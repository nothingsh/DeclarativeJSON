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

/// Changes the data the page keeps for one item: applies the change to the
/// item's data as the page has it, shows the result and returns it, or
/// returns nil when the page no longer has the item.
typealias DataUpdate = ((inout [String: JSONValue]) -> Void) -> [String: JSONValue]?

/// Runs the actions of a template's events for one item.
///
/// `data` holds the data of the item the views show. `updater` returns the
/// update of that item; an action takes it when it runs, so that a change it
/// makes later, after a request for example, goes to the same item even when
/// the views show another one by then.
@MainActor
final class ActionRunner {
    private let actions: ActionRegistry
    private let data: CurrentValueSubject<[String: JSONValue], Never>
    private let updater: () -> DataUpdate
    private let report: (Issue) -> Void

    init(
        actions: ActionRegistry,
        data: CurrentValueSubject<[String: JSONValue], Never>,
        updater: @escaping () -> DataUpdate,
        report: @escaping (Issue) -> Void
    ) {
        self.actions = actions
        self.data = data
        self.updater = updater
        self.report = report
    }

    /// Reads an event's value, an action or a list of actions, and returns
    /// what runs them in order with the event's value. What cannot run is
    /// reported now and left out.
    func handler(for json: JSONValue, path: String) -> (JSONValue?) -> Void {
        let elements: [(JSONValue, String)]
        if case .array(let array) = json {
            elements = array.enumerated().map { ($1, "\(path)[\($0)]") }
        } else {
            elements = [(json, path)]
        }
        let parsed = elements.compactMap { json, path in parse(json, path: path).map { ($0, path) } }
        // The views keep the runner through this closure. The runner holds no
        // view, and `updater` must not hold one strongly either.
        return { event in
            for (action, path) in parsed {
                self.run(action, event: event, path: path)
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

    private func run(_ action: Action, event: JSONValue?, path: String) {
        // Looked up when it runs, with the data as the previous action left it.
        guard let perform = actions.action(action.name)?.perform else { return }
        perform(ActionContext(
            action: action, event: event, data: data.value, path: path, send: updater(), report: report
        ))
    }
}
