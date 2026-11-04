import XCTest
@testable import doubar

final class StatusItemIdTests: XCTestCase {
    func testFirstItemOfANameHasNoNumber() {
        XCTAssertEqual(StatusItems.id(app: "eu.exelban.Stats", name: "RAM: Pie chart", index: 0),
                       "eu.exelban.Stats/RAM: Pie chart")
    }

    func testRepeatedNameIsNumbered() {
        XCTAssertEqual(StatusItems.id(app: "a", name: "x", index: 1), "a/x#1")
    }

    func testUnnamedItemIsAlwaysNumbered() {
        XCTAssertEqual(StatusItems.id(app: "com.stablyai.orca", name: "", index: 0), "com.stablyai.orca/#0")
    }
}

final class OverlappingTests: XCTestCase {
    func testSeparateItemsDoNotOverlap() {
        XCTAssertEqual(StatusItems.overlapping([0..<30, 40..<70, 80..<100]), [false, false, false])
    }

    /// macOS parks overflow items in the chevron's slot, on top of each other.
    func testPiledItemsAllOverlap() {
        XCTAssertEqual(StatusItems.overlapping([-686 ..< -637, -680 ..< -640, 100..<130]), [true, true, false])
    }

    func testTouchingItemsAreNotObscured() {
        XCTAssertEqual(StatusItems.overlapping([0..<30, 29..<60]), [false, false])
    }

    func testOverlapOfMoreThanTwoPointsIs() {
        XCTAssertEqual(StatusItems.overlapping([0..<30, 27..<60]), [true, true])
    }
}
