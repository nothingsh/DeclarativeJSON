import Combine
import DeclarativeCombine
import DeclarativeUIKit
import UIKit

/// Builds the view of a template node once, binding its `$` properties to the
/// item data, so that new data updates the view without building it again.
@MainActor
struct NodeBuilder {
    let components: ComponentRegistry<UIView>
    let data: AnyPublisher<[String: JSONValue], Never>
    let report: (Issue) -> Void

    func build(_ node: Node, path: String) -> UIView {
        guard let component = components.component(node.type) else {
            report(Issue(.unknownType(node.type), at: path))
            return UIView()
        }
        let spec = component.spec

        var properties: [String: PropertyValue] = [:]
        for (name, value) in node.properties.sorted(by: { $0.key < $1.key }) {
            let declared = spec.properties[name] ?? ComponentSpec.commonProperties[name]
            let isEvent = EventName(rawValue: name).map(spec.events.contains) ?? false
            if declared == nil && !isEvent {
                report(Issue(.unknownProperty(name), at: path))
            } else if case .reference = value, declared?.acceptsReference == false {
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
            data: data,
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

        view.onValue(context.string("accessibilityLabel")) { $0.accessibilityLabel = $1 }
        view.onValue(context.string("accessibilityIdentifier")) { $0.accessibilityIdentifier = $1 }
        return outer
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
