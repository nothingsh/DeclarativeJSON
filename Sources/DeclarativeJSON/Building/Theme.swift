import UIKit

/// The colors, fonts and images that a document names, such as
/// `"secondaryLabel"`, `"headline"` or `"heart.fill"`.
///
/// `standard` has the system colors and text styles under their UIKit names,
/// and no images. Replace a name to restyle every document that uses it, or
/// add your own names:
///
/// ```swift
/// var theme = Theme.standard
/// theme.colors["brand.primary"] = UIColor(named: "BrandPrimary")
/// theme.colors["secondaryLabel"] = UIColor(named: "Subtitle")
/// theme.fonts["price"] = .custom(.systemFont(ofSize: 20, weight: .bold))
/// theme.images["heart.fill"] = UIImage(systemName: "heart.fill")
/// let page = DocumentViewController(document: document, theme: theme)
/// ```
///
/// An image name that the theme does not have is looked up in the app's
/// asset catalog, and then as an SF Symbol. A document written for other
/// platforms too should use only the theme's names.
public struct Theme {
    /// Colors by name. A dynamic color follows light and dark mode.
    public var colors: [String: UIColor]
    public var fonts: [String: Font]
    public var images: [String: UIImage]

    public init(colors: [String: UIColor] = [:], fonts: [String: Font] = [:], images: [String: UIImage] = [:]) {
        self.colors = colors
        self.fonts = fonts
        self.images = images
    }

    /// A font that follows the user's text size.
    public struct Font {
        private let make: (UITraitCollection?) -> UIFont

        /// The text style's font, as `UIFont.preferredFont(forTextStyle:)`
        /// gives it.
        public static func textStyle(_ style: UIFont.TextStyle) -> Font {
            Font { .preferredFont(forTextStyle: style, compatibleWith: $0) }
        }

        /// `font` at the default text size, growing and shrinking with the
        /// user's text size as `style` does.
        public static func custom(_ font: UIFont, relativeTo style: UIFont.TextStyle = .body) -> Font {
            Font { UIFontMetrics(forTextStyle: style).scaledFont(for: font, compatibleWith: $0) }
        }

        /// The font at the text size of `traits`, or of the app without them.
        public func font(compatibleWith traits: UITraitCollection? = nil) -> UIFont {
            make(traits)
        }
    }

    /// The system colors and text styles under their UIKit names, such as
    /// `secondaryLabel`, `systemBlue` and `caption1`, and no images.
    public static var standard: Theme {
        Theme(
            colors: [
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
                "systemGreen": .systemGreen, "systemMint": .systemMint, "systemTeal": .systemTeal,
                "systemCyan": .systemCyan, "systemBlue": .systemBlue, "systemIndigo": .systemIndigo,
                "systemPurple": .systemPurple, "systemPink": .systemPink, "systemBrown": .systemBrown,
                "systemGray": .systemGray, "systemGray2": .systemGray2, "systemGray3": .systemGray3,
                "systemGray4": .systemGray4, "systemGray5": .systemGray5, "systemGray6": .systemGray6,
                "clear": .clear, "black": .black, "white": .white,
            ],
            fonts: [
                "largeTitle": .textStyle(.largeTitle), "title1": .textStyle(.title1), "title2": .textStyle(.title2),
                "title3": .textStyle(.title3), "headline": .textStyle(.headline),
                "subheadline": .textStyle(.subheadline), "body": .textStyle(.body), "callout": .textStyle(.callout),
                "footnote": .textStyle(.footnote), "caption1": .textStyle(.caption1),
                "caption2": .textStyle(.caption2),
            ]
        )
    }

    /// The image named `name`: the theme's, or else one in the app's asset
    /// catalog, or else an SF Symbol.
    func image(_ name: String) -> UIImage? {
        images[name] ?? UIImage(named: name) ?? UIImage(systemName: name)
    }
}

extension Manifest {

    /// The manifest of a page with these components, actions and theme, which
    /// lists the theme's names of colors, fonts and images.
    public init(components: ComponentRegistry<UIView>, actions: ActionRegistry, theme: Theme = .standard) {
        self.init(
            components: components.specs,
            actions: actions.specs,
            colors: Array(theme.colors.keys),
            fonts: Array(theme.fonts.keys),
            images: Array(theme.images.keys)
        )
    }
}
