import DeclarativeUIKit
import UIKit

/// What the layout rules know of a view built from a node.
@MainActor
final class LayoutInfo {
    /// The node's `layoutPriority`: the lower, the sooner the view gives way
    /// when its stack runs out of space.
    var priority: Double = 0
    /// Whether the view takes the width it is given, as a slider does.
    var fillsWidth = false
    /// The compression resistance ranges a stack last handed down, to hand
    /// down again when a `repeat` changes its children.
    var ranges: (horizontal: ClosedRange<Double>, vertical: ClosedRange<Double>)?
}

@MainActor private let layoutInfos = NSMapTable<UIView, LayoutInfo>.weakToStrongObjects()

extension UIView {

    @MainActor var layoutInfo: LayoutInfo {
        if let info = layoutInfos.object(forKey: self) { return info }
        let info = LayoutInfo()
        layoutInfos.setObject(info, forKey: self)
        return info
    }
}

/// The last arranged view of a `vstack` or an `hstack`, which takes the
/// space that its spacers and the views that fill do not, so that the other
/// views keep their own size and the extra space is after them.
final class StackFiller: UIView {

    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false
        // Grows after spacers (50) and before content (250 and up).
        setContentHuggingPriority(UILayoutPriority(100), for: .horizontal)
        setContentHuggingPriority(UILayoutPriority(100), for: .vertical)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    override var intrinsicContentSize: CGSize { .zero }
}

/// Applies the layout rules to stacks:
///
/// - When a stack runs out of space along its axis, the views with the lowest
///   `layoutPriority` give way first, and of those the earliest. A view in a
///   nested stack gives way with its stack. Auto Layout gives way where the
///   compression resistance is lowest, so each view without children gets
///   one from a range that its stacks narrow down by rank.
/// - Extra space goes to the spacers and the views that fill, and else to the
///   stack's `StackFiller`. A stack without either hugs its content, so that
///   the extra space of the stack it is in goes after it rather than into it.
@MainActor
enum StackLayout {
    static let fullRange: ClosedRange<Double> = 500...990
    /// Below the hugging of content, above the filler's, so that a stack with
    /// nothing that grows stays the size of its content.
    private static let hugging = UILayoutPriority(150)
    /// Above the hugging of spacers, so that a view that fills grows first.
    private static let filling = UILayoutPriority(51)
    private static let identifier = "DeclarativeJSON.layout"

    /// Ends `stack` with a filler.
    static func addFiller(to stack: UIStackView) {
        stack.addArrangedSubview(StackFiller())
    }

    /// Applies the rules to `view` and the stacks in it, with the ranges
    /// `view` had, or the full ranges.
    static func apply(to view: UIView) {
        let ranges = view.layoutInfo.ranges
        apply(to: view, horizontal: ranges?.horizontal ?? fullRange, vertical: ranges?.vertical ?? fullRange)
    }

    private static func apply(to view: UIView, horizontal: ClosedRange<Double>, vertical: ClosedRange<Double>) {
        guard let stack = view as? UIStackView else {
            view.setContentCompressionResistancePriority(priority(in: horizontal), for: .horizontal)
            view.setContentCompressionResistancePriority(priority(in: vertical), for: .vertical)
            return
        }
        stack.layoutInfo.ranges = (horizontal, vertical)
        let children = stack.arrangedSubviews.filter { !($0 is StackFiller) }
        let order = children.indices.sorted {
            (children[$0].layoutInfo.priority, $0) < (children[$1].layoutInfo.priority, $1)
        }
        let isHorizontal = stack.axis == .horizontal
        let main = isHorizontal ? horizontal : vertical
        let width = (main.upperBound - main.lowerBound) / Double(max(children.count, 1))
        for (rank, index) in order.enumerated() {
            let lower = main.lowerBound + Double(rank) * width
            let slot = lower...(lower + width)
            apply(to: children[index], horizontal: isHorizontal ? slot : horizontal, vertical: isHorizontal ? vertical : slot)
        }
        constrain(stack, children: children)
    }

    /// The priority in the middle of `range`.
    private static func priority(in range: ClosedRange<Double>) -> UILayoutPriority {
        UILayoutPriority(Float((range.lowerBound + range.upperBound) / 2))
    }

    /// Replaces the constraints of the rules on `stack`: its hugging, and the
    /// growth of the views in it that fill.
    private static func constrain(_ stack: UIStackView, children: [UIView]) {
        for constraint in stack.constraints where constraint.identifier == identifier {
            constraint.isActive = false
        }
        var constraints: [NSLayoutConstraint] = []
        func add(_ constraint: NSLayoutConstraint, _ priority: UILayoutPriority) {
            constraint.priority = priority
            constraint.identifier = identifier
            constraints.append(constraint)
        }
        if !grows(stack, along: .horizontal) {
            add(stack.widthAnchor.constraint(equalToConstant: 0), hugging)
        }
        if !grows(stack, along: .vertical) {
            add(stack.heightAnchor.constraint(equalToConstant: 0), hugging)
        }
        // A view that grows, other than a spacer, is pulled to the stack's
        // size, so that it takes the space it is given across the stack too.
        for view in children where !(view is Spacer) {
            if grows(view, along: .horizontal) {
                add(view.widthAnchor.constraint(equalTo: stack.widthAnchor), Self.filling)
            }
            if grows(view, along: .vertical) {
                add(view.heightAnchor.constraint(equalTo: stack.heightAnchor), Self.filling)
            }
        }
        // A view that fills shares the extra space of a horizontal stack
        // equally with its spacers.
        let filling = children.filter(\.layoutInfo.fillsWidth)
        if stack.axis == .horizontal {
            let sharing = filling + children.filter { $0 is Spacer }
            for (index, view) in filling.enumerated() {
                for other in sharing.dropFirst(index + 1) {
                    add(view.widthAnchor.constraint(equalTo: other.widthAnchor), .defaultLow - 1)
                }
            }
        }
        NSLayoutConstraint.activate(constraints)

        // No spacing before the filler, which would take room when the
        // stack has none to spare.
        if let last = children.last {
            stack.setCustomSpacing(0, after: last)
        }
    }

    /// Whether `view` takes extra space along `axis`: a spacer along its
    /// stack's axis, a view that fills its width, or a stack with one of
    /// them.
    private static func grows(_ view: UIView, along axis: NSLayoutConstraint.Axis) -> Bool {
        if view is Spacer {
            return (view.superview as? UIStackView)?.axis == axis
        }
        if axis == .horizontal && view.layoutInfo.fillsWidth { return true }
        guard let stack = view as? UIStackView else { return false }
        return stack.arrangedSubviews.contains { !($0 is StackFiller) && grows($0, along: axis) }
    }
}
