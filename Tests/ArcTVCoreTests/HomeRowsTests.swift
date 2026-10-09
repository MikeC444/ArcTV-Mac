import XCTest
@testable import ArcTVCore

final class HomeRowsTests: XCTestCase {
    func testDefaultRowsAreCinemetasPopularNewAndTopRated() {
        let rows = HomeRows.defaultRows(year: 2026)
        XCTAssertEqual(rows.map(\.id), ["popular-movie", "popular-series", "new-movie", "toprated-movie", "toprated-series"])
        let new = rows.first { $0.id == "new-movie" }
        XCTAssertEqual(new?.catalogId, "year")
        XCTAssertEqual(new?.extra, ["genre": "2026"])
        XCTAssertEqual(rows.first { $0.id == "toprated-series" }?.catalogId, "imdbRating")
    }

    func testRowIdsAreUnique() {
        let ids = HomeRows.defaultRows(year: 2026).map(\.id)
        XCTAssertEqual(Set(ids).count, ids.count)
    }
}
