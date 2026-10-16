@testable import DeclarativeJSON

extension Issue {

    /// The issue as the protocol writes it, for comparing with the shared
    /// cases: `{"kind": "unknownType", "type": "card", "at": "templates.product"}`.
    var protocolJSON: JSONValue {
        var object: [String: JSONValue] = ["at": .string(path)]
        func kind(_ name: String, _ fields: [String: JSONValue] = [:]) {
            object["kind"] = .string(name)
            object.merge(fields) { $1 }
        }
        switch self.kind {
        case .invalidNode: kind("invalidNode")
        case .invalidChildren: kind("invalidChildren")
        case .unknownLayout(let layout): kind("unknownLayout", ["layout": .string(layout)])
        case .unknownType(let type): kind("unknownType", ["type": .string(type)])
        case .unknownProperty(let name): kind("unknownProperty", ["property": .string(name)])
        case .referenceNotAccepted(let name): kind("referenceNotAccepted", ["property": .string(name)])
        case .unexpectedChildren: kind("unexpectedChildren")
        case .typeMismatch(let name, let expected):
            kind("typeMismatch", ["property": .string(name), "expected": .object(Manifest.json(expected))])
        case .invalidAction: kind("invalidAction")
        case .unknownAction(let name): kind("unknownAction", ["action": .string(name)])
        case .missingParameter(let name): kind("missingParameter", ["parameter": .string(name)])
        case .unhandledAction(let name): kind("unhandledAction", ["action": .string(name)])
        case .duplicateID(let id): kind("duplicateID", ["id": .string(id)])
        case .unknownTemplate(let name): kind("unknownTemplate", ["template": .string(name)])
        case .unknownID(let id): kind("unknownID", ["id": .string(id)])
        case .unknownOperation(let name): kind("unknownOperation", ["operation": .string(name)])
        }
        return .object(object)
    }
}
