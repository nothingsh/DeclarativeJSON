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

/// Runs the actions of a template's events for one item.
///
/// `data` holds the item's data, and `update` is called with the data an
/// action changed; the page keeps the change and sends it into `data`.
@MainActor
final class ActionRunner {
    private let actions: ActionRegistry
    private let data: CurrentValueSubject<[String: JSONValue], Never>
    private let update: ([String: JSONValue]) -> Void
    private let report: (Issue) -> Void

    init(
        actions: ActionRegistry,
        data: CurrentValueSubject<[String: JSONValue], Never>,
        update: @escaping ([String: JSONValue]) -> Void,
        report: @escaping (Issue) -> Void
    ) {
        self.actions = actions
        self.data = data
        self.update = update
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
        // view, and `update` must not hold one strongly either.
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
            action: action, event: event, data: data.value, path: path, send: update, report: report
        ))
    }
}
