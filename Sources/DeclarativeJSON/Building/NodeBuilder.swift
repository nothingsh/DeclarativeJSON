import Combine
import DeclarativeCombine
import DeclarativeUIKit
import UIKit

/// The layout direction of the app, which an overlay's centered alignments
/// follow. Tests replace it to lay out right to left.
@MainActor
var layoutDirection: () -> UIUserInterfaceLayoutDirection = { UIView.userInterfaceLayoutDirection(for: .unspecified) }

/// One overlay of the `overlay` property.
private struct Overlay {
    static let alignments: [String: LayoutAlignment] = [
        "fill": .fill, "center": .center, "top": .top, "bottom": .bottom,
        "leading": .leading, "trailing": .trailing, "topLeading": .topLeading,
        "topTrailing": .topTrailing, "bottomLeading": .bottomLeading, "bottomTrailing": .bottomTrailing,
    ]

    let alignment: LayoutAlignment
    /// x toward the trailing edge, y toward the bottom.
    let offset: CGPoint
    let content: JSONValue

    /// Reads `{"alignment": ..., "offset": {"x": ..., "y": ...}, "content": node}`,
    /// or returns nil when it is not one. `fill` takes no offset.
    init?(_ json: JSONValue) {
        guard case .object(let object) = json, let content = object["content"],
              Set(object.keys).isSubset(of: ["alignment", "offset", "content"]) else { return nil }
        switch object["alignment"] {
        case nil:
            alignment = .fill
        case .string(let name)?:
            guard let named = Self.alignments[name] else { return nil }
            alignment = named
        case _?:
            return nil
        }
        switch object["offset"] {
        case nil:
            offset = .zero
        case .object(let point)?:
            guard alignment != .fill, Set(point.keys).isSubset(of: ["x", "y"]) else { return nil }
            var coordinates: [String: CGFloat] = [:]
            for key in ["x", "y"] {
                switch point[key] {
                case nil:
                    coordinates[key] = 0
                case .number(let number)? where number.isFinite:
                    coordinates[key] = CGFloat(number)
                case _?:
                    return nil
                }
            }
            offset = CGPoint(x: coordinates["x"] ?? 0, y: coordinates["y"] ?? 0)
        case _?:
            return nil
        }
        self.content = content
    }

    /// The overlays of a property value: one, or an array of them, each with
    /// its path, or nil for one that is not valid.
    static func list(_ json: JSONValue, path: String) -> [(overlay: Overlay?, path: String)] {
        guard case .array(let elements) = json else { return [(Overlay(json), path)] }
        return elements.enumerated().map { (Overlay($1), "\(path)[\($0)]") }
    }
}

/// Builds the view of a template node once, binding its `$` properties to the
/// item data, so that new data updates the view without building it again.
///
/// `target` returns the item the views show and its update, which an action
/// takes when it runs (see `ActionRunner`); it must not hold the views
/// strongly.
@MainActor
struct NodeBuilder {
    let components: ComponentRegistry<UIView>
    let data: CurrentValueSubject<[String: JSONValue], Never>
    let report: (Issue) -> Void
    private let runner: ActionRunner

    init(
        components: ComponentRegistry<UIView>,
        actions: ActionRegistry,
        data: CurrentValueSubject<[String: JSONValue], Never>,
        target: @escaping () -> ActionTarget?,
        report: @escaping (Issue) -> Void
    ) {
        self.components = components
        self.data = data
        self.report = report
        runner = ActionRunner(actions: actions, data: data, target: target, report: report)
    }

    func build(_ node: Node, path: String) -> UIView {
        guard let component = components.component(node.type) else {
            report(Issue(.unknownType(node.type), at: path))
            return node.fallback.map { build($0, path: "\(path).fallback") } ?? UIView()
        }
        let spec = component.spec

        var properties: [String: PropertyValue] = [:]
        for (name, value) in node.properties.sorted(by: { $0.key < $1.key }) {
            let declared = spec.properties[name] ?? ComponentSpec.commonProperties[name]
            let isEvent = EventName(rawValue: name).map(spec.events.contains) ?? false
            if declared == nil && !isEvent {
                report(Issue(.unknownProperty(name), at: path))
            } else if case .reference = value, isEvent || declared?.acceptsReference == false {
                report(Issue(.referenceNotAccepted(name), at: path))
            } else {
                properties[name] = value
            }
        }

        var children: [UIView] = []
        if spec.acceptsChildren {
            children = node.children.enumerated().map { index, child in
                build(child, path: "\(path).children[\(index)]")
            }
        } else if !node.children.isEmpty {
            report(Issue(.unexpectedChildren, at: path))
        }

        let context = BuildContext<UIView>(
            node: Node(type: node.type, properties: properties),
            children: children,
            path: path,
            data: data.eraseToAnyPublisher(),
            runner: runner,
            report: report
        )
        return applyCommonProperties(to: component.build(context), context)
    }

    /// Applies `ComponentSpec.commonProperties`. A view that is not a stack
    /// gets its padding from a stack around it, which then takes the other
    /// properties, except accessibility, which stays with the view.
    private func applyCommonProperties(to view: UIView, _ context: BuildContext<UIView>) -> UIView {
        var outer = view
        if let padding = context.insets("padding") {
            switch view {
            case let stack as UIStackView:
                stack.onValue(padding) { $0.padding($1 ?? .zero) }
            case let scroll as VScroll:
                scroll.onValue(padding) { $0.padding($1 ?? .zero) }
            case let scroll as HScroll:
                scroll.onValue(padding) { $0.padding($1 ?? .zero) }
            default:
                outer = VStack(alignment: .fill) { view }.onValue(padding) { $0.padding($1 ?? .zero) }
            }
        }

        outer.onValue(context.color("background")) { $0.backgroundColor = $1 }
        outer.onValue(context.length("cornerRadius")) { $0.layer.cornerRadius = CGFloat($1 ?? 0) }
        outer.onValue(context.border("border")) { view, border in
            view.layer.borderColor = border?.color.cgColor
            view.layer.borderWidth = border?.width ?? 0
        }

        outer.onValue(context.length("width")) { view, width in
            if let width {
                view.frame(width: CGFloat(width))
            } else {
                // Removes the width set earlier.
                view.frame(minWidth: nil, maxWidth: .infinity)
            }
        }
        outer.onValue(context.length("height")) { view, height in
            if let height {
                view.frame(height: CGFloat(height))
            } else {
                view.frame(minHeight: nil, maxHeight: .infinity)
            }
        }
        outer.onValue(context.aspectRatio("aspectRatio")) { $0.frame(aspectRatio: $1.map { CGFloat($0) }) }
        outer.onValue(context.number("alpha")) { $0.alpha = CGFloat($1 ?? 1) }
        outer.onValue(context.color("tintColor")) { $0.tintColor = $1 }
        outer.onValue(context.bool("clipsToBounds")) { $0.clipsToBounds = $1 ?? false }

        let isHidden = context.bool("isHidden")
        let isVisible = context.bool("isVisible")
        if isHidden != nil || isVisible != nil {
            let hidden = Publishers.CombineLatest(
                isHidden ?? Just(nil).eraseToAnyPublisher(),
                isVisible ?? Just(nil).eraseToAnyPublisher()
            ).map { isHidden, isVisible in isHidden == true || isVisible == false }
            outer.onValue(hidden.eraseToAnyPublisher()) { $0.isHidden = $1 }
        }

        if case .constant(let json)? = context.node.properties["overlay"] {
            addOverlays(json, to: outer, path: context.path)
        }

        view.onValue(context.string("accessibilityLabel")) { $0.accessibilityLabel = $1 }
        view.onValue(context.string("accessibilityIdentifier")) { $0.accessibilityIdentifier = $1 }
        return outer
    }

    /// Adds the overlays of `json`, later ones further front. An overlay
    /// whose nodes set no event lets touches through to the view behind.
    private func addOverlays(_ json: JSONValue, to view: UIView, path: String) {
        for (overlay, overlayPath) in Overlay.list(json, path: "\(path).overlay") {
            guard let overlay else {
                let type = ComponentSpec.commonProperties["overlay"]?.type ?? .any
                report(Issue(.typeMismatch(property: "overlay", expected: type), at: path))
                continue
            }
            var issues: [Issue] = []
            let node = Node(overlay.content, path: "\(overlayPath).content", issues: &issues)
            issues.forEach(report)
            guard let node else { continue }

            let content = build(node, path: "\(overlayPath).content")
            if node.setsEvent {
                // A label or an image view would keep touches from it.
                view.isUserInteractionEnabled = true
            } else {
                content.isUserInteractionEnabled = false
            }
            // Auto Layout reverses x for the leading and trailing edges in a
            // right-to-left layout, but not for the center.
            var offset = overlay.offset
            if [.center, .top, .bottom].contains(overlay.alignment), layoutDirection() == .rightToLeft {
                offset.x = -offset.x
            }
            view.overlay(alignment: overlay.alignment, offset: offset) { content }
        }
    }
}

private extension Node {

    /// Whether this node, or a node in it, sets an event.
    var setsEvent: Bool {
        if properties.keys.contains(where: { EventName(rawValue: $0) != nil }) { return true }
        if children.contains(where: \.setsEvent) || fallback?.setsEvent == true { return true }
        guard case .constant(let json)? = properties["overlay"] else { return false }
        return Overlay.list(json, path: "").contains { overlay, _ in
            var issues: [Issue] = []
            return overlay.flatMap { Node($0.content, path: "", issues: &issues) }?.setsEvent == true
        }
    }
}

private extension BuildContext {

    /// A number greater than 0.
    func aspectRatio(_ name: String) -> AnyPublisher<Double?, Never>? {
        value(name, expected: .number) { json in
            guard case .number(let number) = json, number.isFinite, number > 0 else { return nil }
            return number
        }
    }

    /// `{"color": ..., "width": ...}`, as for `border(color:width:)`.
    func border(_ name: String) -> AnyPublisher<(color: UIColor, width: CGFloat)?, Never>? {
        guard case .object(let fields)? = ComponentSpec.commonProperties[name]?.type else { return nil }
        return value(name, expected: .object(fields)) { json in
            guard case .object(let object) = json, object.count == 2,
                  let color = object["color"].flatMap(UIColor.parse),
                  case .number(let width)? = object["width"], width.isFinite, width >= 0 else { return nil }
            return (color, CGFloat(width))
        }
    }
}
