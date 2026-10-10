import XCTest
@testable import ArcTVCore

final class AccountTests: XCTestCase {
    func testTimestampsAreUTCWithMilliseconds() {
        let text = ISODate.string(from: Date(timeIntervalSince1970: 1_790_000_000.5))
        XCTAssertTrue(text.hasSuffix("Z"))
        XCTAssertNotNil(text.range(of: #"^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\.\d{3}Z$"#, options: .regularExpression))
    }

    func testContinueWatchingDecodesAndMeasuresProgress() throws {
        let json = """
        {"items":[{"providerId":"com.linvo.cinemeta","contentId":"tt1","contentType":"TV_SHOW","seasonNumber":1,"episodeNumber":3,
          "episodeTitle":"Three","title":"Show","positionMs":600000,"durationMs":2400000,"lastWatchedAt":"2026-10-10T00:00:00.000Z"}]}
        """
        let items = try JSONDecoder().decode(ContinueResponse.self, from: Data(json.utf8)).items
        XCTAssertEqual(items[0].progress, 0.25, accuracy: 0.0001)
        XCTAssertEqual(items[0].positionSeconds, 600)
        XCTAssertEqual(items[0].episodeLabel, "S1 E3")
        XCTAssertEqual(items[0].asPreview.type, "series")
    }

    func testMyListEntryFromADetail() {
        let detail = MetaDetail(id: "tt0816692", type: "movie", name: "Interstellar", poster: "https://p", releaseInfo: "2014", imdbRating: "8.7")
        let item = detail.watchlistItem(watched: true)
        XCTAssertEqual(item.contentType, "MOVIE")
        XCTAssertEqual(item.year, 2014)
        XCTAssertEqual(item.rating, 8.7)
        XCTAssertEqual(item.watched, true)
        XCTAssertEqual(item.providerId, "com.linvo.cinemeta")
        let json = String(data: try! JSONEncoder().encode(item), encoding: .utf8)!
        XCTAssertTrue(json.contains("\"contentType\":\"MOVIE\""))
        XCTAssertFalse(json.contains("backdropUrl")) // left out when empty, as the backend allows
    }

    func testProgressReportCarriesTheEpisodePair() throws {
        let report = ProgressReport(providerId: "p", contentId: "tt1", contentType: "TV_SHOW", seasonNumber: 2, episodeNumber: 5, episodeTitle: nil,
                                    title: "T", posterUrl: nil, backdropUrl: nil, positionMs: 1000, durationMs: 5000, completed: false, watchedAt: ISODate.now())
        let json = String(data: try JSONEncoder().encode(report), encoding: .utf8)!
        XCTAssertTrue(json.contains("\"seasonNumber\":2"))
        XCTAssertTrue(json.contains("\"episodeNumber\":5"))
        XCTAssertTrue(json.contains("\"positionMs\":1000"))
    }
}
