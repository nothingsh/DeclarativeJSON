import UIKit

/// The footer of a section with `more`: a spinner while the next items load,
/// or a button that tries again after loading them failed.
final class LoadMoreFooter: UICollectionReusableView {
    static let kind = "DeclarativeJSON.loadMore"

    let spinner = UIActivityIndicatorView(style: .medium)
    let retryButton = UIButton(type: .system)
    private var retry: (() -> Void)?

    override init(frame: CGRect) {
        super.init(frame: frame)
        retryButton.setImage(UIImage(systemName: "arrow.clockwise"), for: .normal)
        retryButton.accessibilityLabel = "Try Again"
        retryButton.addTarget(self, action: #selector(tapRetry), for: .touchUpInside)
        for view in [spinner, retryButton] {
            view.translatesAutoresizingMaskIntoConstraints = false
            addSubview(view)
            NSLayoutConstraint.activate([
                view.centerXAnchor.constraint(equalTo: centerXAnchor),
                view.centerYAnchor.constraint(equalTo: centerYAnchor),
            ])
        }
        let height = heightAnchor.constraint(equalToConstant: 44)
        // Below required, so that it gives way to the layout's first guess.
        height.priority = .defaultHigh
        height.isActive = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("LoadMoreFooter is created in code")
    }

    func show(failed: Bool, retry: @escaping () -> Void) {
        self.retry = retry
        retryButton.isHidden = !failed
        if failed {
            spinner.stopAnimating()
        } else {
            spinner.startAnimating()
        }
    }

    @objc private func tapRetry() {
        retry?()
    }
}
