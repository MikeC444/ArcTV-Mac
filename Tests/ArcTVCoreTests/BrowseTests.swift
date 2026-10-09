import XCTest
@testable import ArcTVCore

final class BrowseTests: XCTestCase {
    private func meta(_ id: String, rating: String?, year: String?) -> MetaPreview {
        MetaPreview(id: id, type: "movie", name: id, releaseInfo: year, imdbRating: rating)
    }

    func testSortsLikeTheWebApp() {
        let items = [meta("a", rating: "6.0", year: "2020"), meta("b", rating: "8.5", year: "2018"), meta("c", rating: nil, year: "2024")]
        XCTAssertEqual(BrowseSort.featured.apply(items).map(\.id), ["a", "b", "c"])
        XCTAssertEqual(BrowseSort.highestRated.apply(items).map(\.id), ["b", "a", "c"])
        XCTAssertEqual(BrowseSort.newest.apply(items).map(\.id), ["c", "a", "b"])
    }

    func testYearComesFromTheStartOfReleaseInfo() {
        XCTAssertEqual(meta("a", rating: nil, year: "2019-2024").year, 2019)
        XCTAssertNil(meta("a", rating: nil, year: "TBA").year)
        XCTAssertNil(meta("a", rating: nil, year: nil).year)
    }

    func testInterleaveAndDistinct() {
        let movies = [meta("m1", rating: nil, year: nil), meta("m2", rating: nil, year: nil), meta("dup", rating: nil, year: nil)]
        let shows = [meta("s1", rating: nil, year: nil), meta("dup", rating: nil, year: nil)]
        XCTAssertEqual(interleave(movies, shows).map(\.id), ["m1", "s1", "m2", "dup", "dup"])
        XCTAssertEqual(distinctByID(interleave(movies, shows)).map(\.id), ["m1", "s1", "m2", "dup"])
    }

    func testWatchlistDecodesAndBecomesPosterCards() throws {
        let json = """
        {"items":[{"providerId":"com.linvo.cinemeta","contentId":"tt0816692","contentType":"MOVIE","title":"Interstellar","posterUrl":"https://example.com/p.jpg","year":2014,"rating":8.7,"watched":false,"updatedAt":"2026-10-01T00:00:00.000Z"},
                  {"providerId":"p","contentId":"tt2","contentType":"TV_SHOW","title":"A Show","updatedAt":"2026-10-02T00:00:00.000Z"}]}
        """
        let items = try JSONDecoder().decode(WatchlistResponse.self, from: Data(json.utf8)).items
        XCTAssertEqual(items.count, 2)
        XCTAssertEqual(items[0].asPreview.type, "movie")
        XCTAssertEqual(items[0].asPreview.releaseInfo, "2014")
        XCTAssertEqual(items[1].asPreview.type, "series")
    }
}
