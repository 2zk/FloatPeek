import XCTest
@testable import FloatPeek

final class ImageSelectionTests: XCTestCase {
    private let ids = (0..<6).map {
        URL(fileURLWithPath: "/tmp/image-\($0).png")
    }

    func testReplaceAndToggleSelection() {
        var selection = ImageSelection()

        selection.select(ids[1], mode: .replace, orderedIDs: ids)
        selection.select(ids[3], mode: .toggle, orderedIDs: ids)

        XCTAssertEqual(selection.selectedIDs, Set([ids[1], ids[3]]))
        XCTAssertEqual(selection.focusedID, ids[3])

        selection.select(ids[3], mode: .toggle, orderedIDs: ids)

        XCTAssertEqual(selection.selectedIDs, [ids[1]])
        XCTAssertEqual(selection.focusedID, ids[1])
    }

    func testRangeSelectionUsesPreviousSelectionAsAnchor() {
        var selection = ImageSelection()
        selection.select(ids[1], mode: .replace, orderedIDs: ids)

        selection.select(ids[4], mode: .range, orderedIDs: ids)

        XCTAssertEqual(selection.selectedIDs, Set(ids[1...4]))
        XCTAssertEqual(selection.focusedID, ids[4])
    }

    func testMovingSelectionUsesGridColumnCount() {
        var selection = ImageSelection()
        selection.select(ids[1], mode: .replace, orderedIDs: ids)

        XCTAssertTrue(selection.move(.down, columnCount: 2, orderedIDs: ids))
        XCTAssertEqual(selection.focusedID, ids[3])
        XCTAssertTrue(selection.move(.left, columnCount: 2, orderedIDs: ids))
        XCTAssertEqual(selection.focusedID, ids[2])
    }

    func testMovingBeyondBoundsDoesNotChangeSelection() {
        var selection = ImageSelection()
        selection.select(ids[0], mode: .replace, orderedIDs: ids)

        XCTAssertFalse(selection.move(.up, columnCount: 3, orderedIDs: ids))
        XCTAssertEqual(selection.focusedID, ids[0])
    }

    func testShiftMovingSelectionExpandsAndContractsFromAnchor() {
        var selection = ImageSelection()
        selection.select(ids[1], mode: .replace, orderedIDs: ids)

        XCTAssertTrue(
            selection.move(
                .down,
                columnCount: 2,
                orderedIDs: ids,
                extendingSelection: true
            )
        )
        XCTAssertEqual(selection.selectedIDs, Set(ids[1...3]))
        XCTAssertEqual(selection.focusedID, ids[3])

        XCTAssertTrue(
            selection.move(
                .right,
                columnCount: 2,
                orderedIDs: ids,
                extendingSelection: true
            )
        )
        XCTAssertEqual(selection.selectedIDs, Set(ids[1...4]))
        XCTAssertEqual(selection.focusedID, ids[4])

        XCTAssertTrue(
            selection.move(
                .left,
                columnCount: 2,
                orderedIDs: ids,
                extendingSelection: true
            )
        )
        XCTAssertEqual(selection.selectedIDs, Set(ids[1...3]))
        XCTAssertEqual(selection.focusedID, ids[3])
    }

    func testReconcileRemovesMissingItemsAndKeepsOrderedFocus() {
        var selection = ImageSelection()
        selection.select(ids[1], mode: .replace, orderedIDs: ids)
        selection.select(ids[3], mode: .toggle, orderedIDs: ids)

        selection.reconcile(orderedIDs: [ids[0], ids[1], ids[2]])

        XCTAssertEqual(selection.selectedIDs, [ids[1]])
        XCTAssertEqual(selection.focusedID, ids[1])
    }
}
