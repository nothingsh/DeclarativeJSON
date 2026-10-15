import XCTest
@testable import DeclarativeJSON

final class DocumentTests: XCTestCase {

    private func decode(_ json: String) throws -> Document {
        try DocumentDecoder().decode(Data(json.utf8))
    }

    func testADocumentDecodesIntoTemplatesAndSections() throws {
        let document = try decode("""
        {
          "v": 1,
          "templates": {
            "product": { "type": "hstack", "spacing": 12, "children": [
              { "type": "label", "text": "$title", "lines": 2 }
            ]},
            "title": { "type": "label", "text": "$text" }
          },
          "sections": [
            { "id": "today", "layout": "carousel", "header": { "template": "title", "data": { "text": "Today" } },
              "items": [ { "id": "p1", "template": "product", "data": { "title": "Keyboard", "liked": true, "count": 1 } } ] }
          ]
        }
        """)

        XCTAssertEqual(document.templates["product"], Node(
            type: "hstack",
            properties: ["spacing": .constant(.number(12))],
            children: [Node(type: "label", properties: ["text": .reference("title"), "lines": .constant(.number(2))])]
        ))
        XCTAssertEqual(document.sections.count, 1)
        let section = document.sections[0]
        XCTAssertEqual(section.id, "today")
        XCTAssertEqual(section.layout, .carousel)
        XCTAssertEqual(section.header?.template, "title")
        XCTAssertEqual(section.header?.data, ["text": .string("Today")])
        XCTAssertEqual(section.items.map(\.id), ["p1"])
        XCTAssertEqual(section.items[0].template, "product")
        XCTAssertEqual(section.items[0].data, [
            "title": .string("Keyboard"), "liked": .bool(true), "count": .number(1),
        ])
        XCTAssertEqual(document.issues, [])
    }

    func testADocumentOfAnotherVersionFailsToDecode() {
        XCTAssertThrowsError(try decode(#"{ "v": 2, "templates": {}, "sections": [] }"#)) { error in
            XCTAssertEqual(error as? DocumentError, .unsupportedVersion(2))
        }
    }

    func testADollarStringIsAReferenceAndADoubleDollarIsALiteralDollar() {
        XCTAssertEqual(PropertyValue(.string("$title")), .reference("title"))
        XCTAssertEqual(PropertyValue(.string("$$99")), .constant(.string("$99")))
        XCTAssertEqual(PropertyValue(.string("$")), .constant(.string("$")))
        XCTAssertEqual(PropertyValue(.string("title")), .constant(.string("title")))
        XCTAssertEqual(PropertyValue(.array([.string("$title")])), .constant(.array([.string("$title")])))
    }

    func testAReferenceResolvesToTheItemDataAndToNilWhenTheKeyIsMissing() {
        let data: [String: JSONValue] = ["title": .string("Keyboard")]

        XCTAssertEqual(PropertyValue.reference("title").resolve(in: data), .string("Keyboard"))
        XCTAssertNil(PropertyValue.reference("subtitle").resolve(in: data))
        XCTAssertEqual(PropertyValue.constant(.number(1)).resolve(in: data), .number(1))
    }

    func testMalformedTemplateContentIsLeftOutAndReportedInsteadOfFailingTheDocument() throws {
        let document = try decode("""
        {
          "v": 1,
          "templates": {
            "broken": "label",
            "row": { "type": "vstack", "children": [
              "label",
              { "text": "no type" },
              { "type": "label", "children": {} }
            ]}
          },
          "sections": [ { "id": "s", "layout": "grid", "items": [] } ]
        }
        """)

        XCTAssertNil(document.templates["broken"])
        XCTAssertEqual(document.templates["row"], Node(type: "vstack", children: [Node(type: "label")]))
        XCTAssertEqual(document.sections[0].layout, .list)
        XCTAssertEqual(document.issues, [
            Issue(.invalidNode, at: "templates.broken"),
            Issue(.invalidNode, at: "templates.row.children[0]"),
            Issue(.invalidNode, at: "templates.row.children[1]"),
            Issue(.invalidChildren, at: "templates.row.children[2]"),
            Issue(.unknownLayout("grid"), at: "sections[0]"),
        ])
    }
}
