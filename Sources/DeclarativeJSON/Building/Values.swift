import Combine
import DeclarativeCombine
import UIKit

@MainActor
public extension PublisherBindable {

    /// Runs `apply` with this view and each value of a property publisher
    /// from `BuildContext`, or does nothing when the node does not set the
    /// property.
    @discardableResult
    func onValue<T>(_ publisher: AnyPublisher<T, Never>?, _ apply: @escaping (Self, T) -> Void) -> Self {
        guard let publisher else { return self }
        return onReceive(publisher, perform: apply)
    }

    /// Runs `action`, from `BuildContext.action(_:)`, with the value of each
    /// event from one of this view's publishers and this view as its source,
    /// or does nothing when the node does not set the event.
    @discardableResult
    func onEvent<P: Publisher>(
        _ action: EventAction?,
        _ publisher: (Self) -> P,
        value: @escaping (P.Output) -> JSONValue? = { _ in nil }
    ) -> Self where P.Failure == Never {
        guard let action else { return self }
        return onReceive(publisher(self)) { view, output in action(value(output), source: view) }
    }
}

@MainActor
public extension BuildContext {

    /// A color: a system color name such as `"secondaryLabel"` or
    /// `"systemBlue"`, `"#RRGGBB"` or `"#RRGGBBAA"`, or an object with a
    /// `"light"` and a `"dark"` color in either of those forms.
    func color(_ name: String) -> AnyPublisher<UIColor?, Never>? {
        value(name, expected: .color, read: UIColor.parse)
    }

    /// A font: a text style such as `"headline"`, which follows Dynamic Type,
    /// or an object with a `"size"` and an optional `"weight"` such as
    /// `"semibold"`.
    func font(_ name: String) -> AnyPublisher<UIFont?, Never>? {
        value(name, expected: .font, read: UIFont.parse)
    }

    /// Insets: one length for every edge, or an object with any of `top`,
    /// `leading`, `bottom`, `trailing`, `horizontal` and `vertical`, where an
    /// edge wins over its axis. Edges not given are 0.
    func insets(_ name: String) -> AnyPublisher<NSDirectionalEdgeInsets?, Never>? {
        value(name, expected: .insets, read: NSDirectionalEdgeInsets.init(json:))
    }
}

extension UIColor {

    static func parse(_ json: JSONValue) -> UIColor? {
        switch json {
        case .string(let string):
            return named(string)
        case .object(let object):
            guard object.count == 2, case .string(let light)? = object["light"], case .string(let dark)? = object["dark"],
                  let lightColor = named(light), let darkColor = named(dark) else { return nil }
            return UIColor { $0.userInterfaceStyle == .dark ? darkColor : lightColor }
        default:
            return nil
        }
    }

    static func named(_ string: String) -> UIColor? {
        if let color = systemColors[string] { return color }
        guard string.hasPrefix("#"), string.count == 7 || string.count == 9,
              let value = UInt64(string.dropFirst(), radix: 16) else { return nil }
        let rgba = string.count == 7 ? value << 8 | 0xFF : value
        return UIColor(
            red: CGFloat(rgba >> 24 & 0xFF) / 255,
            green: CGFloat(rgba >> 16 & 0xFF) / 255,
            blue: CGFloat(rgba >> 8 & 0xFF) / 255,
            alpha: CGFloat(rgba & 0xFF) / 255
        )
    }

    static let systemColors: [String: UIColor] = [
        "label": .label, "secondaryLabel": .secondaryLabel, "tertiaryLabel": .tertiaryLabel,
        "quaternaryLabel": .quaternaryLabel, "placeholderText": .placeholderText, "link": .link,
        "separator": .separator, "opaqueSeparator": .opaqueSeparator,
        "systemBackground": .systemBackground, "secondarySystemBackground": .secondarySystemBackground,
        "tertiarySystemBackground": .tertiarySystemBackground,
        "systemGroupedBackground": .systemGroupedBackground,
        "secondarySystemGroupedBackground": .secondarySystemGroupedBackground,
        "tertiarySystemGroupedBackground": .tertiarySystemGroupedBackground,
        "systemFill": .systemFill, "secondarySystemFill": .secondarySystemFill,
        "tertiarySystemFill": .tertiarySystemFill, "quaternarySystemFill": .quaternarySystemFill,
        "systemRed": .systemRed, "systemOrange": .systemOrange, "systemYellow": .systemYellow,
        "systemGreen": .systemGreen, "systemTeal": .systemTeal, "systemBlue": .systemBlue,
        "systemIndigo": .systemIndigo, "systemPurple": .systemPurple, "systemPink": .systemPink,
        "systemGray": .systemGray, "systemGray2": .systemGray2, "systemGray3": .systemGray3,
        "systemGray4": .systemGray4, "systemGray5": .systemGray5, "systemGray6": .systemGray6,
        "clear": .clear, "black": .black, "white": .white,
    ]
}

private extension UIFont {

    static func parse(_ json: JSONValue) -> UIFont? {
        switch json {
        case .string(let name):
            guard let style = textStyles[name] else { return nil }
            return .preferredFont(forTextStyle: style)
        case .object(let object):
            guard case .number(let size)? = object["size"], size.isFinite, size > 0 else { return nil }
            var weight = UIFont.Weight.regular
            switch object["weight"] {
            case nil:
                break
            case .string(let name)?:
                guard let named = weights[name] else { return nil }
                weight = named
            case _?:
                return nil
            }
            guard Set(object.keys).isSubset(of: ["size", "weight"]) else { return nil }
            return .systemFont(ofSize: CGFloat(size), weight: weight)
        default:
            return nil
        }
    }

    static let textStyles: [String: UIFont.TextStyle] = [
        "largeTitle": .largeTitle, "title1": .title1, "title2": .title2, "title3": .title3,
        "headline": .headline, "subheadline": .subheadline, "body": .body, "callout": .callout,
        "footnote": .footnote, "caption1": .caption1, "caption2": .caption2,
    ]

    static let weights: [String: UIFont.Weight] = [
        "ultraLight": .ultraLight, "thin": .thin, "light": .light, "regular": .regular,
        "medium": .medium, "semibold": .semibold, "bold": .bold, "heavy": .heavy, "black": .black,
    ]
}

private extension NSDirectionalEdgeInsets {

    init?(json: JSONValue) {
        func length(_ value: JSONValue?) -> CGFloat?? {
            guard let value else { return .some(nil) }
            guard case .number(let number) = value, number.isFinite, number >= 0 else { return nil }
            return CGFloat(number)
        }
        switch json {
        case .number:
            guard let all = length(json) ?? nil else { return nil }
            self.init(top: all, leading: all, bottom: all, trailing: all)
        case .object(let object):
            let keys = ["top", "leading", "bottom", "trailing", "horizontal", "vertical"]
            guard Set(object.keys).isSubset(of: keys) else { return nil }
            var lengths: [String: CGFloat] = [:]
            for key in keys {
                guard let value = length(object[key]) else { return nil }
                lengths[key] = value
            }
            let horizontal = lengths["horizontal"] ?? 0
            let vertical = lengths["vertical"] ?? 0
            self.init(
                top: lengths["top"] ?? vertical,
                leading: lengths["leading"] ?? horizontal,
                bottom: lengths["bottom"] ?? vertical,
                trailing: lengths["trailing"] ?? horizontal
            )
        default:
            return nil
        }
    }
}
