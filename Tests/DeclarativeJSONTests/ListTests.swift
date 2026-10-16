import UIKit
import XCTest
@testable import DeclarativeJSON

@MainActor
final class ListTests: XCTestCase {

    private var issues: [Issue] = []

    private func document(_ json: String) throws -> Document {
        try DocumentDecoder().decode(Data(json.utf8))
    }

    private func show(
        _ json: String,
        components: ComponentRegistry<UIView> = .standard,
        actions: ActionRegistry = .standard
    ) throws -> DocumentViewController {
        let controller = DocumentViewController(document: try document(json), components: components, actions: actions)
        controller.onIssue = { [unowned self] in issues.append($0) }
        controller.loadViewIfNeeded()
        controller.view.frame = CGRect(x: 0, y: 0, width: 320, height: 480)
        controller.view.layoutIfNeeded()
        return controller
    }

    private func cell(_ controller: DocumentViewController, _ item: Int, section: Int = 0) -> UICollectionViewCell? {
        controller.collectionView.cellForItem(at: IndexPath(item: item, section: section))
    }

    private func views<T: UIView>(_ type: T.Type, in view: UIView?) -> [T] {
        guard let view else { return [] }
        return ((view as? T).map { [$0] } ?? []) + view.subviews.flatMap { views(type, in: $0) }
    }

    func testListAndCarouselSectionsShowTheirItemsAndHeadersWithTheirTemplates() throws {
        let controller = try show("""
        { "v": 1,
          "templates": {
            "title": { "type": "label", "text": "$text", "font": "headline" },
            "row": { "type": "label", "text": "$title", "padding": 12 },
            "card": { "type": "label", "text": "$title", "width": 100, "height": 60 }
          },
          "sections": [
            { "id": "today", "header": { "template": "title", "data": { "text": "Today" } },
              "items": [ { "id": "a", "template": "row", "data": { "title": "A" } },
                         { "id": "b", "template": "row", "data": { "title": "B" } } ] },
            { "id": "picks", "layout": "carousel",
              "items": [ { "id": "c", "template": "card", "data": { "title": "C" } },
                         { "id": "d", "template": "card", "data": { "title": "D" } } ] }
          ] }
        """)
        let header = controller.collectionView.supplementaryView(
            forElementKind: UICollectionView.elementKindSectionHeader, at: IndexPath(item: 0, section: 0)
        )
        let (a, b) = (try XCTUnwrap(cell(controller, 0)), try XCTUnwrap(cell(controller, 1)))
        let (c, d) = (try XCTUnwrap(cell(controller, 0, section: 1)), try XCTUnwrap(cell(controller, 1, section: 1)))

        XCTAssertEqual(views(UILabel.self, in: header).map(\.text), ["Today"])
        XCTAssertEqual(views(UILabel.self, in: a).map(\.text), ["A"])
        XCTAssertEqual(views(UILabel.self, in: d).map(\.text), ["D"])
        XCTAssertEqual(a.frame.width, 320)
        XCTAssertEqual(b.frame.minY, a.frame.maxY)
        XCTAssertEqual(c.frame.size, CGSize(width: 100, height: 60))
        XCTAssertEqual(d.frame.minY, c.frame.minY)
        XCTAssertEqual(d.frame.minX, c.frame.maxX)
        XCTAssertEqual(issues, [])
    }

    func testAGridLaysItsItemsOutInRowsOfEqualWidthAsTallAsTheirTallestCell() throws {
        let controller = try show("""
        { "v": 1,
          "templates": { "tile": { "type": "label", "height": "$height" } },
          "sections": [
            { "id": "grid", "layout": "grid", "columns": 3, "spacing": 10,
              "items": [ { "id": "a", "template": "tile", "data": { "height": 40 } },
                         { "id": "b", "template": "tile", "data": { "height": 80 } },
                         { "id": "c", "template": "tile", "data": { "height": 40 } },
                         { "id": "d", "template": "tile", "data": { "height": 40 } } ] },
            { "id": "wrong", "layout": "grid", "columns": 0, "spacing": "wide",
              "items": [ { "id": "e", "template": "tile", "data": { "height": 40 } },
                         { "id": "f", "template": "tile", "data": { "height": 40 } } ] }
          ] }
        """)
        func frames(_ section: Int, _ count: Int) -> [CGRect?] {
            (0..<count).map { cell(controller, $0, section: section)?.frame }
        }

        XCTAssertEqual(frames(0, 4), [
            CGRect(x: 0, y: 0, width: 100, height: 40),
            CGRect(x: 110, y: 0, width: 100, height: 80),
            CGRect(x: 220, y: 0, width: 100, height: 40),
            CGRect(x: 0, y: 90, width: 100, height: 40),
        ])
        // The defaults: two columns, no spacing.
        XCTAssertEqual(frames(1, 2), [
            CGRect(x: 0, y: 130, width: 160, height: 40),
            CGRect(x: 160, y: 130, width: 160, height: 40),
        ])
        XCTAssertEqual(issues, [
            Issue(.typeMismatch(property: "columns", expected: .integer), at: "sections[1]"),
            Issue(.typeMismatch(property: "spacing", expected: .number), at: "sections[1]"),
        ])
    }

    func testDuplicateIDsAndUnknownTemplatesAreLeftOutAndEachIssueIsReportedOnce() throws {
        let controller = try show("""
        { "v": 1,
          "templates": { "row": { "type": "label", "text": "$title", "colour": "red" } },
          "sections": [
            { "id": "s", "header": { "template": "banner" }, "items": [
              { "id": "a", "template": "row" },
              { "id": "a", "template": "row" },
              { "id": "b", "template": "card" },
              { "id": "c", "template": "row" }
            ]},
            { "id": "s", "items": [ { "id": "d", "template": "row" } ] }
          ] }
        """)

        XCTAssertEqual(controller.collectionView.numberOfSections, 1)
        XCTAssertEqual(controller.collectionView.numberOfItems(inSection: 0), 2)
        XCTAssertEqual(issues, [
            Issue(.unknownTemplate("banner"), at: "sections[0].header"),
            Issue(.duplicateID("a"), at: "sections[0].items[1]"),
            Issue(.unknownTemplate("card"), at: "sections[0].items[2]"),
            Issue(.duplicateID("s"), at: "sections[1]"),
            Issue(.unknownProperty("colour"), at: "templates.row"),
        ])
    }

    func testAToggleResizesTheCellAndStaysWhenTheCellIsReusedForAnotherItem() throws {
        let items = (0..<40).map { #"{ "id": "\#($0)", "template": "row", "data": { "title": "Item \#($0)", "expanded": false } }"# }
        let controller = try show("""
        { "v": 1,
          "templates": { "row": { "type": "vstack", "alignment": "fill", "children": [
            { "type": "label", "text": "$title" },
            { "type": "label", "text": "Details", "isVisible": "$expanded" },
            { "type": "button", "title": "More", "onTap": { "action": "toggle", "path": "expanded" } }
          ]}},
          "sections": [ { "id": "s", "items": [ \(items.joined(separator: ",")) ] } ] }
        """)
        let collectionView = controller.collectionView
        let first = try XCTUnwrap(cell(controller, 0))
        let collapsedHeight = first.frame.height

        views(UIButton.self, in: first).first?.fire(.touchUpInside)
        collectionView.layoutIfNeeded()
        XCTAssertGreaterThan(try XCTUnwrap(cell(controller, 0)).frame.height, collapsedHeight)

        // In steps, as scrolling does, so that cells leave before others come.
        // Whether the details show when the first cell is reused for another
        // item, which is collapsed.
        var detailsShownInReuse: Bool?
        func scroll(to y: CGFloat) {
            let start = collectionView.contentOffset.y
            for step in 1...20 {
                collectionView.contentOffset.y = start + (y - start) * CGFloat(step) / 20
                collectionView.layoutIfNeeded()
                let labels = views(UILabel.self, in: first)
                if collectionView.visibleCells.contains(first), labels.first?.text != "Item 0" {
                    detailsShownInReuse = labels.contains { $0.text == "Details" && !$0.isHidden }
                }
            }
        }
        scroll(to: collectionView.contentSize.height - collectionView.bounds.height)
        XCTAssertNil(cell(controller, 0))
        XCTAssertEqual(detailsShownInReuse, false, "the first cell is reused for a collapsed item")

        scroll(to: 0)
        let shown = try XCTUnwrap(cell(controller, 0))
        XCTAssertTrue(views(UILabel.self, in: shown).contains { $0.text == "Details" && !$0.isHidden })
        XCTAssertEqual(issues, [])
    }

    func testAChangeMadeAfterTheActionReturnedGoesToItsItemAndKeepsTheChangesMadeInBetween() throws {
        var later: ActionContext?
        var actions = ActionRegistry.standard
        actions.register(ActionSpec("later")) { later = $0 }
        let items = (0..<40).map {
            #"{ "id": "\#($0)", "template": "row", "data": { "title": "Item \#($0)", "liked": false, "expanded": false } }"#
        }
        let controller = try show("""
        { "v": 1,
          "templates": { "row": { "type": "vstack", "alignment": "fill", "children": [
            { "type": "label", "text": "$title" },
            { "type": "label", "text": "Liked", "isVisible": "$liked" },
            { "type": "label", "text": "Details", "isVisible": "$expanded" },
            { "type": "button", "title": "Like", "onTap": { "action": "later" } },
            { "type": "button", "title": "More", "onTap": { "action": "toggle", "path": "expanded" } }
          ]}},
          "sections": [ { "id": "s", "items": [ \(items.joined(separator: ",")) ] } ] }
        """, actions: actions)
        let collectionView = controller.collectionView
        // Without prefetching, a cell that leaves is reused for the next item.
        collectionView.isPrefetchingEnabled = false
        let first = try XCTUnwrap(cell(controller, 0))
        let buttons = views(UIButton.self, in: first)
        buttons[0].fire(.touchUpInside)
        let context = try XCTUnwrap(later)
        // Item 0 changes while the app waits, as for a request.
        buttons[1].fire(.touchUpInside)
        collectionView.layoutIfNeeded()

        // Finishes the like once the first cell is reused for another item.
        var likedShownInReuse: Bool?
        let end = collectionView.contentSize.height - collectionView.bounds.height
        for step in 1...20 where likedShownInReuse == nil {
            collectionView.contentOffset.y = end * CGFloat(step) / 20
            collectionView.layoutIfNeeded()
            if collectionView.visibleCells.contains(first), views(UILabel.self, in: first).first?.text != "Item 0" {
                context.update { $0["liked"] = .bool(true) }
                likedShownInReuse = views(UILabel.self, in: first).contains { $0.text == "Liked" && !$0.isHidden }
            }
        }
        XCTAssertEqual(likedShownInReuse, false, "the first cell shows another item")

        collectionView.contentOffset.y = 0
        collectionView.layoutIfNeeded()
        let shown = views(UILabel.self, in: try XCTUnwrap(cell(controller, 0))).filter { !$0.isHidden }.compactMap(\.text)
        XCTAssertTrue(shown.contains("Liked"))
        XCTAssertTrue(shown.contains("Details"), "the change made in between stays")
        XCTAssertEqual(issues, [])
    }

    func testAnAsyncActionIsCancelledWhenThePageGoesAwayAndTheActionsAfterItDoNotRun() async throws {
        var cancelled = false
        var recorded = 0
        var actions = ActionRegistry.standard
        actions.register(ActionSpec("record")) { _ in recorded += 1 }
        actions.register(ActionSpec("wait")) { _ in
            do {
                try await Task.sleep(nanoseconds: 60_000_000_000)
            } catch {
                cancelled = error is CancellationError
                throw error
            }
        }
        weak var page: DocumentViewController?
        try autoreleasepool {
            let controller = try show("""
            { "v": 1,
              "templates": { "row": { "type": "button", "title": "Like", "onTap": [
                { "action": "wait", "onFailure": { "action": "record" } }, { "action": "record" }
              ]}},
              "sections": [ { "id": "s", "items": [ { "id": "a", "template": "row" } ] } ] }
            """, actions: actions)
            page = controller
            views(UIButton.self, in: cell(controller, 0)).first?.fire(.touchUpInside)
        }
        XCTAssertNil(page)

        for _ in 0..<100 where !cancelled {
            await Task.yield()
        }
        XCTAssertTrue(cancelled)
        XCTAssertEqual(recorded, 0)
    }

    func testAnActionInAHeaderChangesTheHeadersData() throws {
        let controller = try show("""
        { "v": 1,
          "templates": {
            "title": { "type": "vstack", "children": [
              { "type": "label", "text": "Filters", "isVisible": "$expanded" },
              { "type": "button", "title": "Show", "onTap": { "action": "toggle", "path": "expanded" } }
            ]},
            "row": { "type": "label", "text": "$title" }
          },
          "sections": [ { "id": "s", "header": { "template": "title", "data": { "expanded": false } },
            "items": [ { "id": "a", "template": "row", "data": { "title": "A" } } ] } ] }
        """)
        let header = try XCTUnwrap(controller.collectionView.supplementaryView(
            forElementKind: UICollectionView.elementKindSectionHeader, at: IndexPath(item: 0, section: 0)
        ))

        views(UIButton.self, in: header).first?.fire(.touchUpInside)

        XCTAssertTrue(views(UILabel.self, in: header).contains { $0.text == "Filters" && !$0.isHidden })
        XCTAssertEqual(issues, [])
    }

    func testAnActionKnowsTheItemShownWhenItRunsTheViewThatSentItAndThePage() throws {
        var contexts: [ActionContext] = []
        var actions = ActionRegistry.standard
        actions.register(ActionSpec("record")) { contexts.append($0) }
        func page(_ section: String, _ item: String) -> String {
            """
            { "v": 1,
              "templates": {
                "title": { "type": "button", "title": "Title", "onTap": { "action": "record" } },
                "row": { "type": "button", "title": "Row", "onTap": { "action": "record" } }
              },
              "sections": [ { "id": "\(section)", "header": { "template": "title" },
                "items": [ { "id": "\(item)", "template": "row" } ] } ] }
            """
        }
        let controller = try show(page("s", "a"), actions: actions)
        let built = views(UIButton.self, in: cell(controller, 0)).first
        // The cell's views, built for item a, now show item b.
        controller.setDocument(try document(page("t", "b")), animatingDifferences: false)
        controller.view.layoutIfNeeded()
        let row = try XCTUnwrap(views(UIButton.self, in: cell(controller, 0)).first)
        XCTAssertIdentical(row, built)
        let header = try XCTUnwrap(views(UIButton.self, in: controller.collectionView.supplementaryView(
            forElementKind: UICollectionView.elementKindSectionHeader, at: IndexPath(item: 0, section: 0)
        )).first)

        row.fire(.touchUpInside)
        header.fire(.touchUpInside)

        XCTAssertEqual(contexts.map(\.item), [
            ItemInfo(id: "b", section: "t", template: "row"),
            ItemInfo(id: nil, section: "t", template: "title"),
        ])
        XCTAssertEqual(contexts.map(\.item.isHeader), [false, true])
        XCTAssertIdentical(contexts.first?.sourceView, row)
        XCTAssertIdentical(contexts.last?.sourceView, header)
        XCTAssertIdentical(contexts.first?.page, controller)
        XCTAssertEqual(issues, [])
    }

    func testAPatchShowsItsItemsAndTheOtherItemsKeepTheirLocalChanges() throws {
        let controller = try show("""
        { "v": 1,
          "templates": { "row": { "type": "vstack", "children": [
            { "type": "label", "text": "$title" },
            { "type": "label", "text": "Liked", "isVisible": "$liked" },
            { "type": "button", "title": "Like", "onTap": { "action": "toggle", "path": "liked" } }
          ]}},
          "sections": [ { "id": "s", "items": [
            { "id": "a", "template": "row", "data": { "title": "A", "liked": false } },
            { "id": "b", "template": "row", "data": { "title": "B", "liked": false } } ] } ] }
        """)
        views(UIButton.self, in: cell(controller, 0)).first?.fire(.touchUpInside)
        views(UIButton.self, in: cell(controller, 1)).first?.fire(.touchUpInside)

        controller.apply(try DocumentDecoder().decodePatch(Data("""
        { "v": 1,
          "templates": { "notice": { "type": "label", "text": "$text" } },
          "operations": [
            { "op": "replaceItems", "items": [ { "id": "b", "template": "row", "data": { "title": "B2", "liked": false } } ] },
            { "op": "insertItems", "section": "s", "after": "b", "items": [
              { "id": "c", "template": "notice", "data": { "text": "New" } } ] }
          ] }
        """.utf8)), animatingDifferences: false)
        controller.view.layoutIfNeeded()

        func shown(_ item: Int) -> [String?] {
            views(UILabel.self, in: cell(controller, item)).filter { !$0.isHidden }.map(\.text)
        }
        XCTAssertEqual(shown(0), ["A", "Liked", "Like"])
        XCTAssertEqual(shown(1), ["B2", "Like"])
        XCTAssertEqual(shown(2), ["New"])
        XCTAssertEqual(controller.document.sections[0].items.map(\.id), ["a", "b", "c"])
        XCTAssertEqual(issues, [])
    }

    func testCellsBuildTheirTemplateOnceAndANewDocumentSendsItsData() throws {
        var builds = 0
        var components = ComponentRegistry<UIView>.standard
        components.register(ComponentSpec("title", properties: ["text": PropertySpec(.string)])) { context in
            builds += 1
            return UILabel().onValue(context.string("text")) { $0.text = $1 }
        }
        func page(_ first: String, _ second: String, template: String = #""text": "$title""#) -> String {
            """
            { "v": 1, "templates": { "row": { "type": "title", \(template) } },
              "sections": [ { "id": "s", "items": [
                { "id": "a", "template": "row", "data": { "title": "\(first)" } },
                { "id": "b", "template": "row", "data": { "title": "\(second)" } } ] } ] }
            """
        }
        let controller = try show(page("A", "B"), components: components)
        XCTAssertEqual(builds, 2)

        controller.setDocument(try document(page("A2", "B2")), animatingDifferences: false)
        controller.view.layoutIfNeeded()
        XCTAssertEqual(builds, 2)
        XCTAssertEqual(views(UILabel.self, in: cell(controller, 1)).map(\.text), ["B2"])

        controller.setDocument(try document(page("A3", "B3", template: #""text": "New""#)), animatingDifferences: false)
        controller.view.layoutIfNeeded()
        XCTAssertEqual(builds, 4)
        XCTAssertEqual(views(UILabel.self, in: cell(controller, 1)).map(\.text), ["New"])
    }

    private func patch(_ json: String) throws -> Patch {
        try DocumentDecoder().decodePatch(Data(json.utf8))
    }

    private func footer(_ controller: DocumentViewController, section: Int = 0) -> LoadMoreFooter? {
        controller.collectionView.supplementaryView(
            forElementKind: LoadMoreFooter.kind, at: IndexPath(item: 0, section: section)
        ) as? LoadMoreFooter
    }

    func testScrollingNearTheEndOfASectionWithMoreAsksForItsNextItemsOnce() throws {
        let items = (0..<30).map { #"{ "id": "\#($0)", "template": "row", "data": { "title": "Item \#($0)" } }"# }
        let controller = try show("""
        { "v": 1,
          "templates": { "row": { "type": "label", "text": "$title", "height": 40 } },
          "sections": [ { "id": "feed", "more": "page2", "items": [ \(items.joined(separator: ",")) ] } ] }
        """)
        var requests: [(String, JSONValue)] = []
        let asked = expectation(description: "asked for more")
        controller.onLoadMore = { requests.append(($0, $1)); asked.fulfill() }
        let collectionView = controller.collectionView
        func scroll(to y: CGFloat) {
            let start = collectionView.contentOffset.y
            for step in 1...10 {
                collectionView.contentOffset.y = start + (y - start) * CGFloat(step) / 10
                collectionView.layoutIfNeeded()
            }
        }

        // The page asks from item 25 on; items 10 to 22 show. iOS 15 shows a
        // little more than the bounds.
        scroll(to: 400)
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.05))
        XCTAssertEqual(requests.count, 0)

        let end = collectionView.contentSize.height - collectionView.bounds.height
        scroll(to: end)
        wait(for: [asked], timeout: 1)
        scroll(to: 0)
        scroll(to: end)
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.05))

        XCTAssertEqual(requests.map(\.0), ["feed"])
        XCTAssertEqual(requests.map(\.1), [.string("page2")])
        XCTAssertEqual(footer(controller)?.spinner.isAnimating, true)
        XCTAssertEqual(issues, [])
    }

    func testAFailedLoadRetriesAndAnAppendWhoseEndStillShowsAsksForTheNextItems() throws {
        let controller = try show("""
        { "v": 1,
          "templates": { "row": { "type": "label", "text": "$title", "height": 40 } },
          "sections": [ { "id": "feed", "more": "page2", "items": [ { "id": "a", "template": "row" } ] } ] }
        """)
        var requests: [JSONValue] = []
        var asked = expectation(description: "asked for page 2")
        controller.onLoadMore = { requests.append($1); asked.fulfill() }
        wait(for: [asked], timeout: 1)

        controller.showLoadMoreFailure(in: "feed")
        let shown = try XCTUnwrap(footer(controller))
        XCTAssertFalse(shown.retryButton.isHidden)
        XCTAssertFalse(shown.spinner.isAnimating)
        asked = expectation(description: "asked for page 2 again")
        shown.retryButton.fire(.touchUpInside)
        XCTAssertTrue(shown.retryButton.isHidden)
        wait(for: [asked], timeout: 1)

        // The footer still shows, and no cell comes into view to ask. (iOS 15
        // shows the footer again in the next layout, which asks too.)
        asked = expectation(description: "asked for page 3")
        controller.apply(try patch("""
        { "v": 1, "operations": [ { "op": "appendItems", "section": "feed", "items": [], "more": "page3" } ] }
        """), animatingDifferences: false)
        controller.view.layoutIfNeeded()
        wait(for: [asked], timeout: 1)

        controller.apply(try patch("""
        { "v": 1, "operations": [ { "op": "appendItems", "section": "feed",
          "items": [ { "id": "b", "template": "row" } ] } ] }
        """), animatingDifferences: false)
        controller.view.layoutIfNeeded()
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.05))

        XCTAssertEqual(requests, [.string("page2"), .string("page2"), .string("page3")])
        XCTAssertEqual(controller.collectionView.numberOfItems(inSection: 0), 2)
        XCTAssertNil(footer(controller))
        XCTAssertEqual(issues, [])
    }

    func testACarouselWithMoreAsksForItsNextItemsWithoutAFooter() throws {
        let controller = try show("""
        { "v": 1,
          "templates": { "card": { "type": "label", "width": 100, "height": 60 } },
          "sections": [ { "id": "picks", "layout": "carousel", "more": "page2",
            "items": [ { "id": "a", "template": "card" }, { "id": "b", "template": "card" } ] } ] }
        """)
        let asked = expectation(description: "asked for more")
        controller.onLoadMore = { _, _ in asked.fulfill() }

        wait(for: [asked], timeout: 1)
        XCTAssertNil(footer(controller))
    }

    func testTheScrollViewDelegateGetsTheCollectionViewsScrollCallbacks() throws {
        final class Recorder: NSObject, UIScrollViewDelegate {
            var offsets: [CGFloat] = []
            func scrollViewDidScroll(_ scrollView: UIScrollView) { offsets.append(scrollView.contentOffset.y) }
        }
        let items = (0..<30).map { #"{ "id": "\#($0)", "template": "row" }"# }
        let controller = try show("""
        { "v": 1, "templates": { "row": { "type": "label", "height": 40 } },
          "sections": [ { "id": "s", "items": [ \(items.joined(separator: ",")) ] } ] }
        """)
        let recorder = Recorder()
        controller.scrollViewDelegate = recorder

        controller.collectionView.contentOffset.y = 100

        XCTAssertEqual(recorder.offsets, [100])
    }
}

