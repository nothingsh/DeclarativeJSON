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

    /// The page's colors, fonts and images.
    var theme: Theme {
        themeValue as? Theme ?? .standard
    }

    /// A color: a name in the theme, such as `"secondaryLabel"` or
    /// `"systemBlue"`, `"#RRGGBB"` or `"#RRGGBBAA"`, or an object with a
    /// `"light"` and a `"dark"` color in either of those forms.
    func color(_ name: String) -> AnyPublisher<UIColor?, Never>? {
        let theme = theme
        return value(name, expected: .color, read: theme.color(_:))
    }

    /// A font: a name in the theme, such as `"headline"`, or an object with
    /// a `"size"` and an optional `"weight"` such as `"semibold"`, whose size
    /// is that at the default text size. Both follow Dynamic Type.
    func font(_ name: String) -> AnyPublisher<UIFont?, Never>? {
        themeFont(name)?.map { $0?.font() }.eraseToAnyPublisher()
    }

    /// An image named in the theme, or in the app's asset catalog, or an SF
    /// Symbol. A name that is none of them is reported.
    func image(_ name: String) -> AnyPublisher<UIImage?, Never>? {
        let theme = theme
        return string(name)?.map { [report, path] imageName -> UIImage? in
            guard let imageName else { return nil }
            guard let image = theme.image(imageName) else {
                report(Issue(.unknownImage(imageName), at: path))
                return nil
            }
            return image
        }.eraseToAnyPublisher()
    }

    /// Insets: one length for every edge, or an object with any of `top`,
    /// `leading`, `bottom`, `trailing`, `horizontal` and `vertical`, where an
    /// edge wins over its axis. Edges not given are 0.
    func insets(_ name: String) -> AnyPublisher<NSDirectionalEdgeInsets?, Never>? {
        value(name, expected: .insets, read: NSDirectionalEdgeInsets.init(json:))
    }
}

@MainActor
extension BuildContext {

    /// A font as `font(_:)` reads it, to read again when the text size
    /// changes.
    func themeFont(_ name: String) -> AnyPublisher<Theme.Font?, Never>? {
        let theme = theme
        return value(name, expected: .font, read: theme.font(_:))
    }
}

private let weights: [String: UIFont.Weight] = [
    "ultraLight": .ultraLight, "thin": .thin, "light": .light, "regular": .regular,
    "medium": .medium, "semibold": .semibold, "bold": .bold, "heavy": .heavy, "black": .black,
]

extension Theme {

    /// A color as written: a name, a hex color, or a light and a dark one.
    func color(_ json: JSONValue) -> UIColor? {
        switch json {
        case .string(let string):
            return color(named: string)
        case .object(let object):
            guard object.count == 2, case .string(let light)? = object["light"], case .string(let dark)? = object["dark"],
                  let lightColor = color(named: light), let darkColor = color(named: dark) else { return nil }
            return UIColor { $0.userInterfaceStyle == .dark ? darkColor : lightColor }
        default:
            return nil
        }
    }

    private func color(named string: String) -> UIColor? {
        if let color = colors[string] { return color }
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

    /// A font as written: a name, or a size with an optional weight.
    func font(_ json: JSONValue) -> Font? {
        switch json {
        case .string(let name):
            return fonts[name]
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
            // Scaled as body text is, as an Android sp is.
            return .custom(.systemFont(ofSize: CGFloat(size), weight: weight))
        default:
            return nil
        }
    }
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
