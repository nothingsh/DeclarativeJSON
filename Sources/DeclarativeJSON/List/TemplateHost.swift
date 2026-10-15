import Combine
import DeclarativeUIKit
import UIKit

/// What a template's data belongs to: an item, or a section's header.
enum TemplateKey: Hashable {
    case item(String)
    case header(String)
}

/// The view tree of a template in a cell or a header, built when the cell is
/// first shown and kept across reuse. Showing another item only sends its
/// data. A template whose content changed with a new document is built again.
@MainActor
final class TemplateHost {
    private let data = CurrentValueSubject<[String: JSONValue], Never>([:])
    private var key: TemplateKey?
    private var built: (template: Node, view: UIView)?

    func show(
        _ template: Node,
        path: String,
        key: TemplateKey,
        data: [String: JSONValue],
        in container: UIView,
        page: DocumentViewController
    ) {
        self.key = key
        if built?.template != template {
            built?.view.removeFromSuperview()
            let builder = NodeBuilder(
                components: page.components,
                actions: page.actions,
                data: self.data,
                update: { [weak self, weak page] data in
                    guard let self, let key = self.key else { return }
                    page?.update(data, for: key) { self.data.send(data) }
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
