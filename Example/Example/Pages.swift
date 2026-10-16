import DeclarativeJSON
import UIKit

/// Opens the documents bundled with the app, where a real app would fetch
/// them from its server, and handles what they ask the app to do.
@MainActor
final class Pages {
    weak var navigationController: UINavigationController?

    private let titles = [
        "home": "DeclarativeJSON", "store": "Store", "settings": "Settings", "feed": "Feed", "empty": "Empty",
    ]
    private var components = ComponentRegistry<UIView>.standard
    private var actions = ActionRegistry.standard
    /// The files whose first load fails, to show the retry buttons.
    private var failingOnce: Set<String> = ["feed", "feed-3"]

    init() {
        components.register(.rating, build: buildRating)

        // The router: example://store opens store.json.
        actions.register(.navigate) { [weak self] context in
            if let url = context.url("url") { self?.open(url) }
        }
        actions.register(.openURL) { context in
            if let url = context.url("url") { UIApplication.shared.open(url) }
        }
        // Waits as for a request; the document shows a spinner meanwhile.
        actions.register(ActionSpec("addToCart", parameters: ["name": PropertySpec(.string)])) { [weak self] context in
            try await Task.sleep(nanoseconds: 1_000_000_000)
            self?.showAlert(title: "Added to the cart", message: context.string("name"))
        }
        actions.register(ActionSpec("showProduct", parameters: [
            "name": PropertySpec(.string), "price": PropertySpec(.string),
        ])) { [weak self] context in
            self?.showAlert(title: context.string("name"), message: context.string("price"))
        }
    }

    func open(_ url: URL) {
        guard url.scheme == "example", let name = url.host else {
            print("No page for \(url)")
            return
        }
        if name == "feed" {
            return push(feed(), name: name)
        }
        guard let file = Bundle.main.url(forResource: name, withExtension: "json"),
              let document = try? DocumentDecoder().decode(Data(contentsOf: file)) else {
            print("No page for \(url)")
            return
        }
        push(DocumentViewController(document: document, components: components, actions: actions), name: name)
    }

    private func push(_ controller: DocumentViewController, name: String) {
        controller.title = titles[name]
        controller.onIssue = { print("\(name).json: \($0)") }
        navigationController?.pushViewController(controller, animated: navigationController?.topViewController != nil)
    }

    /// A page loaded as from a server: it shows a spinner, then the first
    /// page of posts, loads the next pages as patches named by `more`, and
    /// loads the first page again when pulled down.
    private func feed() -> DocumentViewController {
        let controller = DocumentViewController(components: components, actions: actions)
        load(into: controller)
        controller.onLoadMore = { [weak self, weak controller] section, more in
            guard case .string(let name) = more else { return }
            Task {
                do {
                    let data = try await self?.fetch(name) ?? Data()
                    controller?.apply(try DocumentDecoder().decodePatch(data))
                } catch {
                    controller?.showLoadMoreFailure(in: section)
                }
            }
        }
        controller.onRefresh = { [weak self, weak controller] done in
            Task {
                if let data = try? await self?.fetch("feed"), let document = try? DocumentDecoder().decode(data) {
                    controller?.setDocument(document)
                }
                done()
            }
        }
        return controller
    }

    private func load(into controller: DocumentViewController) {
        Task { [weak self, weak controller] in
            do {
                let data = try await self?.fetch("feed") ?? Data()
                controller?.setDocument(try DocumentDecoder().decode(data), animatingDifferences: false)
            } catch {
                controller?.showFailure { [weak self, weak controller] in
                    if let self, let controller { load(into: controller) }
                }
            }
        }
    }

    /// Reads a bundled file a second late, as a request would.
    private func fetch(_ name: String) async throws -> Data {
        try await Task.sleep(nanoseconds: 1_000_000_000)
        if failingOnce.remove(name) != nil {
            throw URLError(.notConnectedToInternet)
        }
        guard let file = Bundle.main.url(forResource: name, withExtension: "json") else {
            throw URLError(.fileDoesNotExist)
        }
        return try Data(contentsOf: file)
    }

    private func showAlert(title: String?, message: String?) {
        let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .default))
        navigationController?.present(alert, animated: true)
    }
}
