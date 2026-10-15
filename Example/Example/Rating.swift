import DeclarativeJSON
import UIKit

extension ComponentSpec {

    /// An app's own component: `{"type": "rating", "value": "$rating"}` shows
    /// up to five stars.
    static let rating = ComponentSpec("rating", properties: ["value": PropertySpec(.number)])
}

@MainActor
func buildRating(_ context: BuildContext<UIView>) -> UIView {
    let label = UILabel()
    label.textColor = .systemOrange
    label.font = .preferredFont(forTextStyle: .caption1)
    return label.onValue(context.number("value")) { label, value in
        let stars = min(max(Int((value ?? 0).rounded()), 0), 5)
        label.text = String(repeating: "★", count: stars) + String(repeating: "☆", count: 5 - stars)
        label.accessibilityLabel = "\(stars) out of 5 stars"
    }
}
