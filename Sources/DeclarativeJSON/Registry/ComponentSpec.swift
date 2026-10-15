import Foundation

/// The kind of value a property takes.
public indirect enum PropertyType: Equatable, Sendable {
    case number
    case integer
    case bool
    case string
    case url
    case color
    case font
    /// A length for every edge, or an object with any of `top`, `leading`,
    /// `bottom`, `trailing`, `horizontal` and `vertical`.
    case insets
    /// One of these strings.
    case oneOf([String])
    /// An object with these keys, as for a modifier with labeled arguments.
    case object([String: PropertyType])
}

/// A property a component accepts.
public struct PropertySpec: Equatable, Sendable {
    public let type: PropertyType
    /// Whether the value can be a `$` reference to the item's data. A property
    /// that is read only when the view is created cannot.
    public let acceptsReference: Bool

    public init(_ type: PropertyType, acceptsReference: Bool = true) {
        self.type = type
        self.acceptsReference = acceptsReference
    }
}

/// An event a component sends, whose value is an action or a list of actions.
public enum EventName: String, CaseIterable, Sendable {
    case onTap, onChange, onReturn
}

/// What a component type accepts: its properties besides the common ones, its
/// events, and whether it has children.
public struct ComponentSpec: Equatable, Sendable {
    public let type: String
    public let properties: [String: PropertySpec]
    public let events: Set<EventName>
    public let acceptsChildren: Bool

    public init(
        _ type: String,
        properties: [String: PropertySpec] = [:],
        events: Set<EventName> = [],
        acceptsChildren: Bool = false
    ) {
        self.type = type
        self.properties = properties
        self.events = events
        self.acceptsChildren = acceptsChildren
    }

    /// The properties every component accepts, applied to whatever view it
    /// builds.
    public static let commonProperties: [String: PropertySpec] = [
        "width": PropertySpec(.number),
        "height": PropertySpec(.number),
        "aspectRatio": PropertySpec(.number),
        "padding": PropertySpec(.insets),
        "background": PropertySpec(.color),
        "cornerRadius": PropertySpec(.number),
        "clipsToBounds": PropertySpec(.bool),
        "border": PropertySpec(.object(["color": .color, "width": .number])),
        "alpha": PropertySpec(.number),
        "tintColor": PropertySpec(.color),
        "isHidden": PropertySpec(.bool),
        // The opposite of isHidden, so that a template can show one view and
        // hide another with the same reference.
        "isVisible": PropertySpec(.bool),
        "accessibilityLabel": PropertySpec(.string),
        "accessibilityIdentifier": PropertySpec(.string),
    ]
}
