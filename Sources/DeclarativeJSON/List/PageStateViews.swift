import UIKit

/// The views a page shows in place of its sections by default: a spinner
/// while it loads, a message with a button that tries again when loading
/// failed, and a message when it has no items.
enum PageStateViews {
    static func loading() -> UIView {
        let spinner = UIActivityIndicatorView(style: .large)
        spinner.startAnimating()
        return centered(spinner)
    }

    static func failure(retry: @escaping () -> Void) -> UIView {
        let button = RetryButton(type: .system)
        button.setTitle("Try Again", for: .normal)
        button.retry = retry
        let stack = UIStackView(arrangedSubviews: [message("Couldn't load this page."), button])
        stack.axis = .vertical
        stack.alignment = .center
        stack.spacing = 8
        return centered(stack)
    }

    static func empty() -> UIView {
        centered(message("Nothing here yet."))
    }

    private static func message(_ text: String) -> UILabel {
        let label = UILabel()
        label.text = text
        label.font = .preferredFont(forTextStyle: .body)
        label.adjustsFontForContentSizeCategory = true
        label.textColor = .secondaryLabel
        label.textAlignment = .center
        label.numberOfLines = 0
        return label
    }

    private static func centered(_ content: UIView) -> UIView {
        let container = UIView()
        content.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(content)
        let margins = container.layoutMarginsGuide
        NSLayoutConstraint.activate([
            content.centerXAnchor.constraint(equalTo: margins.centerXAnchor),
            content.centerYAnchor.constraint(equalTo: margins.centerYAnchor),
            content.leadingAnchor.constraint(greaterThanOrEqualTo: margins.leadingAnchor),
            content.trailingAnchor.constraint(lessThanOrEqualTo: margins.trailingAnchor),
        ])
        return container
    }
}

/// A button that calls a closure, through a target and an action as the
/// library's other controls do.
private final class RetryButton: UIButton {
    var retry: (() -> Void)?

    override init(frame: CGRect) {
        super.init(frame: frame)
        addTarget(self, action: #selector(tap), for: .touchUpInside)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("RetryButton is created in code")
    }

    @objc private func tap() {
        retry?()
    }
}
