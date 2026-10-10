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
        XCTAssertEqual(Format.runtime(minutes: 49), "49m")
        XCTAssertEqual(Format.runtime(minutes: 60), "1h 0m")
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

final class BrowseAndSearchTests: XCTestCase {
    func testRecentSearchesPutTheNewestFirstAndDoNotDouble() {
        var list: [String] = []
        for term in ["alien", "  sinners ", "ALIEN", "it"] { list = RecentSearches.adding(term, to: list) }
        XCTAssertEqual(list, ["it", "ALIEN", "sinners"])
        XCTAssertEqual(RecentSearches.adding("   ", to: list), list)
        var many: [String] = []
        for number in 1...12 { many = RecentSearches.adding("t\(number)", to: many) }
        XCTAssertEqual(many.count, RecentSearches.limit)
        XCTAssertEqual(many.first, "t12")
    }

    func testTheMovieAndShowGenreListsMatchCinemeta() {
        XCTAssertEqual(Genres.movies.count, 19)
        XCTAssertEqual(Genres.shows.count, 22)
        XCTAssertTrue(Genres.shows.starts(with: Genres.movies))
        XCTAssertFalse(Genres.movies.contains("Reality-TV"))
    }
}

final class HomeCacheTests: XCTestCase {
    func testTheLastRowsComeBackForTheSameAccountOnlyAndOnlyWhileFresh() {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("arctv-home-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        let cache = HomeCache(directory: directory)
        let items = (0..<40).map { MetaPreview(id: "t\($0)", type: "movie", name: "T\($0)") }
        let now = Date(timeIntervalSince1970: 1_790_000_000)
        cache.save([HomeSection(id: "a_base", title: "Popular", items: items)], userID: "user/1", now: now)
        let back = cache.load(userID: "user/1", now: now.addingTimeInterval(60))
        XCTAssertEqual(back?.first?.title, "Popular")
        XCTAssertEqual(back?.first?.items.count, HomeCache.itemsPerRow)
        XCTAssertNil(cache.load(userID: "someone-else", now: now))
        XCTAssertNil(cache.load(userID: "user/1", now: now.addingTimeInterval(HomeCache.maxAge + 1)))
    }
}

final class LastSourceTests: XCTestCase {
    private func item(_ addon: String, _ title: String, hash: String? = nil, url: String? = "https://x/y.mkv", index: Int = 0) -> SourceItem {
        SourceItem(addonName: addon, stream: AddonStream(url: url, ytId: nil, infoHash: hash, fileIdx: nil, title: title, name: nil, description: nil, behaviorHints: nil), index: index)
    }

    func testTheSameTorrentIsFoundEvenWhenTheListChanged() {
        let last = LastSource(addonName: "A", releaseTitle: "Old name", infoHash: "ABC")
        let list = [item("A", "Other", hash: "zzz", index: 0), item("B", "New name", hash: "abc", index: 1)]
        XCTAssertEqual(last.match(in: list)?.id, "B#1")
    }

    func testTheSameReleaseFromTheSameAddonBeatsTheSameNameElsewhere() {
        let last = LastSource(addonName: "A", releaseTitle: "Movie.1080p")
        let list = [item("B", "Movie.1080p", index: 0), item("A", "Movie.1080p", index: 1)]
        XCTAssertEqual(last.match(in: list)?.id, "A#1")
        XCTAssertEqual(LastSource(addonName: "Z", releaseTitle: "Movie.1080p").match(in: list)?.id, "B#0")
        XCTAssertNil(LastSource(addonName: "A", releaseTitle: "Nothing like it").match(in: list))
    }

    func testASourceThatCannotPlayIsNeverPicked() {
        let last = LastSource(addonName: "A", releaseTitle: "Movie", infoHash: "abc")
        XCTAssertNil(last.match(in: [item("A", "Movie", hash: "abc", url: nil)]))
    }

    func testTheStoreRemembersPerEpisodeAndPerAccount() {
        let suite = UserDefaults(suiteName: "arctv-test-\(UUID().uuidString)")!
        let mine = LastSourceStore(defaults: suite, userID: "u1")
        mine.set(LastSource(addonName: "A", releaseTitle: "E1"), titleID: "tt1", season: 1, episode: 1)
        XCTAssertEqual(mine.get(titleID: "tt1", season: 1, episode: 1)?.releaseTitle, "E1")
        XCTAssertNil(mine.get(titleID: "tt1", season: 1, episode: 2))
        XCTAssertNil(LastSourceStore(defaults: suite, userID: "u2").get(titleID: "tt1", season: 1, episode: 1))
    }
}
