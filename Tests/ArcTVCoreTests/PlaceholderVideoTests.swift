import XCTest
@testable import ArcTVCore

final class PlaceholderVideoTests: XCTestCase {
    func testAFewSecondsForALongTitleIsAPlaceholder() {
        XCTAssertTrue(PlaceholderVideo.isPlaceholder(durationSeconds: 9, runtimeMinutes: 47))
        XCTAssertTrue(PlaceholderVideo.isPlaceholder(durationSeconds: 90, runtimeMinutes: 120))
    }

    func testARealFileIsNot() {
        XCTAssertFalse(PlaceholderVideo.isPlaceholder(durationSeconds: 47 * 60, runtimeMinutes: 47))
        XCTAssertFalse(PlaceholderVideo.isPlaceholder(durationSeconds: 40 * 60, runtimeMinutes: 47))
    }

    func testNothingIsAssumedWithoutARuntimeOrForAShortTitleOrBeforeTheLengthIsKnown() {
        XCTAssertFalse(PlaceholderVideo.isPlaceholder(durationSeconds: 9, runtimeMinutes: nil))
        XCTAssertFalse(PlaceholderVideo.isPlaceholder(durationSeconds: 9, runtimeMinutes: 8))
        XCTAssertFalse(PlaceholderVideo.isPlaceholder(durationSeconds: 0, runtimeMinutes: 47))
        XCTAssertFalse(PlaceholderVideo.isPlaceholder(durationSeconds: .nan, runtimeMinutes: 47))
        XCTAssertFalse(PlaceholderVideo.isPlaceholder(durationSeconds: .infinity, runtimeMinutes: 47))
    }

    func testItMustBeBothUnderTwoMinutesAndUnderATenthOfTheRuntime() {
        XCTAssertFalse(PlaceholderVideo.isPlaceholder(durationSeconds: 130, runtimeMinutes: 600))
        XCTAssertFalse(PlaceholderVideo.isPlaceholder(durationSeconds: 70, runtimeMinutes: 11))
        XCTAssertTrue(PlaceholderVideo.isPlaceholder(durationSeconds: 60, runtimeMinutes: 11))
    }
}
