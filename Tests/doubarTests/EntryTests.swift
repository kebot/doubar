import XCTest
@testable import doubar

final class EntryTests: XCTestCase {
    func testStatusEntryMatchesItsItemOnly() {
        XCTAssertTrue(Entry.matches("status:eu.exelban.Stats/RAM: Pie chart",
                                    item: "eu.exelban.Stats/RAM: Pie chart"))
        XCTAssertFalse(Entry.matches("status:eu.exelban.Stats/RAM: Pie chart",
                                     item: "eu.exelban.Stats/GPU: Mini"))
    }

    func testAppEntryMatchesEveryItemOfThatApp() {
        XCTAssertTrue(Entry.matches("status:eu.exelban.Stats", item: "eu.exelban.Stats/GPU: Mini"))
        XCTAssertFalse(Entry.matches("status:eu.exelban", item: "eu.exelban.Stats/GPU: Mini"))
    }

    func testWidgetEntryNeverMatchesAStatusItem() {
        XCTAssertFalse(Entry.matches("clock", item: "clock"))
    }

    /// magpie's tooltip carries live token counts below its name. An entry
    /// saved with the whole tooltip must still find the item, whose id is
    /// now just the first line.
    func testEntrySavedWithWholeTooltipMatchesByFirstLine() {
        let saved = "status:com.yetone.magpie/magpie\nToday: 282M tokens (9.0M in)\n≈$303 · 2451 requests"
        XCTAssertTrue(Entry.matches(saved, item: "com.yetone.magpie/magpie"))
    }

    func testFirstLine() {
        XCTAssertEqual(Entry.firstLine("magpie\nToday: 1M"), "magpie")
        XCTAssertEqual(Entry.firstLine("RAM: Pie chart"), "RAM: Pie chart")
        XCTAssertEqual(Entry.firstLine(""), "")
    }
}
