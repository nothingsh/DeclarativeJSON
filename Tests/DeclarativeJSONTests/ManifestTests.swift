import UIKit
import XCTest
@testable import DeclarativeJSON

@MainActor
final class ManifestTests: XCTestCase {

    /// manifest.json at the root of the repository is what the backend reads.
    /// When it no longer matches the code, this test rewrites it and fails, so
    /// that the change shows in the diff.
    func testTheCheckedInManifestMatchesTheStandardRegistries() throws {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("manifest.json")
        let generated = try Manifest(components: ComponentRegistry<UIView>.standard, actions: .standard, theme: .standard).encoded() + Data("\n".utf8)
        let checkedIn = try? Data(contentsOf: url)

        if checkedIn != generated {
            try generated.write(to: url)
            XCTFail("manifest.json was out of date and has been rewritten; review and commit it")
        }
    }

    func testTheManifestListsTheThirteenBuiltInTypesWithTheirPropertiesAndEvents() throws {
        guard case .object(let root) = Manifest(components: ComponentSpec.standard, actions: []).json,
              case .object(let components)? = root["components"] else {
            return XCTFail("no components")
        }

        XCTAssertEqual(Set(components.keys), [
            "vstack", "hstack", "vscroll", "hscroll", "spacer",
            "label", "image", "button", "textfield", "switch", "slider", "progress", "activity",
        ])
        XCTAssertEqual(components["spacer"], .object([
            "children": .bool(false),
            "events": .array([]),
            "properties": .object(["minLength": .object(["type": .string("number"), "reference": .bool(false)])]),
        ]))
        guard case .object(let textfield)? = components["textfield"] else { return XCTFail("no textfield") }
        XCTAssertEqual(textfield["events"], .array([.string("onChange"), .string("onReturn")]))
        guard case .object(let common)? = root["common"] else { return XCTFail("no common properties") }
        XCTAssertEqual(common["border"], .object([
            "type": .string("object"),
            "properties": .object(["color": .object(["type": .string("color")]), "width": .object(["type": .string("number")])]),
            "reference": .bool(true),
        ]))
    }

    func testTheManifestListsTheNamesOfTheTheme() throws {
        var theme = Theme.standard
        theme.colors["brand"] = .systemTeal
        theme.images["heart"] = UIImage()

        let root = Manifest(components: ComponentRegistry<UIView>.standard, actions: .standard, theme: theme).json

        guard case .object(let fields) = root, case .array(let colors)? = fields["colors"] else {
            return XCTFail("no colors")
        }
        XCTAssertTrue(colors.contains(.string("brand")))
        XCTAssertTrue(colors.contains(.string("secondaryLabel")))
        XCTAssertEqual(fields["images"], .array([.string("heart")]))
        guard case .array(let fonts)? = fields["fonts"] else { return XCTFail("no fonts") }
        XCTAssertEqual(fonts.count, 11)
    }
}
