import Foundation

/// What an action accepts.
public struct ActionSpec: Equatable, Sendable {
    public let name: String
    public let parameters: [String: PropertySpec]

    public init(_ name: String, parameters: [String: PropertySpec] = [:]) {
        self.name = name
        self.parameters = parameters
    }

    /// Hands `url` to the app's router.
    public static let navigate = ActionSpec("navigate", parameters: ["url": PropertySpec(.url)])
    /// Hands `url` to the app to open outside the page.
    public static let openURL = ActionSpec("openURL", parameters: ["url": PropertySpec(.url)])
    /// Sets the item's data at `path` to `value`, or to the event's value when
    /// there is no `value`: the text of a text field, the state of a switch,
    /// the value of a slider.
    public static let set = ActionSpec("set", parameters: [
        "path": PropertySpec(.string, acceptsReference: false),
        "value": PropertySpec(.any),
    ])
    /// Flips the Bool in the item's data at `path`; a missing one becomes true.
    public static let toggle = ActionSpec("toggle", parameters: [
        "path": PropertySpec(.string, acceptsReference: false),
    ])
}

/// The actions an event can run, and what each does.
///
/// ```swift
/// var actions = ActionRegistry.standard
/// actions.register(.navigate) { context in
///     if let url = context.url("url") { router.open(url) }
/// }
/// actions.register(ActionSpec("track", parameters: ["event": PropertySpec(.string)])) { context in
///     analytics.track(context.string("event"))
/// }
/// ```
///
/// Actions run in the app; nothing is sent back to the server. Registering
/// an action that is already there replaces it.
public struct ActionRegistry {
    public typealias Perform = @MainActor (ActionContext) -> Void

    private var actions: [String: (spec: ActionSpec, perform: Perform)] = [:]

    public init() {}

    public mutating func register(_ spec: ActionSpec, perform: @escaping Perform) {
        actions[spec.name] = (spec, perform)
    }

    /// Every registered action, sorted by name.
    public var specs: [ActionSpec] {
        actions.values.map(\.spec).sorted { $0.name < $1.name }
    }

    func action(_ name: String) -> (spec: ActionSpec, perform: Perform)? {
        actions[name]
    }

    /// `set` and `toggle`, and `navigate` and `openURL`, which report that
    /// they are not handled until the app registers them.
    public static var standard: ActionRegistry {
        var registry = ActionRegistry()
        registry.register(.navigate) { $0.report(.unhandledAction("navigate")) }
        registry.register(.openURL) { $0.report(.unhandledAction("openURL")) }
        registry.register(.set) { context in
            guard let path = context.string("path") else { return context.report(.missingParameter("path")) }
            if context.has("value") {
                // A reference to a missing key removes the key.
                context.update { $0[path] = context.parameters["value"] }
            } else if let event = context.event {
                context.update { $0[path] = event }
            } else {
                context.report(.missingParameter("value"))
            }
        }
        registry.register(.toggle) { context in
            guard let path = context.string("path") else { return context.report(.missingParameter("path")) }
            switch context.data[path] {
            case nil, .null?:
                context.update { $0[path] = .bool(true) }
            case .bool(let bool)?:
                context.update { $0[path] = .bool(!bool) }
            case _?:
                context.report(.typeMismatch(property: path, expected: .bool))
            }
        }
        return registry
    }
}

/// What an action's handler gets: its parameters, resolved against the item
/// data when the action runs, the event's value, and the item data.
@MainActor
public final class ActionContext {
    /// The parameters, with `$` references resolved. A reference to a
    /// missing key is left out.
    public let parameters: [String: JSONValue]
    /// The value the event carries, if any: a String, a Bool or a number.
    public let event: JSONValue?
    /// The item's data when the action ran, and after each `update`, as the
    /// page has it then.
    public private(set) var data: [String: JSONValue]

    private let written: Set<String>
    private let path: String
    private let send: DataUpdate
    private let issue: (Issue) -> Void

    init(
        action: Action,
        event: JSONValue?,
        data: [String: JSONValue],
        path: String,
        send: @escaping DataUpdate,
        report: @escaping (Issue) -> Void
    ) {
        parameters = action.parameters.compactMapValues { $0.resolve(in: data) }
        written = Set(action.parameters.keys)
        self.event = event
        self.data = data
        self.path = path
        self.send = send
        issue = report
    }

    /// Whether the template gives the parameter, even as a reference to a
    /// missing key.
    public func has(_ name: String) -> Bool {
        written.contains(name)
    }

    /// Changes the item's data. The page keeps the change and the item's
    /// views show it at once.
    ///
    /// It can be called after the action returned, after a request for
    /// example. The change still goes to the item the action ran for, and
    /// applies to the item's data as the page has it then; the page drops it
    /// when it no longer has the item.
    public func update(_ change: (inout [String: JSONValue]) -> Void) {
        if let updated = send(change) {
            data = updated
        } else {
            change(&data)
        }
    }

    public func report(_ kind: Issue.Kind) {
        issue(Issue(kind, at: path))
    }

    public func string(_ name: String) -> String? {
        read(name, .string) { if case .string(let string) = $0 { return string } else { return nil } }
    }

    public func url(_ name: String) -> URL? {
        read(name, .url) { if case .string(let string) = $0 { return URL(string: string) } else { return nil } }
    }

    public func bool(_ name: String) -> Bool? {
        read(name, .bool) { if case .bool(let bool) = $0 { return bool } else { return nil } }
    }

    public func number(_ name: String) -> Double? {
        read(name, .number) { if case .number(let number) = $0 { return number } else { return nil } }
    }

    private func read<T>(_ name: String, _ expected: PropertyType, _ convert: (JSONValue) -> T?) -> T? {
        guard let json = parameters[name], json != .null else { return nil }
        guard let value = convert(json) else {
            report(.typeMismatch(property: name, expected: expected))
            return nil
        }
        return value
    }
}
