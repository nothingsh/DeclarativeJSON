import DeclarativeJSON
import UIKit

/// Opens the documents bundled with the app, where a real app would fetch
/// them from its server, and handles what they ask the app to do.
@MainActor
final class Pages {
    weak var navigationController: UINavigationController?

    private let titles = ["home": "DeclarativeJSON", "store": "Store", "settings": "Settings"]
    private var components = ComponentRegistry<UIView>.standard
    private var actions = ActionRegistry.standard

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
        guard url.scheme == "example", let name = url.host,
              let file = Bundle.main.url(forResource: name, withExtension: "json"),
              let document = try? DocumentDecoder().decode(Data(contentsOf: file)) else {
            print("No page for \(url)")
            return
        }
        let controller = DocumentViewController(document: document, components: components, actions: actions)
        controller.title = titles[name]
        controller.onIssue = { print("\(name).json: \($0)") }
        navigationController?.pushViewController(controller, animated: navigationController?.topViewController != nil)
    }

    private func showAlert(title: String?, message: String?) {
        let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .default))
        navigationController?.present(alert, animated: true)
    }
}
