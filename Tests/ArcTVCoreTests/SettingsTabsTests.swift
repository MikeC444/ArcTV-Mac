import XCTest
@testable import ArcTVCore

final class SettingsTabsTests: XCTestCase {
    func testMoveRow() {
        let order = ["a", "b", "c"]
        XCTAssertEqual(HomeRowOrder.move(order, id: "b", delta: -1), ["b", "a", "c"])
        XCTAssertEqual(HomeRowOrder.move(order, id: "b", delta: 1), ["a", "c", "b"])
        XCTAssertEqual(HomeRowOrder.move(order, id: "a", delta: -1), order)
        XCTAssertEqual(HomeRowOrder.move(order, id: "c", delta: 1), order)
        XCTAssertEqual(HomeRowOrder.move(order, id: "x", delta: 1), order)
    }

    func testLanguageLists() {
        XCTAssertEqual(LanguageChoices.subtitles().count, 16)
        XCTAssertNil(LanguageChoices.subtitles()[0].code)
        XCTAssertEqual(LanguageChoices.audio()[0].name, "Automatic")
        XCTAssertEqual(LanguageChoices.all.first?.code, "en")
    }

    func testVersionCompare() {
        XCTAssertTrue(UpdateCheck.isNewer("0.1.3", than: "0.1.2"))
        XCTAssertTrue(UpdateCheck.isNewer("v0.2.0", than: "0.1.9"))
        XCTAssertTrue(UpdateCheck.isNewer("1.0", than: "0.9.9"))
        XCTAssertFalse(UpdateCheck.isNewer("0.1.2", than: "0.1.2"))
        XCTAssertFalse(UpdateCheck.isNewer("0.1.2", than: "0.1.10"))
        XCTAssertFalse(UpdateCheck.isNewer("1.0.0", than: "1.0"))
    }

    func testParseRelease() throws {
        let json = """
        {"tag_name":"v0.2.0","body":"- Faster Home\\n- New look\\n","html_url":"https://github.com/x/y/releases/tag/v0.2.0",
         "assets":[{"name":"ArcTV.dmg","browser_download_url":"https://github.com/x/y/releases/download/v0.2.0/ArcTV.dmg"}]}
        """
        let data = Data(json.utf8)
        let info = try UpdateCheck.parse(data)
        XCTAssertEqual(info.version, "0.2.0")
        XCTAssertEqual(info.notes, "- Faster Home\n- New look")
        XCTAssertEqual(info.downloadURL?.lastPathComponent, "ArcTV.dmg")
        XCTAssertEqual(try UpdateCheck.result(statusCode: 200, data: data, current: "0.1.0"), .available(info))
        XCTAssertEqual(try UpdateCheck.result(statusCode: 200, data: data, current: "0.2.0"), .upToDate(latest: "0.2.0"))
        XCTAssertEqual(try UpdateCheck.result(statusCode: 404, data: Data(), current: "0.1.0"), .upToDate(latest: nil))
        XCTAssertThrowsError(try UpdateCheck.result(statusCode: 500, data: Data(), current: "0.1.0"))
    }
}
