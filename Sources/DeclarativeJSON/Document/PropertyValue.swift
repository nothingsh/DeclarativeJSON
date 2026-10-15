import Foundation

/// The value of a property in a template: a constant, or a reference to a key
/// of the item's `data`.
///
/// A string that starts with `$` is a reference, `"$title"` to the key
/// `title`. The reference is the whole value; there is no concatenation and
/// no arithmetic. `$$` escapes a dollar sign: `"$$99"` is the string `"$99"`.
/// A lone `"$"` is the string `"$"`. Only the property value itself is read
/// this way, not the strings nested in an array or an object.
public enum PropertyValue: Equatable, Sendable {
    case constant(JSONValue)
    case reference(String)

    public init(_ json: JSONValue) {
        guard case .string(let string) = json, string.hasPrefix("$"), string != "$" else {
            self = .constant(json)
            return
        }
        let rest = String(string.dropFirst())
        self = rest.hasPrefix("$") ? .constant(.string(rest)) : .reference(rest)
    }

    /// The value for an item with this data, or nil when a reference names a
    /// key the data does not have.
    public func resolve(in data: [String: JSONValue]) -> JSONValue? {
        switch self {
        case .constant(let value):
            return value
        case .reference(let key):
            return data[key]
        }
    }
}
