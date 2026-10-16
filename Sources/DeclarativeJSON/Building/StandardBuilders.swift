import Combine
import DeclarativeCombine
import DeclarativeUIKit
import UIKit

// The alignment enums of DeclarativeUIKit are not Sendable, so the tables
// belong to the main actor.
@MainActor private let horizontalAlignments: [String: HorizontalAlignment] = [
    "leading": .leading, "center": .center, "trailing": .trailing, "fill": .fill,
]
@MainActor private let verticalAlignments: [String: VerticalAlignment] = [
    "top": .top, "center": .center, "bottom": .bottom,
    "firstTextBaseline": .firstTextBaseline, "lastTextBaseline": .lastTextBaseline, "fill": .fill,
]
private let textAlignments: [String: NSTextAlignment] = [
    "natural": .natural, "left": .left, "center": .center, "right": .right, "justified": .justified,
]

/// The image view's current load, so that a new URL cancels it and a late
/// completion is ignored.
@MainActor
private final class ImageLoad {
    var token: AnyCancellable?
    var generation = 0
}

extension ComponentRegistry where View == UIView {

    /// The built-in components, loading images with `URLSession`.
    public static var standard: ComponentRegistry<UIView> {
        standard(imageLoader: .urlSession)
    }

    /// The built-in components, loading images with `imageLoader`.
    public static func standard(imageLoader: ImageLoader) -> ComponentRegistry<UIView> {
        let builders: [String: Build] = [
            "vstack": { context in
                VStack { context.children }
                    .configure(StackLayout.addFiller)
                    .onValue(context.choice("alignment", horizontalAlignments)) { $0.alignment($1 ?? .center) }
                    .onValue(context.number("spacing")) { $0.spacing(CGFloat($1 ?? 0)) }
                    .onTap(context)
            },
            "hstack": { context in
                HStack { context.children }
                    .configure(StackLayout.addFiller)
                    .onValue(context.choice("alignment", verticalAlignments)) { $0.alignment($1 ?? .center) }
                    .onValue(context.number("spacing")) { $0.spacing(CGFloat($1 ?? 0)) }
                    .onTap(context)
            },
            "vscroll": { context in
                VScroll { context.children }
                    .onValue(context.choice("alignment", horizontalAlignments)) { $0.alignment($1 ?? .center) }
                    .onValue(context.number("spacing")) { $0.spacing(CGFloat($1 ?? 0)) }
                    .onValue(context.bool("showsIndicators")) { $0.showsIndicators($1 ?? true) }
                    .onValue(context.bool("bounces")) { $0.bounces($1 ?? true) }
            },
            "hscroll": { context in
                HScroll { context.children }
                    .onValue(context.choice("alignment", verticalAlignments)) { $0.alignment($1 ?? .center) }
                    .onValue(context.number("spacing")) { $0.spacing(CGFloat($1 ?? 0)) }
                    .onValue(context.bool("showsIndicators")) { $0.showsIndicators($1 ?? true) }
                    .onValue(context.bool("bounces")) { $0.bounces($1 ?? true) }
            },
            "spacer": { context in
                // A constant, so the publisher has its value on subscription.
                var minLength: Double?
                _ = context.length("minLength")?.sink { minLength = $0 }
                return Spacer(minLength: CGFloat(minLength ?? 0))
            },
            "label": { context in
                TextLabel()
                    .configure { $0.adjustsFontForContentSizeCategory = true }
                    .onValue(context.string("text")) { $0.plainText = $1 }
                    // `markdown` wins over `text`, which shows in releases without it.
                    .onValue(context.string("markdown")) { $0.markdown = $1 }
                    .onValue(context.length("lineHeight")) { $0.lineHeight = $1 }
                    // As written, to read again when the text size changes.
                    .onValue(context.themeFont("font")) { $0.baseFont = $1 }
                    .onValue(context.color("textColor")) { $0.baseColor = $1 }
                    .onValue(context.integer("numberOfLines")) { $0.numberOfLines = $1 ?? 1 }
                    .onValue(context.choice("textAlignment", textAlignments)) { $0.alignment = $1 ?? .natural }
                    .onValue(context.bool("adjustsFontSizeToFitWidth")) { $0.adjustsFontSizeToFitWidth = $1 ?? false }
            },
            "image": { context in
                let imageView = UIImageView()
                    .onValue(context.choice("contentMode", [
                        "scaleToFill": UIView.ContentMode.scaleToFill, "scaleAspectFit": .scaleAspectFit,
                        "scaleAspectFill": .scaleAspectFill, "center": .center,
                    ])) { $0.contentMode = $1 ?? .scaleToFill }
                let name = context.image("image")
                let url = context.url("url")
                guard name != nil || url != nil else { return imageView }
                // The named image shows until the URL's image arrives, and
                // stays when it cannot be loaded.
                let load = ImageLoad()
                let images = Publishers.CombineLatest(
                    name ?? Just(nil).eraseToAnyPublisher(),
                    url ?? Just(nil).eraseToAnyPublisher()
                )
                return imageView.onValue(images.eraseToAnyPublisher()) { view, images in
                    load.generation += 1
                    load.token = nil
                    view.image = images.0
                    guard let url = images.1 else { return }
                    let generation = load.generation
                    load.token = imageLoader.load(url) { [weak view] image in
                        guard let view, let image, load.generation == generation else { return }
                        view.image = image
                    }
                }
            },
            "button": { context in
                UIButton(type: .system)
                    .onValue(context.string("title")) { $0.title($1) }
                    .onValue(context.color("titleColor")) { $0.titleColor($1) }
                    .onValue(context.image("image")) { $0.image($1) }
                    .onValue(context.bool("isEnabled")) { $0.isEnabled = $1 ?? true }
                    .onEvent(context.action(.onTap), \.tapPublisher)
            },
            "textfield": { context in
                UITextField()
                    .configure {
                        $0.borderStyle = .roundedRect
                        $0.adjustsFontForContentSizeCategory = true
                    }
                    // Only a different text: setting the text being typed, as
                    // `set` in onChange does, would end the input method's
                    // composition.
                    .onValue(context.string("text")) { if $0.text != $1 ?? "" { $0.text = $1 } }
                    .onValue(context.string("placeholder")) { $0.placeholder = $1 }
                    .onValue(context.font("font")) { $0.font = $1 }
                    .onValue(context.color("textColor")) { $0.textColor = $1 }
                    .onValue(context.choice("textAlignment", textAlignments)) { $0.textAlignment = $1 ?? .natural }
                    .onValue(context.choice("keyboardType", [
                        "default": UIKeyboardType.default, "emailAddress": .emailAddress, "numberPad": .numberPad,
                        "decimalPad": .decimalPad, "phonePad": .phonePad, "URL": .URL,
                    ])) { $0.keyboardType = $1 ?? .default }
                    .onValue(context.choice("returnKeyType", [
                        "default": UIReturnKeyType.default, "go": .go, "next": .next, "done": .done,
                        "search": .search, "send": .send,
                    ])) { $0.returnKeyType = $1 ?? .default }
                    .onValue(context.bool("isSecureTextEntry")) { $0.isSecureTextEntry = $1 ?? false }
                    .onValue(context.bool("isEnabled")) { $0.isEnabled = $1 ?? true }
                    .onEvent(context.action(.onChange), \.textPublisher) { .string($0) }
                    .onEvent(context.action(.onReturn), \.returnPublisher)
            },
            "switch": { context in
                UISwitch()
                    .onValue(context.bool("isOn")) { $0.isOn = $1 ?? false }
                    .onValue(context.color("onTintColor")) { $0.onTintColor = $1 }
                    .onValue(context.bool("isEnabled")) { $0.isEnabled = $1 ?? true }
                    .onEvent(context.action(.onChange), \.isOnPublisher) { .bool($0) }
            },
            "slider": { context in
                // The range before the value, which the slider clamps to it.
                UISlider()
                    .onValue(context.number("minimumValue")) { $0.minimumValue = Float($1 ?? 0) }
                    .onValue(context.number("maximumValue")) { $0.maximumValue = Float($1 ?? 1) }
                    .onValue(context.number("value")) { $0.value = Float($1 ?? 0) }
                    .onValue(context.color("minimumTrackTintColor")) { $0.minimumTrackTintColor = $1 }
                    .onValue(context.color("maximumTrackTintColor")) { $0.maximumTrackTintColor = $1 }
                    .onValue(context.bool("isEnabled")) { $0.isEnabled = $1 ?? true }
                    .onEvent(context.action(.onChange), \.valuePublisher) { .number(Double($0)) }
            },
            "progress": { context in
                UIProgressView(progressViewStyle: .default)
                    .onValue(context.number("progress")) { $0.progress = Float($1 ?? 0) }
                    .onValue(context.color("progressTintColor")) { $0.progressTintColor = $1 }
                    .onValue(context.color("trackTintColor")) { $0.trackTintColor = $1 }
            },
            "activity": { context in
                UIActivityIndicatorView(style: .medium)
                    .onValue(context.bool("hidesWhenStopped")) { $0.hidesWhenStopped = $1 ?? true }
                    .onValue(context.bool("isAnimating")) { $0.isAnimating($1 ?? false) }
                    .onValue(context.color("color")) { $0.color = $1 ?? .gray }
            },
        ]

        var registry = ComponentRegistry<UIView>()
        for spec in ComponentSpec.standard {
            guard let build = builders[spec.type] else {
                preconditionFailure("No builder for the standard component \(spec.type)")
            }
            registry.register(spec, build: build)
        }
        return registry
    }
}

@MainActor
private extension UIStackView {

    /// Runs the stack's `onTap` when anywhere in it is tapped, except on a
    /// control inside it, which keeps its own taps, and highlights the stack
    /// while it is pressed unless `highlight` is false. With an
    /// `accessibilityLabel`, VoiceOver reads the stack as one button.
    func onTap(_ context: BuildContext<UIView>) -> Self {
        guard let action = context.action(.onTap) else { return self }
        let press = PressHighlight()
        background { press.highlight }
        addGestureRecognizer(press)
        onValue(context.bool("highlight")) { _, highlight in press.isEnabled = highlight ?? true }
        accessibilityTraits.insert(.button)
        isAccessibilityElement = context.node.properties["accessibilityLabel"] != nil
        return onEvent(action, { $0.gesturePublisher(makeTapRecognizer()) })
    }
}

/// Makes the recognizer of a stack's `onTap`. Tests replace it with one whose
/// action they can send, which a test process without touches cannot.
@MainActor
var makeTapRecognizer: () -> UITapGestureRecognizer = { UITapGestureRecognizer() }
