import UIKit
import XCTest
@testable import DeclarativeJSON

/// The data of the items and headers in an action case, by "item:<id>" and
/// "header:<section id>".
private final class Store {
    var values: [String: [String: JSONValue]] = [:]
}

/// What the app's `navigate` and `openURL` handlers got in an action case.
private final class Handed {
    var urls: [JSONValue] = []
}

/// Runs the cases in protocol/cases, which every renderer of the format runs
/// too. A case that fails names itself in the message.
@MainActor
final class ProtocolCaseTests: XCTestCase {

    private static let directory = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent("protocol/cases")

    private let decoder = DocumentDecoder()

    private func cases(_ file: String) throws -> [[String: JSONValue]] {
        let data = try Data(contentsOf: Self.directory.appendingPathComponent("\(file).json"))
        guard case .object(let root) = try JSONDecoder().decode(JSONValue.self, from: data),
              case .array(let cases)? = root["cases"] else {
            throw CocoaError(.fileReadCorruptFile)
        }
        let read = cases.compactMap { if case .object(let fields) = $0 { return fields } else { return nil } }
        XCTAssertFalse(read.isEmpty, "no cases in \(file).json")
        return read
    }

    private func encoded(_ json: JSONValue?) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(json ?? .null)
    }

    private func text(_ json: JSONValue) -> String {
        (try? encoded(json)).flatMap { String(data: $0, encoding: .utf8) } ?? "?"
    }

    private func name(_ fields: [String: JSONValue]) -> String {
        if case .string(let name)? = fields["name"] { return name }
        return "unnamed case"
    }

    /// Compares issues as sets: the order they are reported in, and how often,
    /// is up to the renderer.
    private func assertIssues(_ issues: [Issue], _ expected: JSONValue?, _ name: String) {
        guard case .array(let written)? = expected else { return }
        let actual = Set(issues.map { text($0.protocolJSON) })
        let wanted = Set(written.map(text))
        let missing = wanted.subtracting(actual).sorted()
        let unexpected = actual.subtracting(wanted).sorted()
        XCTAssertTrue(missing.isEmpty && unexpected.isEmpty, """
        \(name): issues differ
          missing: \(missing.joined(separator: "\n           "))
          unexpected: \(unexpected.joined(separator: "\n              "))
        """)
    }

    // MARK: - Decoding

    func testDecodingCases() throws {
        for fields in try cases("decoding") {
            let data: Data
            if case .string(let text)? = fields["text"] {
                data = Data(text.utf8)
            } else {
                data = try encoded(fields["input"])
            }
            var result: String
            do {
                if fields["patch"] == .bool(true) {
                    _ = try decoder.decodePatch(data)
                } else {
                    _ = try decoder.decode(data)
                }
                result = "decodes"
            } catch DocumentError.unsupportedVersion {
                result = "unsupportedVersion"
            } catch {
                result = "invalid"
            }
            XCTAssertEqual(.string(result), fields["expect"], name(fields))
        }
    }

    // MARK: - Issues

    /// Shows the document in a page large enough for every cell and header
    /// to be built.
    private func show(_ document: Document, issues: @escaping (Issue) -> Void) -> DocumentViewController {
        let controller = DocumentViewController(document: document)
        controller.onIssue = issues
        controller.loadViewIfNeeded()
        controller.view.frame = CGRect(x: 0, y: 0, width: 2000, height: 4000)
        controller.view.layoutIfNeeded()
        return controller
    }

    func testIssueCases() throws {
        for fields in try cases("issues") {
            var issues: [Issue] = []
            _ = show(try decoder.decode(try encoded(fields["document"]))) { issues.append($0) }
            assertIssues(issues, fields["issues"], name(fields))
        }
    }

    // MARK: - Actions

    func testActionCases() async throws {
        for fields in try cases("actions") {
            try await runActionCase(fields)
        }
    }

    /// The JSON at a path such as `templates.row.children[1].overlay.content`.
    private func json(at path: String, in root: JSONValue) -> JSONValue? {
        var current: JSONValue? = root
        for segment in path.split(separator: ".") {
            let parts = segment.split(separator: "[")
            guard case .object(let object)? = current else { return nil }
            current = object[String(parts[0])]
            for index in parts.dropFirst() {
                guard case .array(let array)? = current, let index = Int(index.dropLast()), array.indices.contains(index) else {
                    return nil
                }
                current = array[index]
            }
        }
        return current
    }

    private func runActionCase(_ fields: [String: JSONValue]) async throws {
        let name = name(fields)
        let documentJSON = try XCTUnwrap(fields["document"], name)
        let document = try decoder.decode(try encoded(documentJSON))
        let store = Store()
        var shown: [String: ItemInfo] = [:]
        for section in document.sections {
            if let header = section.header {
                store.values["header:\(section.id)"] = header.data
                shown["header:\(section.id)"] = ItemInfo(id: nil, section: section.id, template: header.template)
            }
            for item in section.items {
                store.values["item:\(item.id)"] = item.data
                shown["item:\(item.id)"] = ItemInfo(id: item.id, section: section.id, template: item.template)
            }
        }

        struct Failure: Error {}
        let handed = Handed()
        var actions = ActionRegistry.standard
        if case .array(let names)? = fields["handlers"] {
            for case .string(let handler) in names {
                let spec: ActionSpec = handler == "navigate" ? .navigate : .openURL
                actions.register(spec) { context in
                    handed.urls.append(.object([
                        "action": .string(handler),
                        "url": context.url("url").map { .string($0.absoluteString) } ?? .null,
                    ]))
                }
            }
        }
        actions.register(ActionSpec("succeed")) { _ in await Task.yield() }
        actions.register(ActionSpec("fail")) { _ in
            await Task.yield()
            throw Failure()
        }

        var issues: [Issue] = []
        guard case .array(let steps)? = fields["steps"] else { return XCTFail("\(name): no steps") }
        for case .object(let step) in steps {
            let key: String
            switch (step["item"], step["header"]) {
            case (.string(let id)?, _): key = "item:\(id)"
            case (_, .string(let id)?): key = "header:\(id)"
            default: return XCTFail("\(name): a step without an item or a header")
            }
            let item = try XCTUnwrap(shown[key], "\(name): no \(key)")
            guard case .string(let nodePath)? = step["node"], case .string(let event)? = step["event"],
                  nodePath == "templates.\(item.template)" || nodePath.hasPrefix("templates.\(item.template).") else {
                return XCTFail("\(name): the step's node is not in the template of \(key)")
            }
            guard case .object(let node)? = json(at: nodePath, in: documentJSON), let actionsJSON = node[event] else {
                return XCTFail("\(name): no \(event) at \(nodePath)")
            }

            let runner = ActionRunner(
                actions: actions,
                target: {
                    ActionTarget(item: item, data: { store.values[key] }) { change in
                        guard var data = store.values[key] else { return nil }
                        change(&data)
                        store.values[key] = data
                        return data
                    }
                },
                report: { issues.append($0) }
            )
            runner.handler(for: actionsJSON, path: "\(nodePath).\(event)")(step["value"])
            // Lets asynchronous actions, and the actions after them, finish.
            for _ in 0..<50 {
                await Task.yield()
            }
        }

        guard case .object(let expect)? = fields["expect"] else { return XCTFail("\(name): no expect") }
        for (prefix, field) in [("item", "data"), ("header", "headers")] {
            guard case .object(let expected)? = expect[field] else { continue }
            for (id, data) in expected {
                XCTAssertEqual(store.values["\(prefix):\(id)"].map(JSONValue.object), data, "\(name): \(prefix) \(id)")
            }
        }
        if let expected = expect["handed"] {
            XCTAssertEqual(.array(handed.urls), expected, "\(name): handed")
        }
        assertIssues(issues, expect["issues"], name)
    }

    // MARK: - Patches

    func testPatchCases() throws {
        for fields in try cases("patches") {
            let name = name(fields)
            var issues: [Issue] = []
            let controller = show(try decoder.decode(try encoded(fields["document"]))) { issues.append($0) }
            if case .array(let patches)? = fields["patches"] {
                for patch in patches {
                    controller.apply(try decoder.decodePatch(try encoded(patch)), animatingDifferences: false)
                }
            }

            guard case .object(let expect)? = fields["expect"],
                  case .array(let sections)? = expect["sections"] else { return XCTFail("\(name): no sections") }
            let shown = controller.document.sections
            XCTAssertEqual(shown.map { JSONValue.string($0.id) }, sections.map {
                if case .object(let section) = $0 { return section["id"] ?? .null }
                return .null
            }, "\(name): sections")
            for (section, written) in zip(shown, sections) {
                guard case .object(let expected) = written else { continue }
                XCTAssertEqual(.array(section.items.map { .string($0.id) }), expected["items"], "\(name): items of \(section.id)")
                // A key the case leaves out is not checked.
                if let more = expected["more"] {
                    XCTAssertEqual(section.more ?? .null, more, "\(name): more of \(section.id)")
                }
                if let header = expected["header"] {
                    XCTAssertEqual(section.header.map { .string($0.template) } ?? .null, header, "\(name): header of \(section.id)")
                }
            }
            assertIssues(issues, expect["issues"], name)
        }
    }
}
