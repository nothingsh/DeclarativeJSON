import UIKit
import UIKit.UIGestureRecognizerSubclass

/// Highlights a stack with `onTap` while it is pressed, as a list row is.
///
/// It only watches the touches and never recognizes, so the stack's tap and
/// the scroll view's pan get them as before. The highlight shows after a
/// short delay, so that a touch that starts a scroll does not flash it, and
/// a tap released sooner shows it briefly. A touch that moves away from where
/// it started, or that a control or another highlighted stack inside takes,
/// shows nothing.
@MainActor
final class PressHighlight: UIGestureRecognizer, UIGestureRecognizerDelegate {
    static let delay: TimeInterval = 0.1
    /// As far as a tap can move.
    static let allowableMovement: CGFloat = 10

    /// The view the stack puts behind its content.
    let highlight = UIView()

    private var start: CGPoint?
    private var isPressed = false
    /// Shows the highlight once the delay has passed.
    private var pending: Task<Void, Never>?
    /// Hides the highlight of a tap released before it showed.
    private var fading: Task<Void, Never>?

    override init(target: Any?, action: Selector?) {
        super.init(target: target, action: action)
        cancelsTouchesInView = false
        delaysTouchesEnded = false
        delegate = self
        highlight.backgroundColor = .systemFill
        highlight.isUserInteractionEnabled = false
        highlight.alpha = 0
    }

    override var isEnabled: Bool {
        didSet { if !isEnabled { cancel() } }
    }

    /// Whether a touch in `view` highlights the stack: not when a control or
    /// another highlighted stack between them takes it.
    func highlights(touchesIn view: UIView) -> Bool {
        var current: UIView? = view
        while let candidate = current, candidate !== self.view {
            if candidate is UIControl { return false }
            if candidate.gestureRecognizers?.contains(where: { ($0 as? PressHighlight)?.isEnabled == true }) == true {
                return false
            }
            current = candidate.superview
        }
        return true
    }

    func press() {
        isPressed = true
        fading?.cancel()
        pending = afterDelay { [weak self] in
            self?.pending = nil
            self?.show()
        }
    }

    func release() {
        guard isPressed else { return }
        let wasShown = pending == nil
        stopPress()
        guard !wasShown else { return hide() }
        // A tap released before the highlight showed still shows it briefly.
        // It fades once it has been drawn: a fade that started now would
        // start from what is on screen, which is no highlight.
        show()
        fading = afterDelay { [weak self] in self?.hide() }
    }

    func cancel() {
        guard isPressed else { return }
        stopPress()
        hide()
    }

    private func afterDelay(_ body: @escaping @MainActor () -> Void) -> Task<Void, Never> {
        Task {
            try? await Task.sleep(nanoseconds: UInt64(Self.delay * 1_000_000_000))
            guard !Task.isCancelled else { return }
            body()
        }
    }

    private func stopPress() {
        isPressed = false
        pending?.cancel()
        pending = nil
    }

    private func show() {
        highlight.layer.cornerRadius = view?.layer.cornerRadius ?? 0
        highlight.layer.cornerCurve = view?.layer.cornerCurve ?? .circular
        highlight.layer.removeAllAnimations()
        highlight.alpha = 1
    }

    private func hide() {
        UIView.animate(withDuration: 0.25, delay: 0, options: [.beginFromCurrentState, .allowUserInteraction]) {
            self.highlight.alpha = 0
        }
    }

    // MARK: Touches

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) {
        guard start == nil, let touch = touches.first else { return }
        start = touch.location(in: view)
        press()
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent) {
        guard let start, let location = touches.first?.location(in: view) else { return }
        if hypot(location.x - start.x, location.y - start.y) > Self.allowableMovement {
            cancel()
            state = .failed
        }
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent) {
        release()
        state = .failed
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent) {
        cancel()
        state = .failed
    }

    override func reset() {
        super.reset()
        start = nil
        // Failed by another recognizer, such as a scroll that began.
        cancel()
    }

    // MARK: UIGestureRecognizerDelegate

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
        touch.view.map(highlights(touchesIn:)) ?? false
    }

    func gestureRecognizer(
        _ gestureRecognizer: UIGestureRecognizer,
        shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
    ) -> Bool {
        true
    }
}
