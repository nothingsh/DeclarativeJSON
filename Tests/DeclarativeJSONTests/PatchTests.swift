import XCTest
@testable import DeclarativeJSON

final class PatchTests: XCTestCase {

    private func patch(_ json: String) throws -> Patch {
        try DocumentDecoder().decodePatch(Data(json.utf8))
    }

    func testAPatchReadsItsTemplatesAndOperationsAndSkipsAnUnknownOperation() throws {
        let patch = try patch("""
        { "v": 1,
          "templates": { "notice": { "type": "label", "text": "$text" }, "broken": "label" },
          "operations": [
            { "op": "moveItems", "ids": ["a"] },
            { "op": "insertItems", "section": "s", "after": "a", "items": [ { "id": "n", "template": "notice" } ] },
            { "op": "insertSections", "sections": [ { "id": "t", "layout": "masonry", "items": [] } ] },
            { "op": "removeItems", "ids": ["b"] }
          ] }
        """)

        XCTAssertEqual(patch.templates, ["notice": Node(type: "label", properties: ["text": .reference("text")])])
        XCTAssertEqual(patch.operations.count, 3)
        guard case .insertItems(let items, section: "s", after: "a") = patch.operations[0] else {
            return XCTFail("not the insertion: \(patch.operations[0])")
        }
        XCTAssertEqual(items.map(\.id), ["n"])
        guard case .insertSections(let sections, after: nil) = patch.operations[1] else {
            return XCTFail("not the sections: \(patch.operations[1])")
        }
        XCTAssertEqual(sections.map(\.id), ["t"])
        XCTAssertEqual(patch.operations[2], .removeItems(["b"]))
        XCTAssertEqual(patch.issues, [
            Issue(.invalidNode, at: "templates.broken"),
            Issue(.unknownOperation("moveItems"), at: "operations[0]"),
            Issue(.unknownLayout("masonry"), at: "operations[2].sections[0]"),
        ])
        XCTAssertThrowsError(try self.patch(#"{ "v": 2, "operations": [] }"#)) { error in
            XCTAssertEqual(error as? DocumentError, .unsupportedVersion(2))
        }
    }

    func testOperationsApplyInOrderAndSkipWhatTheyCannotFindOrShow() throws {
        let document = try DocumentDecoder().decode(Data("""
        { "v": 1,
          "templates": { "row": { "type": "label", "text": "$title" } },
          "sections": [
            { "id": "s", "items": [ { "id": "a", "template": "row" }, { "id": "b", "template": "row" },
                                    { "id": "c", "template": "row" } ] },
            { "id": "t", "items": [ { "id": "d", "template": "row" } ] },
            { "id": "u", "items": [ { "id": "e", "template": "row" } ] }
          ] }
        """.utf8))
        let patch = try patch("""
        { "v": 1,
          "templates": { "card": { "type": "label", "text": "$title" } },
          "operations": [
            { "op": "moveItems" },
            { "op": "replaceItems", "items": [ { "id": "b", "template": "card" }, { "id": "z", "template": "row" } ] },
            { "op": "insertItems", "section": "s", "after": "a", "items": [
              { "id": "n1", "template": "row" }, { "id": "d", "template": "row" }, { "id": "n2", "template": "card" } ] },
            { "op": "insertItems", "section": "s", "after": "gone", "items": [ { "id": "n3", "template": "row" } ] },
            { "op": "removeItems", "ids": ["c", "gone"] },
            { "op": "replaceSections", "sections": [ { "id": "t", "header": { "template": "banner" },
              "items": [ { "id": "d2", "template": "row" }, { "id": "a", "template": "row" } ] } ] },
            { "op": "insertSections", "after": "s", "sections": [ { "id": "v", "items": [ { "id": "f", "template": "nope" } ] },
                                                                 { "id": "s", "items": [] } ] },
            { "op": "removeSections", "ids": ["u"] }
          ] }
        """)

        let result = document.applying(patch)

        XCTAssertEqual(result.document.sections.map(\.id), ["s", "v", "t"])
        XCTAssertEqual(result.document.sections.map { $0.items.map(\.id) }, [["a", "n1", "n2", "b"], [], ["d2"]])
        XCTAssertEqual(result.document.sections[0].items.map(\.template), ["row", "row", "card", "card"])
        XCTAssertNil(result.document.sections[2].header)
        XCTAssertEqual(Set(result.document.templates.keys), ["row", "card"])
        XCTAssertEqual(result.changedItems, ["b", "n1", "n2", "d2"])
        XCTAssertEqual(result.changedSections, ["t", "v"])
        XCTAssertEqual(result.issues, [
            Issue(.unknownID("z"), at: "operations[1].items[1]"),
            Issue(.duplicateID("d"), at: "operations[2].items[1]"),
            Issue(.unknownID("gone"), at: "operations[3].after"),
            Issue(.unknownID("gone"), at: "operations[4].ids[1]"),
            Issue(.unknownTemplate("banner"), at: "operations[5].sections[0].header"),
            Issue(.duplicateID("a"), at: "operations[5].sections[0].items[1]"),
            Issue(.unknownTemplate("nope"), at: "operations[6].sections[0].items[0]"),
            Issue(.duplicateID("s"), at: "operations[6].sections[1]"),
        ])
    }

    func testAppendingAddsItemsAtTheEndAndReplacesTheSectionsMore() throws {
        let document = try DocumentDecoder().decode(Data("""
        { "v": 1,
          "templates": { "row": { "type": "label", "text": "$title" } },
          "sections": [
            { "id": "s", "more": { "cursor": 2 }, "items": [ { "id": "a", "template": "row" } ] },
            { "id": "t", "more": "t2", "items": [] },
            { "id": "u", "more": null, "items": [] }
          ] }
        """.utf8))
        XCTAssertEqual(document.sections.map(\.more), [.object(["cursor": .number(2)]), .string("t2"), nil])
        let patch = try patch("""
        { "v": 1, "operations": [
          { "op": "appendItems", "section": "s", "items": [ { "id": "b", "template": "row" }, { "id": "a", "template": "row" } ],
            "more": { "cursor": 3 } },
          { "op": "appendItems", "section": "gone", "items": [] },
          { "op": "appendItems", "section": "t", "items": [ { "id": "c", "template": "row" } ] }
        ] }
        """)

        let result = document.applying(patch)

        XCTAssertEqual(result.document.sections.map { $0.items.map(\.id) }, [["a", "b"], ["c"], []])
        XCTAssertEqual(result.document.sections.map(\.more), [.object(["cursor": .number(3)]), nil, nil])
        XCTAssertEqual(result.changedItems, ["b", "c"])
        XCTAssertEqual(result.loadedSections, ["s", "t"])
        XCTAssertEqual(result.issues, [
            Issue(.duplicateID("a"), at: "operations[0].items[1]"),
            Issue(.unknownID("gone"), at: "operations[1].section"),
        ])
    }
}
