import Combine
import Foundation

/// An action as written in a template: `{"action": name, parameters...}`.
public struct Action: Equatable, Sendable {
    public let name: String
    public let parameters: [String: PropertyValue]

    public init(_ name: String, parameters: [String: PropertyValue] = [:]) {
        self.name = name
        self.parameters = parameters
    }
}

/// The item or section header whose views ran an action.
public struct ItemInfo: Equatable, Sendable {
    /// The item's `id`, or nil for a section's header.
    public let id: String?
    /// The `id` of the item's section, or of the header's.
    public let section: String
    /// The name of the template that shows the item or the header.
    public let template: String

    public init(id: String?, section: String, template: String) {
        self.id = id
        self.section = section
        self.template = template
    }

    public var isHeader: Bool { id == nil }
}

/// Changes the data the page keeps for one item: applies the change to the
/// item's data as the page has it, shows the result and returns it, or
/// returns nil when the page no longer has the item.
typealias DataUpdate = ((inout [String: JSONValue]) -> Void) -> [String: JSONValue]?

/// What an action runs for: the item the views show when it runs, the update
/// of that item, and the page, which the context keeps weakly.
struct ActionTarget {
    let item: ItemInfo
    let page: AnyObject?
    let update: DataUpdate
}

/// Runs the actions of a template's events for one item.
///
/// `data` holds the data of the item the views show. `target` returns that
/// item and its update, or nil when the views have no item; an action takes
/// them when it runs, so that a change it makes later, after a request for
/// example, goes to the same item even when the views show another one by
/// then.
@MainActor
final class ActionRunner {
    private let actions: ActionRegistry
    private let data: CurrentValueSubject<[String: JSONValue], Never>
    private let target: () -> ActionTarget?
    private let report: (Issue) -> Void

    init(
        actions: ActionRegistry,
        data: CurrentValueSubject<[String: JSONValue], Never>,
        target: @escaping () -> ActionTarget?,
        report: @escaping (Issue) -> Void
    ) {
        self.actions = actions
        self.data = data
        self.target = target
        self.report = report
    }

    /// Reads an event's value, an action or a list of actions, and returns
    /// what runs them in order with the event's value. What cannot run is
    /// reported now and left out.
    func handler(for json: JSONValue, path: String) -> EventAction {
        let elements: [(JSONValue, String)]
        if case .array(let array) = json {
            elements = array.enumerated().map { ($1, "\(path)[\($0)]") }
        } else {
            elements = [(json, path)]
        }
        let parsed = elements.compactMap { json, path in parse(json, path: path).map { ($0, path) } }
        // The views keep the runner through this closure. The runner holds no
        // view, and `target` must not hold one strongly either.
        return EventAction { event, source in
            for (action, path) in parsed {
                self.run(action, event: event, source: source, path: path)
            }
        }
    }

    private func parse(_ json: JSONValue, path: String) -> Action? {
        guard case .object(var object) = json, case .string(let name)? = object.removeValue(forKey: "action") else {
            report(Issue(.invalidAction, at: path))
            return nil
        }
        guard let spec = actions.action(name)?.spec else {
            report(Issue(.unknownAction(name), at: path))
            return nil
        }
        var parameters: [String: PropertyValue] = [:]
        for (key, value) in object.sorted(by: { $0.key < $1.key }) {
            let parameter = PropertyValue(value)
            if spec.parameters[key] == nil {
                report(Issue(.unknownProperty(key), at: path))
            } else if case .reference = parameter, spec.parameters[key]?.acceptsReference == false {
                report(Issue(.referenceNotAccepted(key), at: path))
            } else {
                parameters[key] = parameter
            }
        }
        return Action(name, parameters: parameters)
    }

    private func run(_ action: Action, event: JSONValue?, source: AnyObject?, path: String) {
        // Looked up when it runs, with the data as the previous action left it.
        guard let perform = actions.action(action.name)?.perform, let target = target() else { return }
        perform(ActionContext(
            action: action, event: event, data: data.value, target: target, source: source, path: path,
            report: report
        ))
    }
}
