import UIKit

/// The view below a list or grid section with `more`, which shows that the
/// section's next items are loading, or that loading them failed.
///
/// The page makes one for each footer it shows with
/// `DocumentViewController.makeLoadMoreView`, and reuses it for other
/// sections. It sizes itself with Auto Layout.
@MainActor
public protocol LoadMoreView: UIView {
    /// Shows that the section's next items are loading.
    func showLoading()
    /// Shows that loading them failed. `retry` asks for them again.
    func showFailure(retry: @escaping () -> Void)
}

/// The footer of a section with `more`; it shows a `LoadMoreView`.
final class LoadMoreFooter: UICollectionReusableView {
    static let kind = "DeclarativeJSON.loadMore"

    private(set) var content: LoadMoreView?
    /// The `makeLoadMoreView` that made `content`, by the page's count of them.
    private var generation = -1

    /// Shows the page's current kind of view in the given state.
    func show(failed: Bool, retry: @escaping () -> Void, make: () -> LoadMoreView, generation: Int) {
        if content == nil || self.generation != generation {
            content?.removeFromSuperview()
            let view = make()
            view.translatesAutoresizingMaskIntoConstraints = false
            addSubview(view)
            NSLayoutConstraint.activate([
                view.topAnchor.constraint(equalTo: topAnchor),
                view.bottomAnchor.constraint(equalTo: bottomAnchor),
                view.leadingAnchor.constraint(equalTo: leadingAnchor),
                view.trailingAnchor.constraint(equalTo: trailingAnchor),
            ])
            content = view
            self.generation = generation
        }
        if failed {
            content?.showFailure(retry: retry)
        } else {
            content?.showLoading()
        }
    }
}

/// The library's `LoadMoreView`: a spinner, or a button that tries again.
final class DefaultLoadMoreView: UIView, LoadMoreView {
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
        fatalError("DefaultLoadMoreView is created in code")
    }

    func showLoading() {
        retry = nil
        retryButton.isHidden = true
        spinner.startAnimating()
    }

    func showFailure(retry: @escaping () -> Void) {
        self.retry = retry
        retryButton.isHidden = false
        spinner.stopAnimating()
    }

    @objc private func tapRetry() {
        retry?()
    }
}
