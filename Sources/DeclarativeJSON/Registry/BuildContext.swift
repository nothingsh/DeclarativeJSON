import Combine
import Foundation

/// Runs the actions of a node's event, from `BuildContext.action(_:)`.
@MainActor
public struct EventAction {
    private let run: (JSONValue?, AnyObject?) -> Void

    init(_ run: @escaping (JSONValue?, AnyObject?) -> Void) {
        self.run = run
    }

    /// Runs the actions with the event's value. `source` is the view that
    /// sent the event, which the actions read as `ActionContext.sourceView`.
    public func callAsFunction(_ value: JSONValue? = nil, source: AnyObject? = nil) {
        run(value, source)
    }
}

/// What a component's build closure gets: its node, its built children, and
/// its properties as publishers.
///
/// A property reader returns nil when the node does not set the property, so
/// that the view keeps its own default. Otherwise it returns a publisher that
/// emits the value once for a constant, and every value of the item's data
/// for a `$` reference, skipping repeats. It emits nil when the referenced key
/// is missing or null, or when the value is not of the expected type; the
/// latter is reported. Each view applies nil as its own default.
@MainActor
public final class BuildContext<View> {
    public let node: Node
    public let children: [View]
    /// Where the node is in the document, for issues.
    public let path: String

    /// The page's theme, which has platform types; a `Theme` for UIKit.
    let themeValue: Any
    let report: (Issue) -> Void
    private let data: AnyPublisher<[String: JSONValue], Never>
    private let runner: ActionRunner

    init(
        node: Node,
        children: [View],
        path: String,
        data: AnyPublisher<[String: JSONValue], Never>,
        theme: Any,
        runner: ActionRunner,
        report: @escaping (Issue) -> Void
    ) {
        self.node = node
        self.children = children
        self.path = path
        self.data = data
        self.themeValue = theme
        self.runner = runner
        self.report = report
    }

    /// What runs the actions of `event` with the event's value, or nil when
    /// the node does not set the event. Call it once per event: the actions
    /// are checked, and their problems reported, on each call.
    public func action(_ event: EventName) -> EventAction? {
        guard case .constant(let json)? = node.properties[event.rawValue] else { return nil }
        return runner.handler(for: json, path: "\(path).\(event.rawValue)")
    }

    /// The property's JSON values, unchecked.
    public func json(_ name: String) -> AnyPublisher<JSONValue?, Never>? {
        switch node.properties[name] {
        case nil:
            return nil
        case .constant(let value)?:
            return Just(value).eraseToAnyPublisher()
        case .reference(let key)?:
            return data.map { $0[key] }.removeDuplicates().eraseToAnyPublisher()
        }
    }

    /// The property's values read by `read`, which returns nil for a value
    /// that is not valid; that is reported as a mismatch with `expected`.
    public func value<T>(
        _ name: String,
        expected: PropertyType,
        read: @escaping (JSONValue) -> T?
    ) -> AnyPublisher<T?, Never>? {
        json(name)?.map { [report, path] json -> T? in
            guard let json, json != .null else { return nil }
            guard let value = read(json) else {
                report(Issue(.typeMismatch(property: name, expected: expected), at: path))
                return nil
            }
            return value
        }.eraseToAnyPublisher()
    }

    public func number(_ name: String) -> AnyPublisher<Double?, Never>? {
        value(name, expected: .number) { json in
            guard case .number(let number) = json, number.isFinite else { return nil }
            return number
        }
    }

    /// A number that is finite and not negative, such as a width.
    public func length(_ name: String) -> AnyPublisher<Double?, Never>? {
        value(name, expected: .number) { json in
            guard case .number(let number) = json, number.isFinite, number >= 0 else { return nil }
            return number
        }
    }

    public func integer(_ name: String) -> AnyPublisher<Int?, Never>? {
        value(name, expected: .integer) { json in
            guard case .number(let number) = json, let integer = Int(exactly: number) else { return nil }
            return integer
        }
    }

    public func bool(_ name: String) -> AnyPublisher<Bool?, Never>? {
        value(name, expected: .bool) { json in
            guard case .bool(let bool) = json else { return nil }
            return bool
        }
    }

    public func string(_ name: String) -> AnyPublisher<String?, Never>? {
        value(name, expected: .string) { json in
            guard case .string(let string) = json else { return nil }
            return string
        }
    }

    public func url(_ name: String) -> AnyPublisher<URL?, Never>? {
        value(name, expected: .url) { json in
            guard case .string(let string) = json else { return nil }
            return URL(string: string)
        }
    }

    /// One of the strings in `options`, read as its value.
    public func choice<T>(_ name: String, _ options: [String: T]) -> AnyPublisher<T?, Never>? {
        value(name, expected: .oneOf(options.keys.sorted())) { json in
            guard case .string(let string) = json else { return nil }
            return options[string]
        }
    }
}
