import UIKit

/// The test process cannot deliver touches, so this records the targets of
/// the recognizer and `fire()` calls them directly.
final class RecordingTapRecognizer: UITapGestureRecognizer {
    private var targets: [(target: NSObject, action: Selector)] = []

    override func addTarget(_ target: Any, action: Selector) {
        targets.append((target as! NSObject, action))
        super.addTarget(target, action: action)
    }

    override func removeTarget(_ target: Any?, action: Selector?) {
        targets.removeAll { $0.target === target as AnyObject? && $0.action == action }
        super.removeTarget(target, action: action)
    }

    func fire() {
        for (target, action) in targets {
            target.perform(action)
        }
    }
}
