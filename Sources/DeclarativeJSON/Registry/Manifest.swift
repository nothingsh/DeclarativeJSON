import Foundation

/// A description of every component, property, event and action the
/// registries accept, for the backend that generates documents.
///
/// ```json
/// {
///   "v": 1,
///   "common": { "alpha": { "type": "number", "reference": true }, … },
///   "components": {
///     "button": {
///       "children": false,
///       "events": ["onTap"],
///       "properties": { "title": { "type": "string", "reference": true }, … }
///     }
///   },
///   "actions": {
///     "navigate": { "parameters": { "url": { "type": "url", "reference": true } } }
///   }
/// }
/// ```
///
/// `common` lists the properties every component accepts besides its own.
/// `reference` tells whether the value can be a `$` reference. A type is one
/// of `number`, `integer`, `bool`, `string`, `url`, `color`, `font`,
/// `insets`, `oneOf` with its `values`, `object` with the type of each of
/// its `properties`, and `any`.
public struct Manifest {
    public let components: [ComponentSpec]
    public let actions: [ActionSpec]

    public init(components: [ComponentSpec], actions: [ActionSpec]) {
        self.components = components
        self.actions = actions
    }

    public init<View>(components: ComponentRegistry<View>, actions: ActionRegistry) {
        self.init(components: components.specs, actions: actions.specs)
    }

    /// The manifest as pretty-printed JSON with sorted keys, so that the same
    /// components always give the same bytes.
    public func encoded() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(json)
    }

    var json: JSONValue {
        var components: [String: JSONValue] = [:]
        for spec in self.components {
            components[spec.type] = .object([
                "children": .bool(spec.acceptsChildren),
                "events": .array(EventName.allCases.filter(spec.events.contains).map { .string($0.rawValue) }),
                "properties": Self.json(spec.properties),
            ])
        }
        var actions: [String: JSONValue] = [:]
        for spec in self.actions {
            actions[spec.name] = .object(["parameters": Self.json(spec.parameters)])
        }
        return .object([
            "v": .number(Double(DocumentVersion.current)),
            "common": Self.json(ComponentSpec.commonProperties),
            "components": .object(components),
            "actions": .object(actions),
        ])
    }

    private static func json(_ properties: [String: PropertySpec]) -> JSONValue {
        .object(properties.mapValues { property in
            var fields = json(property.type)
            fields["reference"] = .bool(property.acceptsReference)
            return .object(fields)
        })
    }

    private static func json(_ type: PropertyType) -> [String: JSONValue] {
        switch type {
        case .number, .integer, .bool, .string, .url, .color, .font, .insets, .any:
            return ["type": .string(type.name)]
        case .oneOf(let values):
            return ["type": .string(type.name), "values": .array(values.map(JSONValue.string))]
        case .object(let fields):
            return ["type": .string(type.name), "properties": .object(fields.mapValues { .object(json($0)) })]
        }
    }
}
