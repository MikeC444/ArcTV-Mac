import XCTest
@testable import ArcTVCore

/// Ported from the Fire TV app's `RecommendTest`: the same fixtures and the same expectations.
final class RecommendTests: XCTestCase {
    private func f(_ genres: [String], _ directors: [String] = [], _ cast: [String] = []) -> Features {
        Features(genres: genres, directors: directors, cast: cast)
    }

    private lazy var meta: [String: Features] = [
        "heist1": f(["crime", "thriller"], ["nolan"], ["a", "b"]),
        "space1": f(["sci-fi", "adventure"], ["villeneuve"], ["c", "d"]),
        "rom1": f(["romance", "comedy"], ["ephron"], ["e", "f"]),
        "heist2": f(["crime", "thriller"], ["nolan"], ["a", "g"]),
        "heist3": f(["crime", "action"], ["mann"], ["h"]),
        "space2": f(["sci-fi", "drama"], ["villeneuve"], ["c", "i"]),
        "space3": f(["sci-fi", "adventure"], ["scott"], ["j"]),
        "rom2": f(["romance", "drama"], ["ephron"], ["e", "k"]),
        "rom3": f(["romance", "comedy"], ["curtis"], ["l"]),
        "nometa": f([])
    ]
    private var pool: [Candidate] {
        ["heist2", "heist3", "space2", "space3", "rom2", "rom3", "nometa"].map { Candidate(id: $0, title: $0, genres: meta[$0]!.genres, rating: 7.0) }
    }
    private func loader(_ source: [String: Features]) -> FeatureLoader {
        { refs, _ in
            var out: [String: Features] = [:]
            for ref in refs { if let found = source[ref.id] { out[ref.id] = found } }
            return out
        }
    }

    private func input(_ id: String, _ rating: Rating? = nil, completed: Bool = false, inWatchlist: Bool = false) -> InteractionInput {
        InteractionInput(id: id, title: id, rating: rating, completed: completed, inWatchlist: inWatchlist)
    }

    private func run(_ inputs: [InteractionInput], exclude: Set<String> = [], candidates: [Candidate]? = nil, load: FeatureLoader? = nil) async -> EngineResult {
        await recommend(EngineInput(interactions: collectInteractions(inputs), excludeIDs: exclude, pool: candidates ?? pool, interactionRefs: [:],
                                    loadFeatures: load ?? loader(meta)))
    }

    private func ids(_ result: EngineResult) -> [String] { result.items.map(\.id) }

    // MARK: signals

    func testUsesTheConfiguredWeightsStrongestSignalPerTitle() {
        XCTAssertEqual(interactionOf(input("x", .like))?.weight, RecommendConfig.weightLike)
        XCTAssertEqual(interactionOf(input("x", completed: true))?.weight, RecommendConfig.weightCompleted)
        XCTAssertEqual(interactionOf(input("x", inWatchlist: true))?.weight, RecommendConfig.weightWatchlist)
        XCTAssertEqual(interactionOf(input("x", completed: true, inWatchlist: true))?.kind, .completed)
        XCTAssertNil(interactionOf(input("x")))
    }

    func testExplicitFeedbackOverridesFinishingAndSaving() {
        let i = interactionOf(input("x", .dislike, completed: true, inWatchlist: true))
        XCTAssertEqual(i?.kind, .dislike)
        XCTAssertEqual(i?.weight, -5)
    }

    func testRepeatedFactsCannotInflateASignal() {
        let once = collectInteractions([input("heist1", completed: true)])
        let many = collectInteractions(Array(repeating: input("heist1", completed: true), count: 10))
        XCTAssertEqual(once, many)
    }

    // MARK: preferences and score

    func testSplitsATitlesWeightEquallyAmongItsUniqueFeaturesPerCategory() {
        let prefs = buildPreferences(collectInteractions([input("heist1", .like)]), featuresByID: ["heist1": meta["heist1"]!])
        XCTAssertEqual(prefs.genre["crime"]!, 2.5, accuracy: 1e-9)
        XCTAssertEqual(prefs.director["nolan"]!, 5.0, accuracy: 1e-9)
        XCTAssertEqual(prefs.cast["a"]!, 2.5, accuracy: 1e-9)
    }

    func testALongCastListDoesNotOutweighAShortOne() {
        let longCast = f(["drama"], [], ["a", "b", "c", "d", "e", "f", "g", "h", "i", "j"])
        let prefs = buildPreferences(collectInteractions([input("L", .like)]), featuresByID: ["L": longCast])
        XCTAssertEqual(prefs.cast.values.reduce(0, +), 5.0, accuracy: 1e-9)
    }

    func testCosineKeepsNegativePreferencesNegative() {
        let prefs = buildPreferences(collectInteractions([input("heist1", .dislike)]), featuresByID: ["heist1": meta["heist1"]!])
        XCTAssertLessThan(scoreCandidate(meta["heist2"], prefs)!.score, 0)
        XCTAssertEqual(cosine(["x": 1], ["x": -2])!, -1.0, accuracy: 1e-9)
    }

    func testCombinesCategoriesWithTheConfiguredWeightsAndRenormalisesWhenOneIsMissing() {
        let prefs = buildPreferences(collectInteractions([input("heist1", .like)]), featuresByID: ["heist1": meta["heist1"]!])
        let full = scoreCandidate(meta["heist2"], prefs)!
        let expected = (TasteCategory.genre.weight * full.categories[.genre]! + TasteCategory.director.weight * full.categories[.director]!
            + TasteCategory.cast.weight * full.categories[.cast]!)
            / (RecommendConfig.categoryWeightGenre + RecommendConfig.categoryWeightDirector + RecommendConfig.categoryWeightCast)
        XCTAssertEqual(full.score, expected, accuracy: 1e-9)
        let genreOnly = scoreCandidate(f(["crime", "thriller"]), prefs)!
        XCTAssertEqual(Array(genreOnly.categories.keys), [.genre])
        XCTAssertEqual(genreOnly.score, genreOnly.categories[.genre]!, accuracy: 1e-9)
    }

    func testHandlesMissingMetadataAndEmptyPreferenceVectors() {
        let prefs = buildPreferences(collectInteractions([input("heist1", .like)]), featuresByID: ["heist1": meta["heist1"]!])
        XCTAssertNil(scoreCandidate(nil, prefs))
        XCTAssertNil(scoreCandidate(f([]), prefs))
        let empty = buildPreferences(collectInteractions([input("nometa", .like)]), featuresByID: ["nometa": meta["nometa"]!])
        XCTAssertNil(scoreCandidate(meta["heist2"], empty))
        XCTAssertEqual(Array(scoreCandidate(f([], ["nolan"]), prefs)!.categories.keys), [.director])
    }

    func testNormalisesNames() {
        let features = featuresFromNames(genres: ["Sci-Fi", " sci-fi "], directors: ["Denis  Villeneuve"], cast: ["Zendaya", "Zendaya", "Timothée Chalamet"])
        XCTAssertEqual(features, Features(genres: ["sci-fi"], directors: ["denis villeneuve"], cast: ["zendaya", "timothée chalamet"]))
        XCTAssertEqual(featuresFromNames(genres: [], directors: [], cast: []), Features())
        XCTAssertEqual(featuresFromNames(genres: [], directors: ["A. One, B. Two"], cast: []).directors, ["a. one", "b. two"])
    }

    // MARK: recommend()

    private var sciFiFan3: [InteractionInput] { [input("space1", .like), input("space2", .like), input("heist1", inWatchlist: true)] }
    private var romFan: [InteractionInput] { [input("rom1", .like), input("rom2", .like), input("heist1", inWatchlist: true)] }

    func testRanksTheSameCatalogueDifferentlyForDifferentProfiles() async {
        let a = await run(sciFiFan3, exclude: ["space2"])
        let b = await run(romFan, exclude: ["rom2"])
        XCTAssertTrue(a.isPersonal)
        XCTAssertTrue(b.isPersonal)
        XCTAssertEqual(ids(a).first, "space3")
        XCTAssertEqual(ids(b).first, "rom3")
        XCTAssertNotEqual(ids(a), ids(b))
    }

    func testIsDeterministic() async {
        let first = await run(sciFiFan3, exclude: ["space2"])
        let second = await run(sciFiFan3, exclude: ["space2"])
        XCTAssertEqual(ids(first), ids(second))
    }

    func testNeverReturnsExcludedTitlesButStillOffersWatchlistedOnes() async {
        let r = await run(sciFiFan3, exclude: ["space3", "heist2"])
        XCTAssertFalse(ids(r).contains("space3"))
        XCTAssertFalse(ids(r).contains("heist2"))
        let saved = await run(sciFiFan3 + [input("rom3", inWatchlist: true)])
        XCTAssertTrue(ids(saved).contains("rom3"))
    }

    func testANotForMeTitlePushesDownWhatResemblesIt() async {
        let liked = await run(romFan + [input("heist1", .like)])
        let disliked = await run(romFan + [input("heist1", .dislike)])
        XCTAssertGreaterThan(ids(disliked).firstIndex(of: "heist2")!, ids(liked).firstIndex(of: "heist2")!)
        XCTAssertLessThan(disliked.items.first { $0.id == "heist2" }!.score!, 0)
    }

    func testExplanationsComeFromRealPositiveContributions() async {
        let r = await run(sciFiFan3, exclude: ["space2"])
        let reason = r.items.first!.reason!
        XCTAssertNotNil(reason.range(of: #"^Because you liked space[12]$"#, options: .regularExpression))
        let prefs = buildPreferences(collectInteractions(sciFiFan3), featuresByID: meta)
        XCTAssertNil(explainCandidate(f(["western"]), prefs))
    }

    func testColdStartGivesTheLabelledPopularFallback() async {
        XCTAssertEqual(RecommendConfig.minInteractionsForPersonalisation, 3)
        let r = await run([input("space1", .like), input("rom1", inWatchlist: true)])
        XCTAssertFalse(r.isPersonal)
        XCTAssertTrue(r.items.allSatisfy { $0.score == nil && $0.reason == nil })
        let none = await run([])
        XCTAssertFalse(none.isPersonal)
        let onlyNegative = await run([input("space1", .dislike), input("rom1", .dislike), input("heist1", .dislike)])
        XCTAssertFalse(onlyNegative.isPersonal)
    }

    func testFallsBackWhenNothingCanBeScored() async {
        let blind = await run(sciFiFan3, candidates: [Candidate(id: "x", title: "x", genres: [], rating: 5)], load: loader([:]))
        XCTAssertFalse(blind.isPersonal)
    }

    func testReturnsAtMost20AndBoundsHowManyCandidatesGetADetailLookup() async {
        let big = (0..<300).map { Candidate(id: "m\($0)", title: "m\($0)", genres: ["sci-fi"], rating: 5) }
        let seen = Counter()
        let table = meta
        let counting: FeatureLoader = { refs, limit in
            seen.raise(to: min(limit, refs.count))
            var out: [String: Features] = [:]
            for ref in refs { out[ref.id] = table[ref.id] ?? Features(genres: ["sci-fi"]) }
            return out
        }
        let r = await run(sciFiFan3, candidates: big, load: counting)
        XCTAssertLessThanOrEqual(r.items.count, 20)
        XCTAssertLessThanOrEqual(seen.value, 60)
    }

    func testPopularFallbackSkipsExcludedTitlesAndDuplicates() async {
        let r = await run([], exclude: ["heist2"], candidates: pool + [pool[0]])
        XCTAssertFalse(ids(r).contains("heist2"))
        XCTAssertEqual(ids(r).count, Set(ids(r)).count)
    }

    // MARK: explanations reflect the whole profile

    private lazy var h: [String: Features] = [
        "mommy": f(["horror"], ["d0"], ["x0"]),
        "deep": f(["horror", "thriller", "mystery"], ["d1"], ["x1", "x2"]),
        "ends": f(["horror", "thriller", "mystery"], ["d2"], ["x3", "x4"]),
        "empty": f(["horror", "mystery", "drama"], ["d3"], ["x5", "x6"]),
        "oak": f(["horror", "thriller", "drama"], ["d4"], ["x7", "x8"]),
        "warfare": f(["war", "action", "drama"], ["d5"], ["x9"]),
        "carry": f(["action", "thriller", "crime"], ["d6"], ["x10"]),
        "candA": f(["horror", "mystery", "thriller"], ["d9"], ["z1"]),
        "candB": f(["horror", "thriller", "drama"], ["d9"], ["z2"]),
        "candC": f(["action", "thriller", "crime"], ["d8"], ["z3"]),
        "candD": f(["war", "action", "drama"], ["d7"], ["z4"])
    ]
    private var horrorProfile: [InteractionInput] {
        [input("mommy", inWatchlist: true)] + ["deep", "ends", "empty", "oak", "warfare", "carry"].map { input($0, completed: true) }
    }

    func testBuildsPreferencesFromEveryInteractedTitleNotFromOne() {
        let prefs = buildPreferences(collectInteractions(horrorProfile), featuresByID: h)
        let sources = Set(prefs.contributions.values.flatMap { $0 }.map(\.id))
        XCTAssertEqual(sources, ["mommy", "deep", "ends", "empty", "oak", "warfare", "carry"])
        XCTAssertGreaterThan(prefs.genre["horror"]!, 3)
    }

    func testCitesTheTitleThatMostResemblesEachPickAndDifferentPicksCanCiteDifferentTitles() async {
        let cands = ["candA", "candB", "candC", "candD"].map { Candidate(id: $0, title: $0, genres: h[$0]!.genres, rating: 7) }
        let r = await run(horrorProfile, candidates: cands, load: loader(h))
        let reasons = Dictionary(uniqueKeysWithValues: r.items.map { ($0.id, $0.reason) })
        XCTAssertNotEqual(reasons["candA"] ?? nil, "Because you saved mommy")
        XCTAssertNotNil((reasons["candA"] ?? nil)?.range(of: #"^Because you watched (deep|ends|empty|oak)$"#, options: .regularExpression))
        XCTAssertNotNil((reasons["candC"] ?? nil)?.range(of: #"^Because you watched (carry|warfare|deep|ends|oak)$"#, options: .regularExpression))
        XCTAssertGreaterThan(Set(reasons.values.compactMap { $0 }).count, 1)
    }

    func testPrefersAStrongerSignalOverAWeakerOneWhenResemblanceIsEqual() async {
        let tied = [input("deep", inWatchlist: true), input("ends", .like), input("empty", inWatchlist: true), input("oak", completed: true)]
        var table = h
        table["ends"] = h["deep"]
        let cand = Candidate(id: "candA", title: "candA", genres: h["candA"]!.genres, rating: 7)
        let r = await run(tied, candidates: [cand], load: loader(table))
        XCTAssertEqual(r.items.first?.reason, "Because you liked ends")
    }

    // MARK: a title never picks itself

    private lazy var selfMeta: [String: Features] = [
        "saved": f(["horror", "mystery"], ["dq"], ["q1", "q2"]),
        "liked": f(["horror", "thriller"], ["dl"], ["l1"]),
        "a": f(["horror", "thriller", "mystery"], ["da"], ["a1"]),
        "b": f(["horror", "thriller", "drama"], ["db"], ["b1"]),
        "c": f(["horror", "mystery", "drama"], ["dc"], ["c1"]),
        "other": f(["horror", "mystery"], ["dz"], ["z1"])
    ]
    private var selfBase: [InteractionInput] { [input("a", completed: true), input("b", completed: true), input("c", completed: true)] }
    private func selfCandidate(_ id: String) -> Candidate { Candidate(id: id, title: id, genres: selfMeta[id]!.genres, rating: 7) }

    func testDoesNotCiteTheTitleItselfAsTheReasonForItsOwnPick() async {
        let r = await run(selfBase + [input("saved", inWatchlist: true)], candidates: [selfCandidate("saved"), selfCandidate("other")], load: loader(selfMeta))
        let mine = r.items.first { $0.id == "saved" }
        XCTAssertFalse((mine?.reason ?? "").hasSuffix("saved"))
        for item in r.items { XCTAssertFalse((item.reason ?? "").contains("you liked \(item.id)")) }
    }

    func testIsScoredAsIfItsOwnSignalWereNotThere() async {
        let withSelf = await run(selfBase + [input("saved", inWatchlist: true), input("liked", .like)],
                                 candidates: [selfCandidate("saved"), selfCandidate("liked"), selfCandidate("other")], load: loader(selfMeta))
        let without = await run(selfBase + [input("liked", .like)], candidates: [selfCandidate("saved")], load: loader(selfMeta))
        XCTAssertEqual(withSelf.items.first { $0.id == "saved" }!.score!, without.items.first { $0.id == "saved" }!.score!, accuracy: 1e-9)
    }

    // MARK: diversity

    private lazy var own: [(String, Features)] = [
        ("h1", f(["horror", "thriller", "mystery"], ["dh1"], ["ah1"])),
        ("h2", f(["horror", "thriller", "drama"], ["dh2"], ["ah2"])),
        ("h3", f(["horror", "mystery", "drama"], ["dh3"], ["ah3"])),
        ("h4", f(["horror", "thriller"], ["dh4"], ["ah4"])),
        ("w1", f(["war", "action", "drama"], ["dw1"], ["aw1"])),
        ("w2", f(["action", "adventure", "war"], ["dw2"], ["aw2"])),
        ("w3", f(["action", "thriller", "crime"], ["dw3"], ["aw3"]))
    ]
    private var horror: [(String, Features, Double)] {
        (0..<30).map { i in
            ("H\(i)", f(i % 2 == 1 ? ["horror", "thriller", "mystery"] : ["horror", "thriller", "drama"], ["dx\(i % 5)"], ["cx\(i)"]), 9.0)
        }
    }
    private var action: [(String, Features, Double)] {
        (0..<10).map { i in
            ("A\(i)", f(i % 2 == 1 ? ["war", "action", "drama"] : ["action", "adventure", "war"], ["dy\(i % 3)"], ["cy\(i)"]), 6.0)
        }
    }

    private func goDiverse() async -> EngineResult {
        var table: [String: Features] = [:]
        for (id, ft) in own { table[id] = ft }
        for (id, ft, _) in horror + action { table[id] = ft }
        let cands = (horror + action).map { Candidate(id: $0.0, title: $0.0, genres: $0.1.genres, rating: $0.2) }
        return await run(own.map { input($0.0, completed: true) }, candidates: cands, load: loader(table))
    }

    func testCoversEveryTasteInTheListNotJustTheBiggestOne() async {
        let picked = ids(await goDiverse())
        XCTAssertTrue(picked.contains { $0.hasPrefix("A") })
        XCTAssertLessThan(picked.filter { $0.hasPrefix("H") }.count, picked.count)
    }

    func testLetsNoSingleTitleExplainMoreThanTheMaximumPicksAndReasonsStayTruthful() async {
        var counts: [String: Int] = [:]
        for item in await goDiverse().items {
            guard let reason = item.reason, reason.hasPrefix("Because you watched ") else { continue }
            counts[String(reason.dropFirst("Because you watched ".count)), default: 0] += 1
        }
        XCTAssertLessThanOrEqual(counts.values.max() ?? 0, RecommendConfig.maxPicksPerSource)
        XCTAssertGreaterThanOrEqual(counts.count, 5)
    }

    func testStillReturnsTheBestScoringPicksFirstAndFillsUpTo20() async {
        let r = await goDiverse()
        XCTAssertEqual(r.items.count, 20)
        XCTAssertTrue(r.isPersonal)
        XCTAssertGreaterThan(r.items.first!.score!, 0)
    }

    // MARK: signature

    func testTheSignatureChangesExactlyWhenFeedbackCompletionOrWatchlistChange() {
        let base = [input("a", .like), input("b", inWatchlist: true)]
        let sig = signatureOf(collectInteractions(base))
        XCTAssertEqual(sig, signatureOf(collectInteractions(base)))
        XCTAssertNotEqual(sig, signatureOf(collectInteractions([input("a", .dislike), input("b", inWatchlist: true)])))
        XCTAssertNotEqual(sig, signatureOf(collectInteractions([input("a", .like)])))
        XCTAssertNotEqual(sig, signatureOf(collectInteractions(base + [input("c", completed: true)])))
        XCTAssertEqual(sig, signatureOf(collectInteractions([input("a", .like, completed: true), input("b", inWatchlist: true)])))
    }

    // MARK: TV shows in the same row

    func testAShowCanBePickedFromAMovieTasteAndItsDetailsAreLookedUpAsAShow() async {
        let shows = ["show1": f(["crime", "thriller"], [], ["a", "z"]), "show2": f(["romance", "comedy"], [], ["y"])]
        let mixed = pool + [
            Candidate(id: "show1", title: "show1", genres: shows["show1"]!.genres, rating: 8, type: "series"),
            Candidate(id: "show2", title: "show2", genres: shows["show2"]!.genres, rating: 8, type: "series")
        ]
        let asked = Asked()
        var table = meta
        for (k, v) in shows { table[k] = v }
        let snapshot = table
        let load: FeatureLoader = { refs, _ in
            asked.add(refs)
            var out: [String: Features] = [:]
            for ref in refs { if let found = snapshot[ref.id] { out[ref.id] = found } }
            return out
        }
        let result = await run([input("heist1", .like), input("heist2", completed: true), input("space1", inWatchlist: true)], candidates: mixed, load: load)
        XCTAssertTrue(result.isPersonal)
        XCTAssertTrue(ids(result).contains("show1"))
        XCTAssertEqual(asked.refs.first { $0.id == "show1" }?.type, "series")
    }

    func testALikedShowShapesTheTasteLikeALikedMovie() async {
        var table = meta
        table["show1"] = f(["crime", "thriller"], [], ["a", "z"])
        let result = await run([input("show1", .like), input("heist2", .like), input("heist1", completed: true)],
                               exclude: ["show1", "heist2", "heist1"], load: loader(table))
        XCTAssertEqual(ids(result).first, "heist3")
    }
}

private final class Counter: @unchecked Sendable {
    private let lock = NSLock()
    private var current = 0
    var value: Int { lock.lock(); defer { lock.unlock() }; return current }
    func raise(to n: Int) { lock.lock(); current = max(current, n); lock.unlock() }
}

private final class Asked: @unchecked Sendable {
    private let lock = NSLock()
    private var all: [TitleRef] = []
    var refs: [TitleRef] { lock.lock(); defer { lock.unlock() }; return all }
    func add(_ more: [TitleRef]) { lock.lock(); all += more; lock.unlock() }
}
