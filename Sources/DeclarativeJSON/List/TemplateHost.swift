import Combine
import DeclarativeUIKit
import UIKit

/// What a template's data belongs to: an item, or a section's header.
enum TemplateKey: Hashable {
    case item(String)
    case header(String)
}

public extension ActionContext {
    /// The view that sent the event, such as an anchor for a popover. Nil
    /// when the view is gone.
    var sourceView: UIView? { source as? UIView }
    /// The page that shows the item. Nil when the page is gone.
    var page: DocumentViewController? { owner as? DocumentViewController }
}

extension ItemInfo {
    var key: TemplateKey { id.map(TemplateKey.item) ?? .header(section) }
}

/// The view tree of a template in a cell or a header, built when the cell is
/// first shown and kept across reuse. Showing another item only sends its
/// data. A template whose content changed with a new document is built again.
@MainActor
final class TemplateHost {
    private let data = CurrentValueSubject<[String: JSONValue], Never>([:])
    private var item: ItemInfo?
    private var built: (template: Node, view: UIView)?

    func show(
        _ template: Node,
        path: String,
        item: ItemInfo,
        data: [String: JSONValue],
        in container: UIView,
        page: DocumentViewController
    ) {
        self.item = item
        if built?.template != template {
            built?.view.removeFromSuperview()
            let builder = NodeBuilder(
                components: page.components,
                actions: page.actions,
                data: self.data,
                // The item shown when an action runs, which a change it makes
                // later still goes to after this view shows another.
                target: { [weak self, weak page] in
                    guard let item = self?.item else { return nil }
                    return ActionTarget(
                        item: item,
                        page: page,
                        data: { [weak page] in page?.data(item.key) },
                        update: { [weak page] change in page?.update(item.key, change) },
                        tasks: page?.tasks
                    )
                },
                report: { [weak page] in page?.report($0) }
            )
            let view = builder.build(template, path: path)
            container.addContent(view)
            built = (template, view)
        }
        self.data.send(data)
    }
}

final class TemplateCell: UICollectionViewCell {
    let host = TemplateHost()
}

final class TemplateHeader: UICollectionReusableView {
    let host = TemplateHost()
}
