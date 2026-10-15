import Foundation

private let horizontalAlignment = PropertyType.oneOf(["leading", "center", "trailing", "fill"])
private let verticalAlignment = PropertyType.oneOf([
    "top", "center", "bottom", "firstTextBaseline", "lastTextBaseline", "fill",
])
private let textAlignment = PropertyType.oneOf(["natural", "left", "center", "right", "justified"])

extension ComponentSpec {

    /// The built-in components. Property names are those of the
    /// DeclarativeUIKit modifiers that set them.
    public static let standard: [ComponentSpec] = [
        ComponentSpec("vstack", properties: [
            "alignment": PropertySpec(horizontalAlignment),
            "spacing": PropertySpec(.number),
        ], acceptsChildren: true),
        ComponentSpec("hstack", properties: [
            "alignment": PropertySpec(verticalAlignment),
            "spacing": PropertySpec(.number),
        ], acceptsChildren: true),
        ComponentSpec("vscroll", properties: [
            "alignment": PropertySpec(horizontalAlignment),
            "spacing": PropertySpec(.number),
            "showsIndicators": PropertySpec(.bool),
            "bounces": PropertySpec(.bool),
        ], acceptsChildren: true),
        ComponentSpec("hscroll", properties: [
            "alignment": PropertySpec(verticalAlignment),
            "spacing": PropertySpec(.number),
            "showsIndicators": PropertySpec(.bool),
            "bounces": PropertySpec(.bool),
        ], acceptsChildren: true),
        ComponentSpec("spacer", properties: [
            // A spacer takes its minimum length when it is created.
            "minLength": PropertySpec(.number, acceptsReference: false),
        ]),
        ComponentSpec("label", properties: [
            "text": PropertySpec(.string),
            "font": PropertySpec(.font),
            "textColor": PropertySpec(.color),
            "numberOfLines": PropertySpec(.integer),
            "textAlignment": PropertySpec(textAlignment),
            "adjustsFontSizeToFitWidth": PropertySpec(.bool),
        ]),
        ComponentSpec("image", properties: [
            // Loaded by the app's image loader.
            "url": PropertySpec(.url),
            // An image in the app's asset catalog, or else an SF Symbol.
            "image": PropertySpec(.string),
            "contentMode": PropertySpec(.oneOf([
                "scaleToFill", "scaleAspectFit", "scaleAspectFill", "center",
            ])),
        ]),
        ComponentSpec("button", properties: [
            "title": PropertySpec(.string),
            "titleColor": PropertySpec(.color),
            "image": PropertySpec(.string),
            "isEnabled": PropertySpec(.bool),
        ], events: [.onTap]),
        ComponentSpec("textfield", properties: [
            "text": PropertySpec(.string),
            "placeholder": PropertySpec(.string),
            "font": PropertySpec(.font),
            "textColor": PropertySpec(.color),
            "textAlignment": PropertySpec(textAlignment),
            "keyboardType": PropertySpec(.oneOf([
                "default", "emailAddress", "numberPad", "decimalPad", "phonePad", "URL",
            ])),
            "returnKeyType": PropertySpec(.oneOf(["default", "go", "next", "done", "search", "send"])),
            "isSecureTextEntry": PropertySpec(.bool),
            "isEnabled": PropertySpec(.bool),
        ], events: [.onChange, .onReturn]),
        ComponentSpec("switch", properties: [
            "isOn": PropertySpec(.bool),
            "onTintColor": PropertySpec(.color),
            "isEnabled": PropertySpec(.bool),
        ], events: [.onChange]),
        ComponentSpec("slider", properties: [
            "value": PropertySpec(.number),
            "minimumValue": PropertySpec(.number),
            "maximumValue": PropertySpec(.number),
            "minimumTrackTintColor": PropertySpec(.color),
            "maximumTrackTintColor": PropertySpec(.color),
            "isEnabled": PropertySpec(.bool),
        ], events: [.onChange]),
        ComponentSpec("progress", properties: [
            "progress": PropertySpec(.number),
            "progressTintColor": PropertySpec(.color),
            "trackTintColor": PropertySpec(.color),
        ]),
        ComponentSpec("activity", properties: [
            "isAnimating": PropertySpec(.bool),
            "hidesWhenStopped": PropertySpec(.bool),
            "color": PropertySpec(.color),
        ]),
    ]
}
