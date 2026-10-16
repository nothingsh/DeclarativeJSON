import Foundation

/// A problem in a document that does not stop the page from showing: the
/// part at fault is left out or replaced, and the rest is shown.
public struct Issue: Hashable, Sendable, CustomStringConvertible {
    public enum Kind: Hashable, Sendable {
        /// A node that is not an object with a string `type`. It is left out.
        case invalidNode
        /// `children` that is not an array. The node gets no children.
        case invalidChildren
        /// A section `layout` this version does not know. The section is laid
        /// out as a list.
        case unknownLayout(String)
        /// A node type the registry does not know. It is shown as its
        /// `fallback`, or else as an empty view.
        case unknownType(String)
        /// A property, or an event, the component does not accept. It is ignored.
        case unknownProperty(String)
        /// A `$` reference in a property that takes only a constant. The
        /// property is ignored.
        case referenceNotAccepted(String)
        /// Children of a component that has none. They are ignored.
        case unexpectedChildren
        /// A property value of the wrong type or out of range, written or
        /// referenced. The property is treated as missing.
        case typeMismatch(property: String, expected: PropertyType)
        /// An event value that is not an action object with a string
        /// `action`, or a list of them. It is left out.
        case invalidAction
        /// An action the registry does not know. It is left out.
        case unknownAction(String)
        /// An action without a parameter it needs. It does nothing.
        case missingParameter(String)
        /// A built-in action the app has not registered a handler for, such as
        /// `navigate`. It does nothing.
        case unhandledAction(String)
        /// A section or item `id` used before in the page. It is left out.
        case duplicateID(String)
        /// An item or header whose template the document does not have. It is
        /// left out.
        case unknownTemplate(String)
    }

    public let kind: Kind
    /// Where in the document, as in `templates.product.children[1]`.
    public let path: String

    public init(_ kind: Kind, at path: String) {
        self.kind = kind
        self.path = path
    }

    public var description: String {
        switch kind {
        case .invalidNode:
            return "\(path): not a node; it needs to be an object with a string \"type\""
        case .invalidChildren:
            return "\(path).children: not an array"
        case .unknownLayout(let layout):
            return "\(path).layout: unknown layout \"\(layout)\"; shown as a list"
        case .unknownType(let type):
            return "\(path): unknown type \"\(type)\"; shown as its fallback or else as an empty view"
        case .unknownProperty(let name):
            return "\(path).\(name): not accepted by this component; ignored"
        case .referenceNotAccepted(let name):
            return "\(path).\(name): takes only a constant, not a reference; ignored"
        case .unexpectedChildren:
            return "\(path).children: this component has no children; ignored"
        case .typeMismatch(let name, let expected):
            return "\(path).\(name): not a valid \(expected.name); treated as missing"
        case .invalidAction:
            return "\(path): not an action; it needs to be an object with a string \"action\""
        case .unknownAction(let name):
            return "\(path): unknown action \"\(name)\"; left out"
        case .missingParameter(let name):
            return "\(path).\(name): missing; the action does nothing"
        case .unhandledAction(let name):
            return "\(path): no handler is registered for \"\(name)\"; it does nothing"
        case .duplicateID(let id):
            return "\(path).id: \"\(id)\" is already used in the page; left out"
        case .unknownTemplate(let name):
            return "\(path).template: no template \"\(name)\"; left out"
        }
    }
}
