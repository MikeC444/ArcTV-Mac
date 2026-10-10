import XCTest
@testable import ArcTVCore

final class HomeSectionsTests: XCTestCase {
    private func preview(_ id: String, background: String? = nil, poster: String? = nil) -> MetaPreview {
        MetaPreview(id: id, type: "movie", name: id, poster: poster, background: background)
    }

    // Reference values come from the web app's `homeVariety.ts`, run on the same inputs.
    func testSeedsMatchTheWebApp() {
        XCTAssertEqual(HomeVariety.hashSeed("abc"), 440_920_331)
        XCTAssertEqual(HomeVariety.hashSeed("user-1|2026-10-10"), 4_162_276_490)
        XCTAssertEqual(HomeVariety.hashSeed("é"), 1_812_687_940)
    }

    func testEachDayDrawsTheSamePageAsTheWebApp() {
        let expected = [("2026-10-10", 0, 1), ("2026-10-11", 0, 0), ("2026-10-12", 0, 0), ("2026-10-13", 1, 0), ("2026-10-14", 0, 1)]
        for (day, popular, new) in expected {
            XCTAssertEqual(HomeVariety.pickPage(seed: "user-1|\(day)", rowKey: "com.linvo.cinemeta_base", weights: [5, 3, 2]), popular, day)
            XCTAssertEqual(HomeVariety.pickPage(seed: "user-1|\(day)", rowKey: "com.linvo.cinemeta_new", weights: [6, 4]), new, day)
        }
    }

    func testTheGentleShuffleMatchesTheWebApp() {
        let order = HomeVariety.varyOrder(Array(0..<20), seed: "user-1|2026-10-10", rowKey: "com.linvo.cinemeta_base")
        XCTAssertEqual(order, [10, 3, 9, 15, 13, 16, 0, 4, 1, 6, 7, 19, 8, 2, 11, 14, 5, 18, 12, 17])
        XCTAssertEqual(order, HomeVariety.varyOrder(Array(0..<20), seed: "user-1|2026-10-10", rowKey: "com.linvo.cinemeta_base"))
    }

    func testOnlyTheCuratedGenresBecomeRowsInTheCuratedOrder() {
        let declared = ["Western", "horror", "Action", "Documentary", "Comedy", "Biography"]
        XCTAssertEqual(HomeVariety.homeGenres(declared: declared), ["Action", "Comedy", "horror", "Documentary"])
    }

    func testCinemetaShapedAddonsAreRecognised() {
        func catalog(_ id: String) -> CatalogDefinition { CatalogDefinition(type: "movie", id: id) }
        XCTAssertTrue(HomeSections.isRanked([catalog("top"), catalog("year"), catalog("imdbRating")]))
        XCTAssertFalse(HomeSections.isRanked([catalog("top"), catalog("year")]))
        XCTAssertTrue(HomeSections.isYear("2026"))
        XCTAssertFalse(HomeSections.isYear("Action"))
        XCTAssertFalse(HomeSections.isYear("1850"))
    }

    func testRowsFollowTheDefaultOrderUntilThePersonPlacesThem() {
        let rows = [
            HomeSection(id: "a_Horror", title: "Horror", items: [preview("1")]),
            HomeSection(id: "a_toprated", title: "Top rated", items: [preview("2")]),
            HomeSection(id: "a_base", title: "Popular", items: [preview("3")]),
            HomeSection(id: "a_Action", title: "Action", items: [preview("4")]),
            HomeSection(id: "a_new", title: "New", items: [preview("5")])
        ]
        XCTAssertEqual(rows.ordered(by: HomeRowPreferences()).map(\.id), ["a_base", "a_new", "a_toprated", "a_Action", "a_Horror"])
        // The person placed Horror and Action: New and Top rated, which they never placed, go above those; Popular (not a late arrival) goes below.
        let placed = HomeRowPreferences(order: ["a_Horror", "a_Action"])
        XCTAssertEqual(rows.ordered(by: placed).map(\.id), ["a_new", "a_toprated", "a_Horror", "a_Action", "a_base"])
    }

    func testATitleAppearsInOnlyOneRow() {
        let rows = [
            HomeSection(id: "x", title: "X", items: [preview("1"), preview("2")]),
            HomeSection(id: "y", title: "Y", items: [preview("2"), preview("3")]),
            HomeSection(id: "z", title: "Z", items: [preview("1"), preview("3")])
        ]
        let out = rows.deduped()
        XCTAssertEqual(out.map(\.id), ["x", "y"])
        XCTAssertEqual(out.map { $0.items.map(\.id) }, [["1", "2"], ["3"]])
    }

    func testTheBannerPrefersRealWideBackdrops() {
        var generator = SystemRandomNumberGenerator()
        let pool = [preview("wide1", background: "b1", poster: "p1"), preview("wide2", background: "b2", poster: "p2"), preview("posterOnly", background: "same", poster: "same"), preview("blank")]
        let two = HeroPool.pickTitles(enabled: pool, backup: [], size: 2, using: &generator)
        XCTAssertEqual(Set(two.map(\.id)), ["wide1", "wide2"])
        let four = HeroPool.pickTitles(enabled: pool, backup: [], size: 4, using: &generator)
        XCTAssertEqual(Set(four.map(\.id)), ["wide1", "wide2", "posterOnly", "blank"])
        let extra = HeroPool.pickTitles(enabled: [preview("a", background: "b", poster: "p")], backup: pool, size: 3, using: &generator)
        XCTAssertEqual(extra.count, 3)
        XCTAssertEqual(Set(extra.map(\.id)).count, 3)
    }
}

final class DetailExtrasTests: XCTestCase {
    func testRuntimesAndDatesReadTheWayTheWebAppWritesThem() {
        XCTAssertEqual(Format.runtime(minutes: 137), "2h 17m")
        XCTAssertEqual(Format.runtimeMinutes("142 min"), 142)
        XCTAssertEqual(Format.runtimeMinutes("2h 22min"), 142)
        XCTAssertNil(Format.runtimeMinutes(nil))
        XCTAssertEqual(Format.releaseDate("2024-03-05"), "Mar 5, 2024")
        XCTAssertEqual(Format.releaseDate("2024-03-05T00:00:00.000Z"), "Mar 5, 2024")
        XCTAssertNil(Format.releaseDate("soon"))
    }

    func testCastKeepsWhatTheAddonSentAndFillsInPhotosByName() {
        let addon = [CastMember(name: "Zoë Saldaña", role: nil, photoURL: nil), CastMember(name: "A B", role: "Hero", photoURL: "keep.jpg")]
        let tmdb = [TmdbCast(name: "Zoe Saldana", character: "Neytiri", photo: "zoe.jpg"), TmdbCast(name: "A B", character: "Other", photo: "other.jpg")]
        let merged = CastMerge.merge(addon, tmdb)
        XCTAssertEqual(merged[0], CastMember(name: "Zoë Saldaña", role: "Neytiri", photoURL: "zoe.jpg"))
        XCTAssertEqual(merged[1], CastMember(name: "A B", role: "Hero", photoURL: "keep.jpg"))
        XCTAssertEqual(CastMerge.merge([], tmdb).map(\.name), ["Zoe Saldana", "A B"])
        XCTAssertEqual(CastMerge.merge(addon, []), addon)
    }

    func testCinemetaCastWithPhotosComesFirstThenTheRemainingNames() throws {
        let json = #"{"id":"tt1","type":"movie","name":"One","cast":["A","B","C"],"app_extras":{"cast":[{"name":"B","character":"Bee","photo":"b.jpg"}]}}"#
        let meta = try JSONDecoder().decode(MetaDetail.self, from: Data(json.utf8))
        XCTAssertEqual(meta.castMembers, [CastMember(name: "B", role: "Bee", photoURL: "b.jpg"), CastMember(name: "A"), CastMember(name: "C")])
    }
}

final class HTMLDecodeTests: XCTestCase {
    func testEntitiesLeftInNamesAreTurnedBackIntoCharacters() {
        XCTAssertEqual("Jack O&apos;Connell".htmlDecoded, "Jack O'Connell")
        XCTAssertEqual("Tom &amp; Jerry".htmlDecoded, "Tom & Jerry")
        XCTAssertEqual("It&#39;s &#x41;".htmlDecoded, "It's A")
        XCTAssertEqual("&amp;apos;".htmlDecoded, "&apos;")
        XCTAssertEqual("plain".htmlDecoded, "plain")
    }
}
