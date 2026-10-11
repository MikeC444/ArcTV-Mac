import XCTest
@testable import ArcTVCore

final class SubtitleStyleTests: XCTestCase {
    func testASavedChoiceIsReadBackAndAnythingElseIsTheDefault() {
        XCTAssertEqual(SubtitleSize.from("large"), .large)
        XCTAssertEqual(SubtitleSize.from("extraLarge"), .extraLarge)
        XCTAssertEqual(SubtitleSize.from(nil), .medium)
        XCTAssertEqual(SubtitleSize.from("huge"), .medium)
        XCTAssertEqual(SubtitleColor.from("yellow"), .yellow)
        XCTAssertEqual(SubtitleColor.from(nil), .white)
        XCTAssertEqual(SubtitleColor.from("pink"), .white)
    }

    func testBiggerSizesMeanBiggerTextAndAShareOfThePicture() {
        let sizes = SubtitleSize.allCases
        for index in 1..<sizes.count {
            XCTAssertGreaterThan(sizes[index].mpvFontSize, sizes[index - 1].mpvFontSize)
            XCTAssertGreaterThan(sizes[index].fraction, sizes[index - 1].fraction)
        }
        XCTAssertEqual(SubtitleSize.medium.mpvFontSize, 55) // mpv's own default
    }

    func testColoursAreMpvHexValues() {
        XCTAssertEqual(SubtitleColor.white.hex, "#FFFFFF")
        XCTAssertEqual(SubtitleColor.yellow.hex, "#FFFF00")
        XCTAssertEqual(SubtitleColor.cyan.hex, "#00FFFF")
        XCTAssertEqual(SubtitleColor.green.hex, "#00FF00")
    }

    func testTheChoicesAreStoredPerMacInTheGivenDefaults() {
        let defaults = UserDefaults(suiteName: "SubtitleStyleTests-\(UUID().uuidString)")!
        XCTAssertEqual(SubtitleStyleStore.size(defaults), .medium)
        SubtitleStyleStore.setSize(.large, defaults)
        SubtitleStyleStore.setColor(.cyan, defaults)
        XCTAssertEqual(SubtitleStyleStore.size(defaults), .large)
        XCTAssertEqual(SubtitleStyleStore.color(defaults), .cyan)
    }
}
