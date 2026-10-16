import Combine
import DeclarativeCombine
import DeclarativeUIKit
import UIKit
import XCTest
@testable import DeclarativeJSON

@MainActor
final class BuildingTests: XCTestCase {

    private var issues: [Issue] = []
    private let data = CurrentValueSubject<[String: JSONValue], Never>([:])

    private func build(_ json: String, components: ComponentRegistry<UIView> = .standard) throws -> UIView {
        let value = try JSONDecoder().decode(JSONValue.self, from: Data(json.utf8))
        var decodeIssues: [Issue] = []
        let node = try XCTUnwrap(Node(value, path: "t", issues: &decodeIssues))
        let builder = NodeBuilder(
            components: components, actions: .standard, data: data, target: { [data] in
                ActionTarget(item: ItemInfo(id: "a", section: "s", template: "t"), page: nil) { change in
                    var changed = data.value
                    change(&changed)
                    data.send(changed)
                    return changed
                }
            }
        ) { [unowned self] in
            issues.append($0)
        }
        return builder.build(node, path: "t")
    }

    func testAReferenceFollowsTheItemDataAndAConstantStays() throws {
        data.send(["title": .string("Keyboard")])
        let label = try XCTUnwrap(try build(#"{ "type": "label", "text": "$title", "numberOfLines": 2 }"#) as? UILabel)

        XCTAssertEqual(label.text, "Keyboard")
        XCTAssertEqual(label.numberOfLines, 2)

        data.send(["title": .string("Mouse")])
        XCTAssertEqual(label.text, "Mouse")
        XCTAssertEqual(label.numberOfLines, 2)

        data.send([:])
        XCTAssertNil(label.text)
        XCTAssertEqual(issues, [])
    }

    func testAnUnknownTypeShowsItsFallbackAndIsStillReported() throws {
        data.send(["scoreText": .string("4.5")])
        let stack = try XCTUnwrap(try build("""
        { "type": "vstack", "children": [
          { "type": "rating", "value": "$score", "fallback": { "type": "label", "text": "$scoreText" } },
          { "type": "chart", "fallback": { "type": "sparkline", "fallback": { "type": "label", "text": "No chart" } } },
          { "type": "label", "text": "Known", "fallback": { "type": "label", "text": "Unused" } }
        ]}
        """) as? UIStackView)

        XCTAssertEqual(stack.arrangedSubviews.map { ($0 as? UILabel)?.text }, ["4.5", "No chart", "Known"])
        XCTAssertEqual(issues, [
            Issue(.unknownType("rating"), at: "t.children[0]"),
            Issue(.unknownType("chart"), at: "t.children[1]"),
            Issue(.unknownType("sparkline"), at: "t.children[1].fallback"),
        ])
    }

    func testAValueOfTheWrongTypeIsReportedAndTreatedAsMissing() throws {
        data.send(["lines": .number(3)])
        let label = try XCTUnwrap(try build(#"{ "type": "label", "numberOfLines": "$lines", "width": -5 }"#) as? UILabel)
        XCTAssertEqual(label.numberOfLines, 3)

        data.send(["lines": .string("three")])

        XCTAssertEqual(label.numberOfLines, 1)
        XCTAssertFalse(label.constraints.contains { $0.firstAttribute == .width && $0.isActive })
        XCTAssertEqual(issues, [
            Issue(.typeMismatch(property: "width", expected: .number), at: "t"),
            Issue(.typeMismatch(property: "numberOfLines", expected: .integer), at: "t"),
        ])
    }

    func testIsHiddenAndIsVisibleShowOneOfTwoViewsWithTheSameReference() throws {
        data.send(["liked": .bool(false)])
        let stack = try XCTUnwrap(try build("""
        { "type": "hstack", "children": [
          { "type": "image", "image": "heart", "isHidden": "$liked" },
          { "type": "image", "image": "heart.fill", "isVisible": "$liked" }
        ]}
        """) as? UIStackView)
        let (unliked, liked) = (stack.arrangedSubviews[0], stack.arrangedSubviews[1])

        XCTAssertEqual([unliked.isHidden, liked.isHidden], [false, true])
        data.send(["liked": .bool(true)])
        XCTAssertEqual([unliked.isHidden, liked.isHidden], [true, false])
    }

    func testUnknownTypesPropertiesAndChildrenAreReportedAndTheRestIsBuilt() throws {
        let stack = try XCTUnwrap(try build("""
        { "type": "vstack", "children": [
          { "type": "rating" },
          { "type": "label", "text": "Hi", "colour": "red", "onTap": { "action": "toggle", "path": "x" },
            "children": [ { "type": "label" } ] },
          { "type": "spacer", "minLength": "$gap" }
        ]}
        """) as? UIStackView)

        XCTAssertEqual(stack.arrangedSubviews.count, 3)
        XCTAssertEqual(String(describing: type(of: stack.arrangedSubviews[0])), "UIView")
        XCTAssertEqual((stack.arrangedSubviews[1] as? UILabel)?.text, "Hi")
        XCTAssertEqual(issues, [
            Issue(.unknownType("rating"), at: "t.children[0]"),
            Issue(.unknownProperty("colour"), at: "t.children[1]"),
            Issue(.unknownProperty("onTap"), at: "t.children[1]"),
            Issue(.unexpectedChildren, at: "t.children[1]"),
            Issue(.referenceNotAccepted("minLength"), at: "t.children[2]"),
        ])
    }

    func testColorsAndFontsAreReadFromEachOfTheirForms() throws {
        let dark = UITraitCollection(userInterfaceStyle: .dark)
        let light = UITraitCollection(userInterfaceStyle: .light)
        func label(_ properties: String) throws -> UILabel {
            try XCTUnwrap(try build(#"{ "type": "label", \#(properties) }"#) as? UILabel)
        }

        XCTAssertEqual(try label(#""textColor": "secondaryLabel""#).textColor, .secondaryLabel)
        XCTAssertEqual(try label(##""textColor": "#FF000080""##).textColor, UIColor(red: 1, green: 0, blue: 0, alpha: 128 / 255))
        let adaptive = try label(##""textColor": { "light": "#000000", "dark": "white" }"##).textColor
        XCTAssertEqual(adaptive?.resolvedColor(with: light), UIColor(red: 0, green: 0, blue: 0, alpha: 1))
        XCTAssertEqual(adaptive?.resolvedColor(with: dark), .white)
        XCTAssertEqual(try label(#""font": "headline""#).font, .preferredFont(forTextStyle: .headline))
        XCTAssertEqual(try label(#""font": { "size": 15, "weight": "semibold" }"#).font, .systemFont(ofSize: 15, weight: .semibold))
        XCTAssertEqual(issues, [])

        _ = try label(##""textColor": "#F00", "font": { "size": 15, "weight": "extraBold" }"##)
        XCTAssertEqual(issues, [
            Issue(.typeMismatch(property: "font", expected: .font), at: "t"),
            Issue(.typeMismatch(property: "textColor", expected: .color), at: "t"),
        ])
    }

    func testAStackDrawsItsOwnBackgroundCornersAndBorder() throws {
        let stack = try XCTUnwrap(try build("""
        { "type": "hstack", "background": "systemBlue", "cornerRadius": 8,
          "border": { "color": "black", "width": 1 }, "children": [ { "type": "label" } ] }
        """) as? UIStackView)

        XCTAssertEqual(stack.backgroundColor, .systemBlue)
        XCTAssertEqual(stack.layer.cornerRadius, 8)
        XCTAssertEqual(stack.layer.borderWidth, 1)
        XCTAssertEqual(stack.subviews, stack.arrangedSubviews)
    }

    func testPaddingOnALeafPutsItInAStackThatTakesTheOtherProperties() throws {
        data.send(["width": .number(120)])
        let outer = try build("""
        { "type": "label", "padding": { "horizontal": 8, "top": 4 }, "width": "$width", "accessibilityLabel": "Name" }
        """)
        let wrapper = try XCTUnwrap(outer as? UIStackView)
        let label = try XCTUnwrap(wrapper.arrangedSubviews.first as? UILabel)

        XCTAssertEqual(wrapper.directionalLayoutMargins, NSDirectionalEdgeInsets(top: 4, leading: 8, bottom: 0, trailing: 8))
        XCTAssertEqual(label.accessibilityLabel, "Name")
        XCTAssertEqual(wrapper.constraints.first { $0.firstAttribute == .width && $0.isActive }?.constant, 120)

        data.send([:])
        XCTAssertFalse(wrapper.constraints.contains { $0.firstAttribute == .width && $0.isActive })
    }

    func testAnImageShowsItsNamedImageUntilItsURLLoadsAndIgnoresALoadThatWasReplaced() throws {
        var completions: [URL: @MainActor @Sendable (UIImage?) -> Void] = [:]
        var cancelled: [URL] = []
        let loader = ImageLoader { url, completion in
            completions[url] = completion
            return AnyCancellable { cancelled.append(url) }
        }
        let first = URL(string: "https://example.com/1.png")!
        let second = URL(string: "https://example.com/2.png")!
        let loaded = UIGraphicsImageRenderer(size: CGSize(width: 1, height: 1)).image { _ in }
        data.send(["url": .string(first.absoluteString)])
        let imageView = try XCTUnwrap(
            try build(#"{ "type": "image", "image": "photo", "url": "$url" }"#, components: .standard(imageLoader: loader))
                as? UIImageView
        )
        let placeholder = imageView.image
        XCTAssertNotNil(placeholder)

        data.send(["url": .string(second.absoluteString)])
        XCTAssertEqual(cancelled, [first])
        completions[first]?(loaded)
        XCTAssertEqual(imageView.image, placeholder)

        completions[second]?(loaded)
        XCTAssertEqual(imageView.image, loaded)
    }

    func testAnAppComponentIsBuiltAndListedInTheManifest() throws {
        var components = ComponentRegistry<UIView>.standard
        components.register(ComponentSpec("rating", properties: ["value": PropertySpec(.number)])) { context in
            UISlider().onValue(context.number("value")) { $0.value = Float($1 ?? 0) }
        }
        data.send(["score": .number(0.5)])

        let rating = try XCTUnwrap(try build(#"{ "type": "rating", "value": "$score" }"#, components: components) as? UISlider)

        XCTAssertEqual(rating.value, 0.5)
        XCTAssertTrue(components.specs.contains { $0.type == "rating" })
        XCTAssertEqual(issues, [])
    }
}
