import XCTest
@testable import ArcTVCore

final class RecommendExtrasTests: XCTestCase {
    // MARK: seeded generator and composition

    func testSeededRandomMatchesTheWebAndFireTVGenerator() {
        // Reference values produced by the web app's mulberry32 for the same seeds.
        let one = SeededRandom(seed: 1)
        XCTAssertEqual(one.next(), 0.6270739406, accuracy: 1e-9)
        XCTAssertEqual(one.next(), 0.0027357212, accuracy: 1e-9)
        XCTAssertEqual(one.next(), 0.5274470400, accuracy: 1e-9)
        let answer = SeededRandom(seed: 42)
        XCTAssertEqual(answer.next(), 0.6011037519, accuracy: 1e-9)
        XCTAssertEqual(answer.next(), 0.4482905590, accuracy: 1e-9)
        let negative = SeededRandom(seed: -7)
        XCTAssertEqual(negative.next(), 0.4330673341, accuracy: 1e-9)
        XCTAssertEqual(negative.next(), 0.3253957673, accuracy: 1e-9)
    }

    private struct Pick: ComposePick, Equatable {
        var id: String
        var score: Double
        var genre: String?
    }

    private func picks() -> [Pick] {
        var out: [Pick] = []
        for i in 0..<12 { out.append(Pick(id: "h\(i)", score: 0.9 - Double(i) * 0.01, genre: "horror")) }
        for i in 0..<12 { out.append(Pick(id: "c\(i)", score: 0.8 - Double(i) * 0.01, genre: "comedy")) }
        return out.sorted { $0.score > $1.score }
    }

    func testComposeKeepsTheAnchorsAndFollowsTheTasteSplit() {
        let row = compose(picks(), limit: 12, shares: ["horror": 0.75, "comedy": 0.25])
        XCTAssertEqual(row.count, 12)
        XCTAssertEqual(Array(row.prefix(5)).map(\.id), ["h0", "h1", "h2", "h3", "h4"])
        let horrorCount = row.filter { $0.genre == "horror" }.count
        XCTAssertEqual(horrorCount, 9) // three quarters of twelve
        XCTAssertEqual(row.map(\.id).count, Set(row.map(\.id)).count)
    }

    func testComposeWithASeedIsRepeatableAndRotatesAwayFromWhatWasShown() {
        let shares = ["horror": 0.5, "comedy": 0.5]
        let first = compose(picks(), limit: 12, shares: shares, seed: 7)
        XCTAssertEqual(first.map(\.id), compose(picks(), limit: 12, shares: shares, seed: 7).map(\.id))
        let shown = Set(first.map(\.id))
        var overlaps: [Int] = []
        for seed in 1...20 {
            let next = compose(picks(), limit: 12, shares: shares, previous: shown, seed: seed)
            overlaps.append(next.filter { shown.contains($0.id) }.count)
        }
        // The five anchors always repeat; the rest should mostly change.
        XCTAssertTrue(overlaps.allSatisfy { $0 >= 5 })
        XCTAssertLessThan(Double(overlaps.reduce(0, +)) / Double(overlaps.count), 10)
    }

    func testComposeReturnsEverythingWhenThereIsNothingToChooseBetween() {
        let few = Array(picks().prefix(4))
        XCTAssertEqual(compose(few, limit: 20).map(\.id), few.map(\.id))
    }

    func testTasteSharesSumToOneAndPrimaryGenreBreaksTiesAlphabetically() {
        var prefs = TastePreferences()
        prefs.genre = ["drama": 2, "crime": 2, "horror": 1]
        XCTAssertEqual(primaryGenre(["horror", "drama", "crime"], prefs), "crime")
        XCTAssertNil(primaryGenre(["western"], prefs))
        let signalled = [Interaction(id: "a", title: "a", kind: .like, weight: 5), Interaction(id: "b", title: "b", kind: .watchlist, weight: 1)]
        let shares = tasteShares(signalled, ownFeatures: ["a": Features(genres: ["horror"]), "b": Features(genres: ["drama"])], prefs)
        XCTAssertEqual(shares.values.reduce(0, +), 1, accuracy: 1e-9)
        XCTAssertEqual(shares["drama"] ?? 0, 1.0 / 6.0, accuracy: 1e-9)
    }

    // MARK: summary

    private func list(_ id: String, watched: Bool) -> WatchlistItem {
        WatchlistItem(providerId: "p", contentId: id, contentType: "MOVIE", title: id, watched: watched, updatedAt: "2026-01-01T00:00:00.000Z")
    }

    func testSummaryCountsLikesDislikesFinishedAndSavedWithTheirPoints() {
        let s = summarizeRecommendations(ratings: ["a": .like, "b": .like, "c": .dislike],
                                         list: [list("w", watched: true), list("l", watched: false), list("l2", watched: false)])
        XCTAssertEqual([s.likes, s.dislikes, s.finished, s.saved], [2, 1, 1, 2])
        XCTAssertEqual(s.likePoints, 10)
        XCTAssertEqual(s.dislikePoints, -5)
        XCTAssertEqual(s.listPoints, 4)
        XCTAssertEqual(s.signals, 6)
    }

    func testARatedTitleCountsOnceByItsRatingEvenWhenItIsAlsoInMyList() {
        let s = summarizeRecommendations(ratings: ["a": .like], list: [list("a", watched: true), list("b", watched: false)])
        XCTAssertEqual([s.likes, s.finished, s.saved], [1, 0, 1])
    }

    func testPicksNeedAtLeastThreeSignalsAndOnePositiveOne() {
        XCTAssertFalse(summarizeRecommendations(ratings: [:], list: []).ready)
        XCTAssertFalse(summarizeRecommendations(ratings: ["a": .like, "b": .dislike], list: []).ready)
        XCTAssertFalse(summarizeRecommendations(ratings: ["a": .dislike, "b": .dislike, "c": .dislike], list: []).ready)
        XCTAssertTrue(summarizeRecommendations(ratings: ["a": .like, "b": .dislike, "c": .dislike], list: []).ready)
    }

    func testSaysWhenMoreTitlesAreRatedThanTheEngineReads() {
        var many: [String: Rating] = [:]
        for i in 1...61 { many["t\(i)"] = .like }
        XCTAssertTrue(summarizeRecommendations(ratings: many, list: []).overLimit)
        many.removeValue(forKey: "t61")
        XCTAssertFalse(summarizeRecommendations(ratings: many, list: []).overLimit)
    }

    func testPointsAreWrittenPlainly() {
        XCTAssertEqual(pointsLabel(20), "+20 points")
        XCTAssertEqual(pointsLabel(-15), "−15 points")
        XCTAssertEqual(pointsLabel(0), "0 points")
        XCTAssertEqual(pointsLabel(1), "+1 point")
    }

    // MARK: removed picks stay out for 5 days

    func testARemovalHidesTheTitleFor5DaysNotAMomentLonger() {
        let now = Date(timeIntervalSince1970: 1_000_000_000)
        let day: TimeInterval = 86_400
        let removed = ["tt1": now.addingTimeInterval(-5 * day + 60)]
        XCTAssertEqual(PickedDismissals.active(removed, now: now), ["tt1"])
        XCTAssertEqual(PickedDismissals.active(removed, now: now.addingTimeInterval(120)), [])
    }

    func testMergingKeepsTheNewestTimeAndDropsOldOnes() {
        let now = Date(timeIntervalSince1970: 1_790_000_000)
        let day: TimeInterval = 86_400
        let local = ["a": now.addingTimeInterval(-3 * day), "old": now.addingTimeInterval(-6 * day)]
        let server = [
            PickedDismissal(profileId: "main", contentId: "a", dismissedAt: ISODate.string(from: now.addingTimeInterval(-1 * day))),
            PickedDismissal(profileId: "main", contentId: "b", dismissedAt: ISODate.string(from: now.addingTimeInterval(-2 * day))),
            PickedDismissal(profileId: "main", contentId: "gone", dismissedAt: ISODate.string(from: now.addingTimeInterval(-9 * day)))
        ]
        let merged = PickedDismissals.merged(local, with: server, now: now)
        XCTAssertEqual(Set(merged.keys), ["a", "b"])
        XCTAssertEqual(merged["a"]!.timeIntervalSince1970, now.addingTimeInterval(-1 * day).timeIntervalSince1970, accuracy: 0.001)
    }

    // MARK: the Home row

    private func preview(_ id: String) -> MetaPreview { MetaPreview(id: id, type: "movie", name: id) }

    func testThePersonalRowDropsRatedAndRemovedTitlesAtOnceAndKeepsReasons() {
        let result = EngineResult.personal([
            Picked(id: "a", score: 0.9, reason: "Because you liked x"), Picked(id: "b", score: 0.8, reason: "Because you liked y"),
            Picked(id: "c", score: 0.7, reason: nil), Picked(id: "missing", score: 0.6, reason: nil)
        ])
        let row = pickedRow(result: result, pool: ["a", "b", "c"].map(preview), hiddenIDs: ["b"], dismissed: ["c"])
        XCTAssertEqual(row?.entries.map(\.id), ["a"])
        XCTAssertEqual(row?.entries.first?.reason, "Because you liked x")
        XCTAssertEqual(row?.title, RecommendConfig.pickedRowTitle)
        XCTAssertNil(pickedRow(result: result, pool: ["a"].map(preview), hiddenIDs: ["a"], dismissed: []))
        XCTAssertNil(pickedRow(result: nil, pool: [], hiddenIDs: [], dismissed: []))
    }

    func testThePopularRowIsLabelledAndNeverGivesReasons() {
        let result = EngineResult.popular([Picked(id: "a", score: nil, reason: "should not show")])
        let row = pickedRow(result: result, pool: [preview("a")], hiddenIDs: [], dismissed: [])
        XCTAssertEqual(row?.title, RecommendConfig.popularRowTitle)
        XCTAssertEqual(row?.personal, false)
        XCTAssertNil(row?.entries.first?.reason)
    }

    func testWhatIsNeverPicked() {
        let items = [list("done", watched: true), list("saved", watched: false)]
        let out = excludedFromPicks(list: items, ratedIDs: ["liked"], continueIDs: ["playing"], dismissed: ["removed"])
        XCTAssertEqual(out, ["done", "liked", "playing", "removed"])
    }

    // MARK: feature lookups and cache

    func testTheLoaderReadsTheCacheFirstAndLooksUpAtMostTheLimitOfTheRest() async {
        let cache = FeatureCache(file: nil)
        await cache.put(["known": Features(genres: ["drama"])])
        let asked = AskedIDs()
        let loader = FeatureLoading.loader(cache: cache, concurrency: 2) { ref in
            asked.add(ref.id)
            return ref.id == "bad" ? nil : Features(genres: ["comedy"], directors: ["d"], cast: [])
        }
        let refs = ["known", "n1", "n2", "bad", "n3", "n1"].map { TitleRef(id: $0) }
        let out = await loader(refs, 3)
        XCTAssertEqual(out["known"]?.genres, ["drama"])
        XCTAssertEqual(asked.ids.count, 3) // capped by the limit, "known" and the repeat not looked up
        XCTAssertFalse(asked.ids.contains("known"))
        XCTAssertNil(out["bad"]) // a failed lookup is just left out
        let cached = await cache.get("n1")
        XCTAssertEqual(cached?.directors, ["d"])
    }

    func testTheCacheForgetsOldEntriesAndKeepsWithinItsSize() async {
        let cache = FeatureCache(file: nil)
        let long = Date(timeIntervalSince1970: 1_000_000)
        await cache.put(["old": Features(genres: ["a"])], now: long)
        let stale = await cache.get("old", now: long.addingTimeInterval(RecommendConfig.featureCacheTTL + 1))
        XCTAssertNil(stale)
        let fresh = await cache.get("old", now: long.addingTimeInterval(60))
        XCTAssertNotNil(fresh)
    }

    func testTheCacheSurvivesBeingReopened() async {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("arctv-features-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: file) }
        let first = FeatureCache(file: file)
        await first.put(["x": Features(genres: ["drama"], directors: ["d"], cast: ["c"])])
        let second = FeatureCache(file: file)
        let found = await second.get("x")
        XCTAssertEqual(found, Features(genres: ["drama"], directors: ["d"], cast: ["c"]))
    }

    // MARK: account answers

    func testFeedbackAndPlusAnswersDecode() throws {
        let json = """
        {"items":[{"profileId":"main","providerId":"com.linvo.cinemeta","contentId":"tt1","contentType":"MOVIE","title":"One","feedback":"like",
          "updatedAt":"2026-10-10T00:00:00.000Z","deletedAt":null}]}
        """
        let items = try JSONDecoder().decode(FeedbackResponse.self, from: Data(json.utf8)).items
        XCTAssertEqual(items.first?.rating, .like)
        let plus = try JSONDecoder().decode(PlusStatus.self, from: Data(#"{"active":true,"plan":"early_access","paywall":false}"#.utf8))
        XCTAssertTrue(plus.active)
        XCTAssertEqual(plus.trialDays, 0)
        let rate = FeedbackItem(title: MetaPreview(id: "tt2", type: "series", name: "Two"), rating: .dislike)
        XCTAssertEqual(rate.contentType, "TV_SHOW")
        XCTAssertEqual(rate.feedback, "dislike")
    }

    func testMetaFeaturesComeFromGenresDirectorsAndCast() {
        let meta = MetaDetail(id: "tt1", type: "movie", name: "One", genres: ["Drama", "Crime"], director: ["Jane  Doe"], cast: ["A", "B"])
        XCTAssertEqual(featuresFromMeta(meta), Features(genres: ["drama", "crime"], directors: ["jane doe"], cast: ["a", "b"]))
    }
}

private final class AskedIDs: @unchecked Sendable {
    private let lock = NSLock()
    private var all: [String] = []
    var ids: [String] { lock.lock(); defer { lock.unlock() }; return all }
    func add(_ id: String) { lock.lock(); all.append(id); lock.unlock() }
}

final class MyListSortTests: XCTestCase {
    private func item(_ title: String, rating: Double?, year: Int?) -> WatchlistItem {
        WatchlistItem(providerId: "p", contentId: title, contentType: "MOVIE", title: title, year: year, rating: rating, updatedAt: "2026-01-01T00:00:00.000Z")
    }

    func testListSortsOrderTitlesTheWayTheirNamesSay() {
        let items = [item("beta", rating: 7, year: 2020), item("Alpha", rating: 9, year: 1999), item("gamma", rating: nil, year: 2024)]
        XCTAssertEqual(ListSort.recent.apply(items).map(\.title), ["beta", "Alpha", "gamma"])
        XCTAssertEqual(ListSort.title.apply(items).map(\.title), ["Alpha", "beta", "gamma"])
        XCTAssertEqual(ListSort.highestRated.apply(items).map(\.title), ["Alpha", "beta", "gamma"])
        XCTAssertEqual(ListSort.newest.apply(items).map(\.title), ["gamma", "beta", "Alpha"])
    }
}
