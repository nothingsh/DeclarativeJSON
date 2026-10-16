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
    /// The item's `tracking`, for analytics; nil for a header and for an
    /// item without one.
    public let tracking: JSONValue?

    public init(id: String?, section: String, template: String, tracking: JSONValue? = nil) {
        self.id = id
        self.section = section
        self.template = template
        self.tracking = tracking
    }

    public var isHeader: Bool { id == nil }
}

/// Changes the data the page keeps for one item: applies the change to the
/// item's data as the page has it, shows the result and returns it, or
/// returns nil when the page no longer has the item.
typealias DataUpdate = @MainActor ((inout [String: JSONValue]) -> Void) -> [String: JSONValue]?

/// What an action runs for: the item the views show when it runs, its data
/// and the update of it, and the page and the page's tasks, if any, which
/// asynchronous actions run in. It keeps the page and the tasks weakly, as
/// the tasks keep it.
struct ActionTarget {
    let item: ItemInfo
    weak var page: AnyObject?
    /// The item's data as the page has it, or nil when the page no longer
    /// has the item.
    let data: @MainActor () -> [String: JSONValue]?
    let update: DataUpdate
    weak var tasks: ActionTasks?
}

/// The tasks of a page's asynchronous actions, cancelled when the page goes
/// away and lets go of this.
final class ActionTasks: @unchecked Sendable {
    private let lock = NSLock()
    private var tasks: [Int: Task<Void, Never>] = [:]
    private var next = 0

    @MainActor
    func run(_ operation: @escaping @MainActor () async -> Void) {
        lock.lock()
        defer { lock.unlock() }
        let id = next
        next += 1
        // The task runs on the main actor, so it cannot finish before it is kept.
        tasks[id] = Task { @MainActor [weak self] in
            await operation()
            self?.remove(id)
        }
    }

    private func remove(_ id: Int) {
        lock.lock()
        defer { lock.unlock() }
        tasks[id] = nil
    }

    deinit {
        tasks.values.forEach { $0.cancel() }
    }
}

/// An action ready to run, with the actions that run after it when it is
/// asynchronous.
private struct Step {
    let action: Action
    let path: String
    let onSuccess: [Step]
    let onFailure: [Step]
}

/// Runs the actions of a template's events for one item.
///
/// `target` returns the item the views show and its update, or nil when the
/// views have no item. An event takes them when it runs, so that a change its
/// actions make later, after a request for example, goes to the same item
/// even when the views show another one by then.
@MainActor
final class ActionRunner {
    private let actions: ActionRegistry
    private let target: () -> ActionTarget?
    private let report: (Issue) -> Void

    init(
        actions: ActionRegistry,
        target: @escaping () -> ActionTarget?,
        report: @escaping (Issue) -> Void
    ) {
        self.actions = actions
        self.target = target
        self.report = report
    }

    /// Reads an event's value, an action or a list of actions, and returns
    /// what runs them in order with the event's value. What cannot run is
    /// reported now and left out.
    func handler(for json: JSONValue, path: String) -> EventAction {
        let steps = steps(json, path: path)
        // The views keep the runner through this closure. The runner holds no
        // view, and `target` must not hold one strongly either.
        return EventAction { event, source in
            guard let target = self.target() else { return }
            self.run(steps[...], event: event, source: source, target: target) {}
        }
    }

    private func steps(_ json: JSONValue, path: String) -> [Step] {
        let elements: [(JSONValue, String)]
        if case .array(let array) = json {
            elements = array.enumerated().map { ($1, "\(path)[\($0)]") }
        } else {
            elements = [(json, path)]
        }
        return elements.compactMap { json, path in parse(json, path: path) }
    }

    private func parse(_ json: JSONValue, path: String) -> Step? {
        guard case .object(var object) = json, case .string(let name)? = object.removeValue(forKey: "action") else {
            report(Issue(.invalidAction, at: path))
            return nil
        }
        guard let spec = actions.action(name)?.spec else {
            report(Issue(.unknownAction(name), at: path))
            return nil
        }
        // Only an asynchronous action takes them; another reports them as unknown.
        var branches: [String: [Step]] = [:]
        if spec.isAsync {
            for key in ["onSuccess", "onFailure"] {
                if let json = object.removeValue(forKey: key) {
                    branches[key] = steps(json, path: "\(path).\(key)")
                }
            }
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
        return Step(
            action: Action(name, parameters: parameters), path: path,
            onSuccess: branches["onSuccess"] ?? [], onFailure: branches["onFailure"] ?? []
        )
    }

    /// Runs `steps` in order, then `next`. An asynchronous action runs in a
    /// task, and the rest when it is done; nothing more runs when the page no
    /// longer has the item by then.
    private func run(
        _ steps: ArraySlice<Step>,
        event: JSONValue?,
        source: AnyObject?,
        target: ActionTarget,
        then next: @escaping @MainActor () -> Void
    ) {
        var rest = steps
        while let step = rest.popFirst() {
            // Read when each action runs, with the data as the previous action left it.
            guard let perform = actions.action(step.action.name)?.perform, let data = target.data() else { return }
            let context = ActionContext(
                action: step.action, event: event, data: data, target: target, source: source, path: step.path,
                report: report
            )
            switch perform {
            case .sync(let perform):
                perform(context)
            case .async(let perform):
                let operation: @MainActor () async -> Void = { [weak source] in
                    let succeeded: Bool
                    do {
                        try await perform(context)
                        succeeded = true
                    } catch {
                        succeeded = false
                    }
                    self.run(succeeded ? step.onSuccess[...] : step.onFailure[...], event: event, source: source, target: target) {
                        self.run(rest, event: event, source: source, target: target, then: next)
                    }
                }
                if let tasks = target.tasks {
                    tasks.run(operation)
                } else {
                    Task { @MainActor in await operation() }
                }
                return
            }
        }
        next()
    }
}
