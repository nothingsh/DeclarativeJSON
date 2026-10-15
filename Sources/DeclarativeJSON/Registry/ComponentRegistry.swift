import Foundation

/// The component types a page can use: what each accepts, and how it builds
/// its view.
///
/// ```swift
/// var components = ComponentRegistry<UIView>.standard
/// components.register(ComponentSpec("rating", properties: ["value": PropertySpec(.number)])) { context in
///     RatingView().onValue(context.number("value")) { $0.value = $1 ?? 0 }
/// }
/// ```
///
/// Registering a type that is already there replaces it. The common
/// properties, such as `padding` and `isHidden`, are applied to every
/// component's view after it is built.
public struct ComponentRegistry<View> {
    public typealias Build = @MainActor (BuildContext<View>) -> View

    private var components: [String: (spec: ComponentSpec, build: Build)] = [:]

    public init() {}

    public mutating func register(_ spec: ComponentSpec, build: @escaping Build) {
        components[spec.type] = (spec, build)
    }

    /// Every registered component, sorted by type.
    public var specs: [ComponentSpec] {
        components.values.map(\.spec).sorted { $0.type < $1.type }
    }

    func component(_ type: String) -> (spec: ComponentSpec, build: Build)? {
        components[type]
    }
}
