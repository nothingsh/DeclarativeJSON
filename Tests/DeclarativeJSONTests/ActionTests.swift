import Combine
import UIKit
import XCTest
@testable import DeclarativeJSON

@MainActor
final class ActionTests: XCTestCase {

    private var issues: [Issue] = []
    private var updates: [[String: JSONValue]] = []
    private let data = CurrentValueSubject<[String: JSONValue], Never>([:])

    private func build(_ json: String, actions: ActionRegistry = .standard) throws -> UIView {
        let value = try JSONDecoder().decode(JSONValue.self, from: Data(json.utf8))
        var decodeIssues: [Issue] = []
        let node = try XCTUnwrap(Node(value, path: "t", issues: &decodeIssues))
        let builder = NodeBuilder(
            components: .standard,
            actions: actions,
            data: data,
            target: { [unowned self] in
                ActionTarget(item: ItemInfo(id: "a", section: "s", template: "t"), data: { [unowned self] in data.value }) {
                    [unowned self] change in
                    var changed = data.value
                    change(&changed)
                    updates.append(changed)
                    data.send(changed)
                    return changed
                }
            },
            report: { [unowned self] in issues.append($0) }
        )
        return builder.build(node, path: "t")
    }

    func testATapRunsItsActionsInOrderAndTheViewsShowTheChangedData() throws {
        var recorded: [JSONValue?] = []
        var actions = ActionRegistry.standard
        actions.register(ActionSpec("record", parameters: ["value": PropertySpec(.any)])) { context in
            recorded.append(context.parameters["value"])
        }
        data.send(["liked": .bool(false), "title": .string("Keyboard")])
        let stack = try XCTUnwrap(try build("""
        { "type": "hstack", "children": [
          { "type": "label", "text": "$title", "isVisible": "$liked" },
          { "type": "button", "onTap": [
            { "action": "toggle", "path": "liked" },
            { "action": "record", "value": "$liked" }
          ]}
        ]}
        """, actions: actions) as? UIStackView)
        let label = stack.arrangedSubviews[0]
        let button = try XCTUnwrap(stack.arrangedSubviews[1] as? UIButton)
        XCTAssertTrue(label.isHidden)

        button.fire(.touchUpInside)

        XCTAssertEqual(recorded, [.bool(true)])
        XCTAssertEqual(updates, [["liked": .bool(true), "title": .string("Keyboard")]])
        XCTAssertFalse(label.isHidden)
        XCTAssertEqual(issues, [])
    }

    private var pending: [CheckedContinuation<Void, Error>] = []

    func testAnAsyncActionRunsItsOnSuccessOrItsOnFailureThenTheActionsAfterIt() async throws {
        struct Failure: Error {}
        var recorded: [JSONValue?] = []
        var actions = ActionRegistry.standard
        actions.register(ActionSpec("record", parameters: ["value": PropertySpec(.any)])) { context in
            recorded.append(context.parameters["value"])
        }
        actions.register(ActionSpec("like")) { [unowned self] _ in
            try await withCheckedThrowingContinuation { pending.append($0) }
        }
        data.send(["liked": .bool(false)])
        let button = try XCTUnwrap(try build("""
        { "type": "button", "onTap": [
          { "action": "toggle", "path": "liked" },
          { "action": "like",
            "onSuccess": { "action": "record", "value": "saved" },
            "onFailure": [ { "action": "toggle", "path": "liked" }, { "action": "record", "value": "$liked" } ] },
          { "action": "record", "value": "after" }
        ]}
        """, actions: actions) as? UIButton)

        button.fire(.touchUpInside)
        XCTAssertEqual(data.value, ["liked": .bool(true)])
        XCTAssertEqual(recorded, [])
        await waitUntil(!pending.isEmpty)
        pending.removeFirst().resume(throwing: Failure())
        await waitUntil(recorded.count == 2)
        XCTAssertEqual(data.value, ["liked": .bool(false)])
        XCTAssertEqual(recorded, [.bool(false), .string("after")])

        recorded = []
        button.fire(.touchUpInside)
        await waitUntil(!pending.isEmpty)
        pending.removeFirst().resume()
        await waitUntil(recorded.count == 2)
        XCTAssertEqual(data.value, ["liked": .bool(true)])
        XCTAssertEqual(recorded, [.string("saved"), .string("after")])
        XCTAssertEqual(issues, [])
    }

    private func waitUntil(_ condition: @autoclosure () -> Bool) async {
        for _ in 0..<100 where !condition() {
            await Task.yield()
        }
    }

    func testATapAnywhereOnAStackRunsItsActionsAndVoiceOverReadsItAsAButton() throws {
        let previous = makeTapRecognizer
        makeTapRecognizer = { RecordingTapRecognizer() }
        defer { makeTapRecognizer = previous }
        let row = try XCTUnwrap(try build("""
        { "type": "hstack", "accessibilityLabel": "Keyboard", "onTap": { "action": "toggle", "path": "opened" },
          "children": [ { "type": "label", "text": "Keyboard" } ] }
        """) as? UIStackView)
        let tap = try XCTUnwrap(row.gestureRecognizers?.lazy.compactMap { $0 as? RecordingTapRecognizer }.first)

        tap.fire()

        XCTAssertEqual(data.value, ["opened": .bool(true)])
        XCTAssertTrue(row.isAccessibilityElement)
        XCTAssertTrue(row.accessibilityTraits.contains(.button))
        XCTAssertEqual(issues, [])
    }

    func testAStackWithOnTapIsHighlightedWhilePressedButNotThroughAControlOrANestedRow() async throws {
        let row = try XCTUnwrap(try build("""
        { "type": "vstack", "cornerRadius": 8, "onTap": { "action": "toggle", "path": "opened" }, "children": [
          { "type": "label", "text": "Keyboard" },
          { "type": "button", "title": "Buy", "onTap": { "action": "toggle", "path": "bought" } },
          { "type": "hstack", "onTap": { "action": "toggle", "path": "more" }, "children": [ { "type": "label" } ] }
        ]}
        """) as? UIStackView)
        let press = try XCTUnwrap(row.gestureRecognizers?.lazy.compactMap { $0 as? PressHighlight }.first)
        let wait = { try await Task.sleep(nanoseconds: UInt64(PressHighlight.delay * 2 * 1_000_000_000)) }

        XCTAssertTrue(row.subviews.first === press.highlight)
        press.press()
        XCTAssertEqual(press.highlight.alpha, 0)
        try await wait()
        XCTAssertEqual(press.highlight.alpha, 1)
        XCTAssertEqual(press.highlight.layer.cornerRadius, 8)
        press.release()
        XCTAssertEqual(press.highlight.alpha, 0)

        press.press()
        press.cancel()
        try await wait()
        XCTAssertEqual(press.highlight.alpha, 0)

        // A tap released before the delay stays highlighted for the delay.
        press.press()
        press.release()
        XCTAssertEqual(press.highlight.alpha, 1)
        try await wait()
        XCTAssertEqual(press.highlight.alpha, 0)

        let nested = try XCTUnwrap(row.arrangedSubviews[2] as? UIStackView)
        XCTAssertTrue(press.highlights(touchesIn: row.arrangedSubviews[0]))
        XCTAssertFalse(press.highlights(touchesIn: row.arrangedSubviews[1]))
        XCTAssertFalse(press.highlights(touchesIn: nested.arrangedSubviews[0]))
    }

    func testHighlightFalseTurnsTheHighlightOff() throws {
        let row = try build("""
        { "type": "hstack", "highlight": false, "onTap": { "action": "toggle", "path": "opened" }, "children": [] }
        """)
        let press = try XCTUnwrap(row.gestureRecognizers?.lazy.compactMap { $0 as? PressHighlight }.first)

        XCTAssertFalse(press.isEnabled)
        XCTAssertEqual(issues, [])
    }

    func testSetWithoutAValueTakesTheValueOfTheEvent() throws {
        let stack = try XCTUnwrap(try build("""
        { "type": "vstack", "children": [
          { "type": "textfield", "text": "$name", "onChange": { "action": "set", "path": "name" } },
          { "type": "switch", "isOn": "$enabled", "onChange": { "action": "set", "path": "enabled" } },
          { "type": "slider", "onChange": { "action": "set", "path": "volume" } }
        ]}
        """) as? UIStackView)
        let field = try XCTUnwrap(stack.arrangedSubviews[0] as? UITextField)
        let toggle = try XCTUnwrap(stack.arrangedSubviews[1] as? UISwitch)
        let slider = try XCTUnwrap(stack.arrangedSubviews[2] as? UISlider)

        field.text = "Ada"
        field.fire(.editingChanged)
        toggle.isOn = true
        toggle.fire(.valueChanged)
        slider.value = 0.5
        slider.fire(.valueChanged)

        XCTAssertEqual(data.value, ["name": .string("Ada"), "enabled": .bool(true), "volume": .number(0.5)])
        XCTAssertEqual(field.text, "Ada")
        XCTAssertTrue(toggle.isOn)
    }

    func testNavigateHandsTheResolvedURLToTheAppAndReportsWhenTheAppHasNoHandler() throws {
        let template = #"{ "type": "button", "onTap": { "action": "navigate", "url": "$detailURL" } }"#
        data.send(["detailURL": .string("app://product/1")])

        let unhandled = try XCTUnwrap(try build(template) as? UIButton)
        unhandled.fire(.touchUpInside)
        XCTAssertEqual(issues, [Issue(.unhandledAction("navigate"), at: "t.onTap")])

        var opened: [URL?] = []
        var actions = ActionRegistry.standard
        actions.register(.navigate) { opened.append($0.url("url")) }
        let handled = try XCTUnwrap(try build(template, actions: actions) as? UIButton)
        handled.fire(.touchUpInside)
        XCTAssertEqual(opened, [URL(string: "app://product/1")])
    }

    func testActionsThatCannotRunAreReportedWhenBuiltAndTheOthersStillRun() throws {
        let stack = try XCTUnwrap(try build("""
        { "type": "vstack", "children": [
          { "type": "button", "onTap": [
            "toggle",
            { "action": "share" },
            { "action": "toggle", "path": "$key", "animated": true, "onFailure": { "action": "share" } },
            { "action": "set", "path": "count", "value": 1 }
          ]},
          { "type": "button", "onTap": "$tap" }
        ]}
        """) as? UIStackView)
        XCTAssertEqual(issues, [
            Issue(.invalidAction, at: "t.children[0].onTap[0]"),
            Issue(.unknownAction("share"), at: "t.children[0].onTap[1]"),
            Issue(.unknownProperty("animated"), at: "t.children[0].onTap[2]"),
            Issue(.unknownProperty("onFailure"), at: "t.children[0].onTap[2]"),
            Issue(.referenceNotAccepted("path"), at: "t.children[0].onTap[2]"),
            Issue(.referenceNotAccepted("onTap"), at: "t.children[1]"),
        ])
        issues = []

        (stack.arrangedSubviews[0] as? UIButton)?.fire(.touchUpInside)

        XCTAssertEqual(data.value, ["count": .number(1)])
        XCTAssertEqual(issues, [Issue(.missingParameter("path"), at: "t.children[0].onTap[2]")])
    }

    func testToggleReportsAValueThatIsNotABoolAndLeavesItAsItIs() throws {
        data.send(["liked": .string("yes")])
        let button = try XCTUnwrap(try build(#"{ "type": "button", "onTap": { "action": "toggle", "path": "liked" } }"#) as? UIButton)

        button.fire(.touchUpInside)

        XCTAssertEqual(data.value, ["liked": .string("yes")])
        XCTAssertEqual(issues, [Issue(.typeMismatch(property: "liked", expected: .bool), at: "t.onTap")])
    }
}
