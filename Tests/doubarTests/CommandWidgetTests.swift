import XCTest
@testable import doubar

final class CommandWidgetTests: XCTestCase {
    func testCommandEntries() {
        XCTAssertEqual(Entry.command("battery"), "widget:battery")
        XCTAssertEqual(Entry.commandId("widget:battery"), "battery")
        XCTAssertNil(Entry.commandId("clock"))
        XCTAssertFalse(Entry.isStatus("widget:battery"))
    }

    func testSanitizedId() {
        XCTAssertEqual(Entry.sanitizedId("My Battery!"), "my-battery")
        XCTAssertNil(Entry.sanitizedId("!!!"))
    }

    func testDecodeSkipsTablesWithoutACommandAndClampsInterval() throws {
        let doc = try TomlDocument("""
        [widget.a]
        command = "date"
        interval = 0
        icon = "clock"
        [widget.b]
        interval = 5
        """)
        let commands = Config.commands(doc["widget"])
        XCTAssertEqual(Array(commands.keys), ["a"])
        XCTAssertEqual(commands["a"]?.interval, 1)
        XCTAssertEqual(commands["a"]?.icon, "clock")
        XCTAssertEqual(commands["a"]?.maxLength, 40)
    }

    func testRemovingTableKeepsTheRest() throws {
        let doc = try TomlDocument("""
        [bar]
        gap = 4

        [widget.a]
        command = "date"

        [clock]
        format = "HH:mm"
        """)
        let out = doc.removingTable(["widget", "a"])
        let parsed = try TomlDocument(out)
        XCTAssertNil(parsed["widget"])
        XCTAssertEqual(parsed["bar"]?["gap"]?.number, 4)
        XCTAssertEqual(parsed["clock"]?["format"]?.string, "HH:mm")
    }

    func testOutputTakesFirstNonEmptyLineAndReportsFailure() {
        let ok = CommandWidgets.output(ShellResult(stdout: "\n  87%  \nmore", stderr: "", status: 0))
        XCTAssertEqual(ok.text, "87%")
        XCTAssertNil(ok.error)
        let bad = CommandWidgets.output(ShellResult(stdout: "", stderr: "boom\nstack", status: 2))
        XCTAssertEqual(bad.error, "boom")
        let silent = CommandWidgets.output(ShellResult(stdout: "", stderr: "", status: 3))
        XCTAssertEqual(silent.error, "exited 3")
    }

    func testShellRunsAndCapturesBothStreams() async {
        let r = await runShell("echo hi; echo oops >&2; exit 4")
        XCTAssertEqual(r.stdout, "hi\n")
        XCTAssertEqual(r.stderr, "oops\n")
        XCTAssertEqual(r.status, 4)
    }

    func testShellTimeout() async {
        let r = await runShell("sleep 5", timeout: 0.3)
        XCTAssertNil(r.status)
        XCTAssertTrue(r.stderr.contains("timed out"))
    }
}
