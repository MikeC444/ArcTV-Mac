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
        // No web link and no torrent hash: nothing to start. (A torrent can be started by the app's own engine, so it can be picked.)
        XCTAssertNil(last.match(in: [item("A", "Movie", hash: nil, url: nil)]))
        XCTAssertEqual(last.match(in: [item("A", "Movie", hash: "abc", url: nil)])?.id, "A#0")
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

final class ProfileTests: XCTestCase {
    func testPinsAreFourDigits() {
        XCTAssertTrue(Profile.isValidPin("0420"))
        XCTAssertFalse(Profile.isValidPin("420"))
        XCTAssertFalse(Profile.isValidPin("04200"))
        XCTAssertFalse(Profile.isValidPin("12a4"))
        XCTAssertFalse(Profile.isValidPin("١٢٣٤")) // not ASCII digits
    }

    func testOldAvatarIdsBecomeTheNearestPictureAndUnknownOnesTheFirst() {
        XCTAssertEqual(Avatars.resolve("fox"), "fox")
        XCTAssertEqual(Avatars.resolve("astro"), "astronaut")
        XCTAssertEqual(Avatars.resolve("bolt"), "robot")
        XCTAssertEqual(Avatars.resolve("nope"), "fox")
        XCTAssertEqual(Avatars.ids.count, 16)
    }

    func testAccountLevelCallsGoWithoutTheProfileHeader() {
        XCTAssertTrue(Profile.isAccountLevel("/user/plus"))
        XCTAssertTrue(Profile.isAccountLevel("/user/profiles/abc/verify-pin"))
        XCTAssertTrue(Profile.isAccountLevel("/user/trailer"))
        XCTAssertFalse(Profile.isAccountLevel("/user/watchlist"))
        XCTAssertFalse(Profile.isAccountLevel("/user/addons"))
    }

    func testAProfileDecodesFromTheBackendsAnswer() throws {
        let json = #"{"id":"p1","name":"Sam","avatar":"cat","kind":"kids","hasPin":true,"isDefault":false}"#
        let profile = try JSONDecoder().decode(Profile.self, from: Data(json.utf8))
        XCTAssertTrue(profile.isKids)
        XCTAssertTrue(profile.hasPin)
        XCTAssertEqual(profile.name, "Sam")
    }

    func testAnUpdateSendsNullToRemoveAPinAndNothingToLeaveItAlone() throws {
        func body(_ pin: String??) throws -> String {
            String(data: try JSONEncoder().encode(UpdateBody(name: "N", avatar: nil, kind: nil, pin: pin)), encoding: .utf8)!
        }
        XCTAssertFalse(try body(nil).contains("pin"))
        XCTAssertTrue(try body(.some(nil)).contains("\"pin\":null"))
        XCTAssertTrue(try body(.some("1234")).contains("\"pin\":\"1234\""))
    }
}

final class PlusAndStatsTests: XCTestCase {
    private var utc: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }

    private func iso(_ text: String) -> String { text }

    func testTheWelcomeShowsOnceEverAndTheInvitationComesBackAfterFiveDays() {
        XCTAssertTrue(PlusPopups.welcomeDue(seen: nil, shownThisLaunch: false))
        XCTAssertFalse(PlusPopups.welcomeDue(seen: PlusPopups.welcomeID, shownThisLaunch: false))
        XCTAssertFalse(PlusPopups.welcomeDue(seen: nil, shownThisLaunch: true))
        let now = Date(timeIntervalSince1970: 1_790_000_000)
        XCTAssertTrue(PlusPopups.invitationDue(never: false, snoozedUntil: nil, shownThisLaunch: false, now: now))
        let closed = now.addingTimeInterval(PlusPopups.snooze)
        XCTAssertFalse(PlusPopups.invitationDue(never: false, snoozedUntil: closed, shownThisLaunch: false, now: now.addingTimeInterval(4 * 24 * 3600)))
        XCTAssertTrue(PlusPopups.invitationDue(never: false, snoozedUntil: closed, shownThisLaunch: false, now: closed))
        XCTAssertFalse(PlusPopups.invitationDue(never: true, snoozedUntil: nil, shownThisLaunch: false, now: now))
        XCTAssertEqual(PlusPopups.snooze, 5 * 24 * 3600)
    }

    func testWhatCountsAsWatchedAndHowLongsAreWritten() {
        XCTAssertEqual(HistoryItem(contentId: "a", contentType: "MOVIE", positionMs: 10, durationMs: 100, completed: true, watchedAt: "").watchedMs, 100)
        XCTAssertEqual(HistoryItem(contentId: "a", contentType: "MOVIE", positionMs: 400, durationMs: 100, completed: false, watchedAt: "").watchedMs, 100)
        XCTAssertEqual(HistoryItem(contentId: "a", contentType: "MOVIE", positionMs: 40, durationMs: 0, completed: false, watchedAt: "").watchedMs, 40)
        XCTAssertEqual(WatchStats.duration(126 * 3_600_000), "126 hours")
        XCTAssertEqual(WatchStats.duration(65 * 60_000), "1 hour 5 minutes")
        XCTAssertEqual(WatchStats.duration(40 * 60_000), "40 minutes")
        XCTAssertEqual(WatchStats.duration(30_000), "under a minute")
        XCTAssertEqual(WatchStats.short(45 * 60_000), "45m")
        XCTAssertEqual(WatchStats.short(3 * 3_600_000), "3h")
        XCTAssertEqual(WatchStats.short(90 * 60_000), "1.5h")
        XCTAssertEqual(WatchStats.short(0), "")
        XCTAssertEqual(WatchStats.weekChange(last7: 118, prev7: 100)?.percent, 18)
        XCTAssertEqual(WatchStats.weekChange(last7: 70, prev7: 100)?.direction, "down")
        XCTAssertNil(WatchStats.weekChange(last7: 1, prev7: 0))
    }

    func testStatsCountEachTitleOnceByDayAndFindStreaksAndTheBusiestDay() {
        let hour: Int64 = 3_600_000
        // (an episode's length that is not a whole number of minutes, as real playback gives: a whole-minute length used as both the position and
        // the length is how an old hand-ticked episode looks, and those do not count)
        let episode = hour + 5_000
        // "Now" is Wednesday 2026-10-14 12:00 UTC.
        let now = ISODate.date(from: "2026-10-14T12:00:00.000Z")!
        let items = [
            HistoryItem(contentId: "m1", contentType: "MOVIE", positionMs: 2 * hour, durationMs: 2 * hour, completed: true, watchedAt: "2026-10-14T09:00:00.000Z"),
            HistoryItem(contentId: "s1e1", contentType: "TV_SHOW", seasonNumber: 1, episodeNumber: 1, positionMs: episode, durationMs: episode, completed: true, watchedAt: "2026-10-13T20:00:00.000Z"),
            HistoryItem(contentId: "s1e2", contentType: "TV_SHOW", seasonNumber: 1, episodeNumber: 2, positionMs: hour / 2, durationMs: hour, completed: false, watchedAt: "2026-10-12T20:00:00.000Z"),
            HistoryItem(contentId: "m2", contentType: "MOVIE", positionMs: hour / 2, durationMs: 2 * hour, completed: false, watchedAt: "2026-09-01T20:00:00.000Z")
        ]
        let stats = WatchStats.compute(items, now: now, calendar: utc)
        XCTAssertFalse(stats.isEmpty)
        XCTAssertEqual(stats.totalMs, 2 * hour + episode + hour / 2 + hour / 2)
        XCTAssertEqual(stats.last7DaysMs, 2 * hour + episode + hour / 2)
        XCTAssertEqual(stats.movieMs, 2 * hour + hour / 2)
        XCTAssertEqual(stats.showMs, episode + hour / 2)
        XCTAssertEqual(stats.moviesFinished, 1)
        XCTAssertEqual(stats.episodesWatched, 1)
        XCTAssertEqual(stats.showsWatched, 2) // two episodes are two history rows, each its own key
        XCTAssertEqual(stats.streakDays, 3) // 12th, 13th and 14th
        XCTAssertEqual(stats.longestStreakDays, 3)
        XCTAssertEqual(stats.activeDays, 4)
        XCTAssertEqual(stats.dailyMs.last, 2 * hour)
        XCTAssertEqual(stats.busiestWeekday, 2) // Wednesday (index 2, Monday first) holds the 2-hour movie
        XCTAssertTrue(WatchStats.compute([], now: now, calendar: utc).isEmpty)
    }

    func testHandTickedEpisodesDoNotCountButPlayedOnesDo() {
        let hour: Int64 = 3_600_000
        let now = ISODate.date(from: "2026-10-14T12:00:00.000Z")!
        let items = [
            // ticked by hand, said so by the account
            HistoryItem(contentId: "a", contentType: "TV_SHOW", seasonNumber: 1, episodeNumber: 1, positionMs: hour + 5_000, durationMs: hour + 5_000, completed: true, markedManually: true, watchedAt: "2026-10-14T09:00:00.000Z"),
            // an older tick: the listed runtime (45 whole minutes) as both position and length
            HistoryItem(contentId: "b", contentType: "TV_SHOW", seasonNumber: 1, episodeNumber: 2, positionMs: 45 * 60_000, durationMs: 45 * 60_000, completed: true, watchedAt: "2026-10-14T09:00:00.000Z"),
            // played
            HistoryItem(contentId: "c", contentType: "TV_SHOW", seasonNumber: 1, episodeNumber: 3, positionMs: 40 * 60_000 + 1_234, durationMs: 40 * 60_000 + 1_234, completed: true, watchedAt: "2026-10-14T10:00:00.000Z")
        ]
        let stats = WatchStats.compute(items, now: now, calendar: utc)
        XCTAssertEqual(stats.episodesWatched, 1)
        XCTAssertEqual(stats.totalMs, 40 * 60_000 + 1_234)
        XCTAssertTrue(WatchStats.compute(Array(items.prefix(2)), now: now, calendar: utc).isEmpty)
    }

    func testResetCountsOnlyWhatWasWatchedAfterIt() {
        let items = [
            HistoryItem(contentId: "old", contentType: "MOVIE", positionMs: 1, durationMs: 1, completed: true, watchedAt: "2026-10-10T09:00:00.000Z"),
            HistoryItem(contentId: "new", contentType: "MOVIE", positionMs: 1, durationMs: 1, completed: true, watchedAt: "2026-10-13T09:00:00.000Z")
        ]
        XCTAssertEqual(WatchStats.afterReset(items, resetAt: "2026-10-12T00:00:00.000Z").map(\.contentId), ["new"])
        XCTAssertEqual(WatchStats.afterReset(items, resetAt: nil).count, 2)
        XCTAssertEqual(WatchStats.afterReset(items, resetAt: "not a time").count, 2)
    }

    func testStreakNoteWeekdayLineAndTheMonthComparison() {
        XCTAssertEqual(WatchStats.streakNote(streak: 5, longest: 6), "best 6 \u{00B7} 1 day to match it")
        XCTAssertEqual(WatchStats.streakNote(streak: 2, longest: 6), "best 6 \u{00B7} 4 days to match it")
        XCTAssertEqual(WatchStats.streakNote(streak: 6, longest: 6), "your best")
        XCTAssertNil(WatchStats.streakNote(streak: 7, longest: 6))
        XCTAssertEqual(WatchStats.streakNote(streak: 0, longest: 3), "best 3")
        XCTAssertNil(WatchStats.streakNote(streak: 0, longest: 0))
        XCTAssertEqual(WatchStats.weekdayLine(0), "You watch most on Mondays.")
        XCTAssertNil(WatchStats.weekdayLine(nil))
        // the 30 days before the last 30
        let now = ISODate.date(from: "2026-10-14T12:00:00.000Z")!
        let items = [
            HistoryItem(contentId: "a", contentType: "MOVIE", positionMs: 3_600_000, durationMs: 3_600_000 + 7, completed: false, watchedAt: "2026-09-01T09:00:00.000Z"),
            HistoryItem(contentId: "b", contentType: "MOVIE", positionMs: 1_800_000, durationMs: 3_600_000 + 7, completed: false, watchedAt: "2026-10-10T09:00:00.000Z")
        ]
        let stats = WatchStats.compute(items, now: now, calendar: utc)
        XCTAssertEqual(stats.prev30DaysMs, 3_600_000)
        XCTAssertEqual(stats.last30DaysMs, 1_800_000)
    }

    func testMostWatchedAndTheRecapWords() {
        let hour: Int64 = 3_600_000
        let now = ISODate.date(from: "2026-10-14T12:00:00.000Z")!
        let items = [
            HistoryItem(contentId: "show", contentType: "TV_SHOW", seasonNumber: 1, episodeNumber: 1, title: "Ted Lasso", positionMs: hour + 1, durationMs: hour + 1, completed: true, watchedAt: "2026-10-14T09:00:00.000Z"),
            HistoryItem(contentId: "show", contentType: "TV_SHOW", seasonNumber: 1, episodeNumber: 2, title: "Ted Lasso", positionMs: hour + 1, durationMs: hour + 1, completed: true, watchedAt: "2026-10-13T09:00:00.000Z"),
            HistoryItem(contentId: "film", contentType: "MOVIE", title: "Heat", positionMs: 2 * hour + 1, durationMs: 2 * hour + 1, completed: true, watchedAt: "2026-10-14T10:00:00.000Z")
        ]
        let stats = WatchStats.compute(items, now: now, calendar: utc)
        XCTAssertEqual(stats.topShow?.title, "Ted Lasso")
        XCTAssertEqual(stats.topShow?.parts, 2)
        XCTAssertEqual(stats.topMovie?.title, "Heat")
        let recap = stats.recap
        XCTAssertEqual(recap?.heading, "My Arc TV recap")
        XCTAssertEqual(recap?.lines, ["Most watched show: Ted Lasso", "Most watched movie: Heat", "Longest streak: 2 days", "1 movie finished \u{00B7} 2 episodes watched"])
        XCTAssertNil(WatchStats.compute([], now: now, calendar: utc).recap)
    }

    func testMonthNamesSitAboveTheWeekWhereAMonthStarts() {
        let now = ISODate.date(from: "2026-10-14T12:00:00.000Z")!
        let cells = WatchStats.heatCells([Int64](repeating: 0, count: WatchStats.heatDays), now: now, calendar: utc)
        let labels = WatchStats.heatMonthLabels(cells, symbols: ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"])
        XCTAssertEqual(labels.count, (cells.count + 6) / 7)
        XCTAssertTrue(labels.contains("Oct"))
        XCTAssertTrue(labels.contains("Sep"))
        // a name is never followed straight away by another
        for pair in zip(labels, labels.dropFirst()) { XCTAssertFalse(!pair.0.isEmpty && !pair.1.isEmpty) }
    }

    func testTheActivityGridStartsOnAMondayAndLightsTheBusiestDays() {
        let now = ISODate.date(from: "2026-10-14T12:00:00.000Z")!
        var daily = [Int64](repeating: 0, count: WatchStats.heatDays)
        daily[WatchStats.heatDays - 1] = 100
        daily[WatchStats.heatDays - 2] = 25
        let cells = WatchStats.heatCells(daily, now: now, calendar: utc)
        let blanks = cells.prefix { $0.ms == nil }.count
        XCTAssertEqual(cells.count - blanks, WatchStats.heatDays)
        XCTAssertEqual(cells.last?.level, 4)
        XCTAssertEqual(cells[cells.count - 2].level, 1)
        // 2026-10-14 minus 90 days is 2026-07-16, a Thursday: three blank cells (Mon, Tue, Wed) come first.
        XCTAssertEqual(blanks, 3)
    }

    func testThePlansAndPerksAreNamed() {
        XCTAssertEqual(PlusPlan.all.map(\.id), ["monthly", "yearly", "lifetime"])
        XCTAssertEqual(PlusPlan.label(for: "yearly"), "Yearly")
        XCTAssertTrue(PlusCopy.perks.contains { $0.title == "Parental controls" && $0.soon })
    }
}
