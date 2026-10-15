import Foundation

/// A problem in a document that does not stop the page from showing: the
/// part at fault is left out or replaced, and the rest is shown.
public struct Issue: Equatable, Sendable, CustomStringConvertible {
    public enum Kind: Equatable, Sendable {
        /// A node that is not an object with a string `type`. It is left out.
        case invalidNode
        /// `children` that is not an array. The node gets no children.
        case invalidChildren
        /// A section `layout` this version does not know. The section is laid
        /// out as a list.
        case unknownLayout(String)
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
        }
    }
}
