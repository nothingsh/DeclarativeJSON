import Foundation

/// A view in a template: `{"type": ..., properties..., "children": [...]}`.
///
/// Every key besides `type`, `children` and `fallback` is a property. Which
/// types and properties exist is up to the component registry; the node keeps
/// them all.
public struct Node: Equatable, Sendable {
    public let type: String
    public let properties: [String: PropertyValue]
    public let children: [Node]
    /// What to show instead when the registry does not know `type`, such as
    /// a component of a later release.
    public var fallback: Node? { fallbacks.first }

    // An array, since a struct cannot hold an optional of itself.
    private let fallbacks: [Node]

    public init(type: String, properties: [String: PropertyValue] = [:], children: [Node] = [], fallback: Node? = nil) {
        self.type = type
        self.properties = properties
        self.children = children
        fallbacks = fallback.map { [$0] } ?? []
    }

    /// Reads a node, or returns nil when the JSON is not one. A child or a
    /// fallback that is not a node is left out; all are reported.
    init?(_ json: JSONValue, path: String, issues: inout [Issue]) {
        guard case .object(var object) = json, case .string(let type)? = object.removeValue(forKey: "type") else {
            issues.append(Issue(.invalidNode, at: path))
            return nil
        }
        var children: [Node] = []
        switch object.removeValue(forKey: "children") {
        case nil:
            break
        case .array(let elements)?:
            for (index, element) in elements.enumerated() {
                if let child = Node(element, path: "\(path).children[\(index)]", issues: &issues) {
                    children.append(child)
                }
            }
        case _?:
            issues.append(Issue(.invalidChildren, at: path))
        }
        let fallback = object.removeValue(forKey: "fallback").flatMap {
            Node($0, path: "\(path).fallback", issues: &issues)
        }
        self.init(type: type, properties: object.mapValues(PropertyValue.init), children: children, fallback: fallback)
    }
}
