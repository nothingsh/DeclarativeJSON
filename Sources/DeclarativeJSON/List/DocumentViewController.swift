import Combine
import UIKit

/// A section as shown: its layout and header, after the document's sections
/// and items were checked.
private struct ShownSection {
    let id: String
    let layout: Document.Layout
    let columns: Int
    let spacing: Double
    let header: (template: String, path: String)?
    let more: JSONValue?
}

/// Where loading the items after a section's is at, for a section with
/// `more`. A section not loading has no state.
private enum LoadingMore {
    case loading
    case failed
}

/// Shows a document's sections in a collection view.
///
/// ```swift
/// let document = try DocumentDecoder().decode(data)
/// var actions = ActionRegistry.standard
/// actions.register(.navigate) { context in
///     if let url = context.url("url") { router.open(url) }
/// }
/// let controller = DocumentViewController(document: document, actions: actions)
/// controller.onIssue = { print($0) }
/// ```
///
/// Each cell builds its template's views the first time it is shown and keeps
/// them; showing another item only sends that item's data. `set` and `toggle`
/// change the page's copy of the item's data, so a change stays when the cell
/// is reused, until `setDocument`, or a patch that replaces the item, replaces
/// the data.
///
/// The page is the collection view's delegate and data source; set
/// `scrollViewDelegate` to get the scroll view's callbacks.
public final class DocumentViewController: UIViewController {
    public let components: ComponentRegistry<UIView>
    public let actions: ActionRegistry
    public private(set) var document: Document

    /// Called once with each distinct problem in the current document, when
    /// the page is shown or the part at fault is first built.
    public var onIssue: ((Issue) -> Void)?

    /// Called when the user nears the end of a section with `more`, with the
    /// section's `id` and its `more`. Load the items after it and apply a
    /// patch that appends them with `appendItems`, or call
    /// `showLoadMoreFailure(in:)`. Until then, the section's footer shows a
    /// spinner and the page asks for no more of that section.
    public var onLoadMore: ((_ section: String, _ more: JSONValue) -> Void)?

    /// Gets the collection view's scroll view callbacks, as its delegate
    /// would. The collection view's own delegate is the page.
    public weak var scrollViewDelegate: UIScrollViewDelegate?

    public private(set) lazy var collectionView = UICollectionView(frame: .zero, collectionViewLayout: makeLayout())

    private var dataSource: UICollectionViewDiffableDataSource<String, String>?
    private var sections: [ShownSection] = []
    private var items: [String: (template: String, path: String, section: String)] = [:]
    private var data: [TemplateKey: [String: JSONValue]] = [:]
    private var reportedIssues: Set<Issue> = []
    private var registeredTemplates: Set<String> = []
    private var loadingMore: [String: LoadingMore] = [:]
    private lazy var collectionDelegate = CollectionDelegate(page: self)
    /// The asynchronous actions running for the page, cancelled with it.
    let tasks = ActionTasks()

    public init(
        document: Document,
        components: ComponentRegistry<UIView> = .standard,
        actions: ActionRegistry = .standard
    ) {
        self.document = document
        self.components = components
        self.actions = actions
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("DocumentViewController is created in code")
    }

    public override func loadView() {
        collectionView.backgroundColor = .systemBackground
        collectionView.delegate = collectionDelegate
        collectionView.register(
            LoadMoreFooter.self, forSupplementaryViewOfKind: LoadMoreFooter.kind, withReuseIdentifier: LoadMoreFooter.kind
        )
        view = collectionView
    }

    public override func viewDidLoad() {
        super.viewDidLoad()
        let dataSource = UICollectionViewDiffableDataSource<String, String>(collectionView: collectionView) {
            [unowned self] collectionView, indexPath, id in
            guard let item = items[id] else { return nil }
            let cell = collectionView.dequeueReusableCell(withReuseIdentifier: item.template, for: indexPath)
            configure(cell, id: id)
            return cell
        }
        dataSource.supplementaryViewProvider = { [unowned self] collectionView, kind, indexPath in
            let section = sections[indexPath.section]
            if kind == LoadMoreFooter.kind {
                let footer = collectionView.dequeueReusableSupplementaryView(
                    ofKind: kind, withReuseIdentifier: kind, for: indexPath
                )
                configureFooter(footer, section: section.id)
                return footer
            }
            guard let header = section.header else { return nil }
            let view = collectionView.dequeueReusableSupplementaryView(
                ofKind: kind, withReuseIdentifier: header.template, for: indexPath
            )
            configure(view, section: section)
            return view
        }
        self.dataSource = dataSource
        show(document, animatingDifferences: false)
    }

    /// Shows another document, such as a newer version of the page. Items and
    /// sections are matched by `id`; local changes from `set` and `toggle` are
    /// replaced by the new document's data.
    public func setDocument(_ document: Document, animatingDifferences: Bool = true) {
        self.document = document
        reportedIssues = []
        loadingMore = [:]
        if isViewLoaded {
            show(document, animatingDifferences: animatingDifferences)
            loadMoreIfShown()
        }
    }

    /// Changes part of the page: replaces, inserts and removes the items and
    /// sections the patch names, and adds its templates. Replaced and inserted
    /// items and sections show the patch's data; the others keep the changes
    /// made on the device. What the patch refers to that the page does not
    /// have is skipped and reported to `onIssue`, every time.
    ///
    /// A section the patch appends to, replaces or inserts is no longer
    /// loading, and shows a footer while it has `more`.
    public func apply(_ patch: Patch, animatingDifferences: Bool = true) {
        let result = document.applying(patch)
        document = result.document
        (patch.issues + result.issues).forEach { onIssue?($0) }
        let sectionIDs = Set(document.sections.map(\.id))
        loadingMore = loadingMore.filter { sectionIDs.contains($0.key) && !result.loadedSections.contains($0.key) }
        if isViewLoaded {
            var kept = data
            for id in result.changedItems {
                kept[.item(id)] = nil
            }
            for id in result.changedSections {
                kept[.header(id)] = nil
            }
            show(document, keeping: kept, animatingDifferences: animatingDifferences)
            loadMoreIfShown()
        }
    }

    /// Shows that loading the items after a section's failed: its footer
    /// shows a button that tries again, and so does scrolling back to the end
    /// of the section. A list or a grid has the footer; a carousel tries
    /// again when it is scrolled to its end.
    public func showLoadMoreFailure(in section: String) {
        guard loadingMore[section] == .loading else { return }
        loadingMore[section] = .failed
        reconfigureFooter(of: section)
    }

    /// Shows a document with the data in `kept` in place of its own, for the
    /// items and headers it has.
    private func show(
        _ document: Document,
        keeping kept: [TemplateKey: [String: JSONValue]] = [:],
        animatingDifferences: Bool
    ) {
        document.issues.forEach(report)
        sections = []
        items = [:]
        data = [:]
        var snapshot = NSDiffableDataSourceSnapshot<String, String>()

        for (sectionIndex, section) in document.sections.enumerated() {
            let sectionPath = "sections[\(sectionIndex)]"
            guard !snapshot.sectionIdentifiers.contains(section.id) else {
                report(Issue(.duplicateID(section.id), at: sectionPath))
                continue
            }
            var header: (template: String, path: String)?
            if let written = section.header {
                if document.templates[written.template] != nil {
                    register(written.template)
                    header = (written.template, "templates.\(written.template)")
                    data[.header(section.id)] = kept[.header(section.id)] ?? written.data
                } else {
                    report(Issue(.unknownTemplate(written.template), at: "\(sectionPath).header"))
                }
            }
            sections.append(ShownSection(
                id: section.id, layout: section.layout, columns: section.columns, spacing: section.spacing,
                header: header, more: section.more
            ))
            snapshot.appendSections([section.id])

            for (itemIndex, item) in section.items.enumerated() {
                let itemPath = "\(sectionPath).items[\(itemIndex)]"
                if items[item.id] != nil {
                    report(Issue(.duplicateID(item.id), at: itemPath))
                } else if document.templates[item.template] == nil {
                    report(Issue(.unknownTemplate(item.template), at: itemPath))
                } else {
                    register(item.template)
                    items[item.id] = (item.template, "templates.\(item.template)", section.id)
                    data[.item(item.id)] = kept[.item(item.id)] ?? item.data
                    snapshot.appendItems([item.id])
                }
            }
        }

        dataSource?.apply(snapshot, animatingDifferences: animatingDifferences)
        // The data source configures only the cells it adds; those it keeps
        // show the new data from here.
        reconfigureVisibleViews()
    }

    private func register(_ template: String) {
        guard registeredTemplates.insert(template).inserted else { return }
        collectionView.register(TemplateCell.self, forCellWithReuseIdentifier: template)
        collectionView.register(
            TemplateHeader.self,
            forSupplementaryViewOfKind: UICollectionView.elementKindSectionHeader,
            withReuseIdentifier: template
        )
    }

    private func configure(_ cell: UICollectionViewCell, id: String) {
        guard let cell = cell as? TemplateCell, let item = items[id],
              let template = document.templates[item.template] else { return }
        cell.host.show(
            template, path: item.path, item: ItemInfo(id: id, section: item.section, template: item.template),
            data: data[.item(id)] ?? [:], in: cell.contentView, page: self
        )
    }

    private func configure(_ view: UICollectionReusableView, section: ShownSection) {
        guard let view = view as? TemplateHeader, let header = section.header,
              let template = document.templates[header.template] else { return }
        view.host.show(
            template, path: header.path, item: ItemInfo(id: nil, section: section.id, template: header.template),
            data: data[.header(section.id)] ?? [:], in: view, page: self
        )
    }

    private func configureFooter(_ view: UICollectionReusableView, section: String) {
        guard let footer = view as? LoadMoreFooter else { return }
        footer.show(failed: loadingMore[section] == .failed) { [weak self] in
            guard let self, let index = sections.firstIndex(where: { $0.id == section }) else { return }
            loadMore(index)
        }
    }

    private func reconfigureFooter(of section: String) {
        guard let index = sections.firstIndex(where: { $0.id == section }),
              let footer = collectionView.supplementaryView(
                  forElementKind: LoadMoreFooter.kind, at: IndexPath(item: 0, section: index)
              ) else { return }
        configureFooter(footer, section: section)
    }

    private func reconfigureVisibleViews() {
        guard let dataSource else { return }
        for indexPath in collectionView.indexPathsForVisibleItems {
            if let cell = collectionView.cellForItem(at: indexPath), let id = dataSource.itemIdentifier(for: indexPath) {
                configure(cell, id: id)
            }
        }
        let kind = UICollectionView.elementKindSectionHeader
        for indexPath in collectionView.indexPathsForVisibleSupplementaryElements(ofKind: kind)
        where indexPath.section < sections.count {
            if let view = collectionView.supplementaryView(forElementKind: kind, at: indexPath) {
                configure(view, section: sections[indexPath.section])
            }
        }
        collectionView.collectionViewLayout.invalidateLayout()
    }

    /// The data the page keeps for an item or a header, or nil when the page
    /// does not have it.
    func data(_ key: TemplateKey) -> [String: JSONValue]? {
        data[key]
    }

    /// Changes the data the page keeps for an item or a header, shows it in
    /// the view that shows it now, if any, then sizes the cells again for it.
    /// Returns the changed data, or nil when the page no longer has the item
    /// or the header.
    func update(_ key: TemplateKey, _ change: (inout [String: JSONValue]) -> Void) -> [String: JSONValue]? {
        guard var changed = data[key] else { return nil }
        change(&changed)
        data[key] = changed
        switch key {
        case .item(let id):
            if let indexPath = dataSource?.indexPath(for: id), let cell = collectionView.cellForItem(at: indexPath) {
                configure(cell, id: id)
            }
        case .header(let id):
            let kind = UICollectionView.elementKindSectionHeader
            if let index = sections.firstIndex(where: { $0.id == id }),
               let view = collectionView.supplementaryView(forElementKind: kind, at: IndexPath(item: 0, section: index)) {
                configure(view, section: sections[index])
            }
        }
        collectionView.collectionViewLayout.invalidateLayout()
        return changed
    }

    /// How close to the end of a section a cell is shown when the page asks
    /// for the section's next items.
    static let loadMoreDistance = 5

    func willDisplayItem(at indexPath: IndexPath) {
        if indexPath.item >= collectionView.numberOfItems(inSection: indexPath.section) - Self.loadMoreDistance {
            loadMore(indexPath.section)
        }
    }

    func willDisplayFooter(ofSection index: Int) {
        loadMore(index)
    }

    /// Asks for the next items of the sections whose end shows, after a
    /// document or a patch: cells added below the end may not come into view
    /// to ask. A section whose loading failed waits to be scrolled to or
    /// retried.
    private func loadMoreIfShown() {
        let shown = collectionView.indexPathsForVisibleItems.filter {
            $0.item >= collectionView.numberOfItems(inSection: $0.section) - Self.loadMoreDistance
        }
        let footers = collectionView.indexPathsForVisibleSupplementaryElements(ofKind: LoadMoreFooter.kind)
        for index in Set((shown + footers).map(\.section)) where index < sections.count {
            if loadingMore[sections[index].id] == nil {
                loadMore(index)
            }
        }
    }

    /// Asks the app for the items after a section's, unless they are loading.
    private func loadMore(_ index: Int) {
        guard index < sections.count, let more = sections[index].more else { return }
        let id = sections[index].id
        guard loadingMore[id] != .loading else { return }
        loadingMore[id] = .loading
        reconfigureFooter(of: id)
        // Not from within the collection view's layout or update, where this
        // is called from, in case the app applies a patch right away.
        DispatchQueue.main.async { [weak self] in
            guard let self, loadingMore[id] == .loading else { return }
            onLoadMore?(id, more)
        }
    }

    func report(_ issue: Issue) {
        guard reportedIssues.insert(issue).inserted else { return }
        onIssue?(issue)
    }

    private func makeLayout() -> UICollectionViewLayout {
        UICollectionViewCompositionalLayout { [weak self] index, _ in
            guard let self, index < sections.count else { return nil }
            let shown = sections[index]
            let section: NSCollectionLayoutSection
            switch shown.layout {
            case .list:
                let size = NSCollectionLayoutSize(widthDimension: .fractionalWidth(1), heightDimension: .estimated(44))
                let group = NSCollectionLayoutGroup.vertical(
                    layoutSize: size, subitems: [NSCollectionLayoutItem(layoutSize: size)]
                )
                section = NSCollectionLayoutSection(group: group)
            case .carousel:
                let size = NSCollectionLayoutSize(widthDimension: .estimated(120), heightDimension: .estimated(44))
                let group = NSCollectionLayoutGroup.horizontal(
                    layoutSize: size, subitems: [NSCollectionLayoutItem(layoutSize: size)]
                )
                section = NSCollectionLayoutSection(group: group)
                section.orthogonalScrollingBehavior = .continuous
            case .grid:
                let height = NSCollectionLayoutDimension.estimated(44)
                let group = NSCollectionLayoutGroup.horizontal(
                    layoutSize: NSCollectionLayoutSize(widthDimension: .fractionalWidth(1), heightDimension: height),
                    subitem: NSCollectionLayoutItem(layoutSize: NSCollectionLayoutSize(
                        widthDimension: .fractionalWidth(1 / CGFloat(shown.columns)), heightDimension: height
                    )),
                    count: shown.columns
                )
                group.interItemSpacing = .fixed(CGFloat(shown.spacing))
                section = NSCollectionLayoutSection(group: group)
                section.interGroupSpacing = CGFloat(shown.spacing)
            }
            let size = NSCollectionLayoutSize(widthDimension: .fractionalWidth(1), heightDimension: .estimated(44))
            if shown.header != nil {
                section.boundarySupplementaryItems.append(NSCollectionLayoutBoundarySupplementaryItem(
                    layoutSize: size, elementKind: UICollectionView.elementKindSectionHeader, alignment: .top
                ))
            }
            // A carousel's footer would sit under the row, not at its end.
            if shown.more != nil, shown.layout != .carousel {
                section.boundarySupplementaryItems.append(NSCollectionLayoutBoundarySupplementaryItem(
                    layoutSize: size, elementKind: LoadMoreFooter.kind, alignment: .bottom
                ))
            }
            return section
        }
    }
}
