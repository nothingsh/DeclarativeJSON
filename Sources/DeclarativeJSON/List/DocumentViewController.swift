import Combine
import UIKit

/// A section as shown: its layout and header, after the document's sections
/// and items were checked.
private struct ShownSection {
    let id: String
    let layout: Document.Layout
    let header: (template: String, path: String)?
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
/// is reused, until `setDocument` replaces the data.
public final class DocumentViewController: UIViewController {
    public let components: ComponentRegistry<UIView>
    public let actions: ActionRegistry
    public private(set) var document: Document

    /// Called once with each distinct problem in the current document, when
    /// the page is shown or the part at fault is first built.
    public var onIssue: ((Issue) -> Void)?

    public private(set) lazy var collectionView = UICollectionView(frame: .zero, collectionViewLayout: makeLayout())

    private var dataSource: UICollectionViewDiffableDataSource<String, String>?
    private var sections: [ShownSection] = []
    private var items: [String: (template: String, path: String, section: String)] = [:]
    private var data: [TemplateKey: [String: JSONValue]] = [:]
    private var reportedIssues: Set<Issue> = []
    private var registeredTemplates: Set<String> = []

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
            guard let header = section.header else { return nil }
            let view = collectionView.dequeueReusableSupplementaryView(
                ofKind: kind, withReuseIdentifier: header.template, for: indexPath
            )
            configure(view, section: section)
            return view
        }
        self.dataSource = dataSource
        apply(document, animatingDifferences: false)
    }

    /// Shows another document, such as a newer version of the page. Items and
    /// sections are matched by `id`; local changes from `set` and `toggle` are
    /// replaced by the new document's data.
    public func setDocument(_ document: Document, animatingDifferences: Bool = true) {
        self.document = document
        reportedIssues = []
        if isViewLoaded {
            apply(document, animatingDifferences: animatingDifferences)
        }
    }

    private func apply(_ document: Document, animatingDifferences: Bool) {
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
                    data[.header(section.id)] = written.data
                } else {
                    report(Issue(.unknownTemplate(written.template), at: "\(sectionPath).header"))
                }
            }
            sections.append(ShownSection(id: section.id, layout: section.layout, header: header))
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
                    data[.item(item.id)] = item.data
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
            }
            if shown.header != nil {
                section.boundarySupplementaryItems = [NSCollectionLayoutBoundarySupplementaryItem(
                    layoutSize: NSCollectionLayoutSize(widthDimension: .fractionalWidth(1), heightDimension: .estimated(44)),
                    elementKind: UICollectionView.elementKindSectionHeader,
                    alignment: .top
                )]
            }
            return section
        }
    }
}
