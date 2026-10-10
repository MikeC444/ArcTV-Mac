import Foundation

/// A catalogue entry that could be recommended. `genres` come from the catalogue listing itself (no extra request).
public struct Candidate: Equatable, Sendable {
    public var id: String
    public var title: String
    public var providerId: String?
    public var genres: [String]
    public var rating: Double?
    /// "movie" or "series", so its details are looked up the right way. Nil means a movie.
    public var type: String?

    public init(id: String, title: String, providerId: String? = nil, genres: [String] = [], rating: Double? = nil, type: String? = nil) {
        self.id = id
        self.title = title
        self.providerId = providerId
        self.genres = genres
        self.rating = rating
        self.type = type
    }
}

public extension MetaPreview {
    var asCandidate: Candidate {
        Candidate(id: id, title: name, providerId: AppInfo.cinemetaProviderId, genres: genres ?? [], rating: Double(imdbRating ?? ""), type: type)
    }
}

/// A title (movie or show) whose features are looked up.
public struct TitleRef: Equatable, Sendable {
    public var id: String
    public var providerId: String?
    public var type: String?

    public init(id: String, providerId: String? = nil, type: String? = nil) {
        self.id = id
        self.providerId = providerId
        self.type = type
    }
}

/// Fetches (or reads from cache) the features of up to `limit` titles not yet known. Unknown or failed lookups are left out. Must never throw.
public typealias FeatureLoader = @Sendable (_ refs: [TitleRef], _ limit: Int) async -> [String: Features]

public struct EngineInput: Sendable {
    public var interactions: [Interaction]
    /// Never recommended: finished, rated, dismissed, or already in Continue Watching.
    public var excludeIDs: Set<String>
    public var pool: [Candidate]
    /// How to look up each of the profile's own titles.
    public var interactionRefs: [String: TitleRef]
    public var loadFeatures: FeatureLoader
    /// When set, a refresh swaps most of the row: the strongest picks stay, the rest are drawn with this seed. Nil = fully deterministic.
    public var seed: Int?
    /// Ids shown by the previous launch; they are less likely to be drawn again.
    public var previousShown: Set<String>

    public init(interactions: [Interaction], excludeIDs: Set<String>, pool: [Candidate], interactionRefs: [String: TitleRef],
                loadFeatures: @escaping FeatureLoader, seed: Int? = nil, previousShown: Set<String> = []) {
        self.interactions = interactions
        self.excludeIDs = excludeIDs
        self.pool = pool
        self.interactionRefs = interactionRefs
        self.loadFeatures = loadFeatures
        self.seed = seed
        self.previousShown = previousShown
    }
}

public struct Picked: Equatable, Sendable {
    public var id: String
    /// Internal ranking value; nil in the popular fallback. Never shown as a percentage.
    public var score: Double?
    public var reason: String?
}

public enum EngineResult: Equatable, Sendable {
    case personal([Picked])
    case popular([Picked])

    public var items: [Picked] {
        switch self {
        case let .personal(items), let .popular(items): return items
        }
    }

    public var isPersonal: Bool {
        if case .personal = self { return true }
        return false
    }
}

private func byRatingThenID(_ a: Candidate, _ b: Candidate) -> Bool {
    let ra = a.rating ?? -1
    let rb = b.rating ?? -1
    return ra != rb ? ra > rb : a.id < b.id
}

/// Distinct, eligible candidates, in their given order.
private func eligible(_ pool: [Candidate], _ excludeIDs: Set<String>) -> [Candidate] {
    var seen = Set<String>()
    return pool.filter { !excludeIDs.contains($0.id) && seen.insert($0.id).inserted }
}

/// Cold start / nothing scorable: the best-rated eligible titles, plainly labelled as popular, never as personalised.
public func popularFallback(pool: [Candidate], excludeIDs: Set<String>) -> EngineResult {
    .popular(eligible(pool, excludeIDs).sorted(by: byRatingThenID).prefix(RecommendConfig.maxResults).map { Picked(id: $0.id, score: nil, reason: nil) })
}

private struct ScoredCandidate: ScoredPick, ComposePick {
    var id: String
    var candidate: Candidate
    var score: Double
    var sources: [Source]
    var genre: String?
}

/// Ranking in four plain steps:
///  1. look up the profile's own titles' features and turn the stored signals into genre / director / cast preference vectors;
///  2. shortlist the eligible candidates from their catalogue genres alone: some by overall genre match, some per genre by taste share, the rest
///     round-robin over each of the profile's own titles, within a bounded size;
///  3. fetch the shortlist's directors and cast (cached, bounded concurrency) and score each with the full weighted cosine;
///  4. sort by score (ties: rating, then id), compose the row (strongest stay, the rest follow the profile's genre split and, with a seed, are
///     drawn so a refresh changes most of them), then the separate diversity step keeps the top 20 while stopping any one of the profile's titles
///     from explaining more than `maxPicksPerSource` of them.
public func recommend(_ input: EngineInput) async -> EngineResult {
    let pool = eligible(input.pool, input.excludeIDs)
    let signalled = input.interactions.filter { $0.weight != 0 }
    if signalled.count < RecommendConfig.minInteractionsForPersonalisation || !signalled.contains(where: { $0.weight > 0 }) {
        return popularFallback(pool: pool, excludeIDs: input.excludeIDs)
    }

    let own = signalled.prefix(RecommendConfig.interactionDetailFetchLimit).map { input.interactionRefs[$0.id] ?? TitleRef(id: $0.id) }
    let ownFeatures = await input.loadFeatures(Array(own), RecommendConfig.interactionDetailFetchLimit)
    let prefs = buildPreferences(signalled, featuresByID: ownFeatures)

    // Step 2: shortlist from the catalogue listing alone (its genres).
    struct PreScored { var candidate: Candidate; var pre: Double }
    let preScored = pool
        .map { candidate in
            PreScored(candidate: candidate, pre: scoreCandidate(Features(genres: normaliseGenres(candidate.genres)), prefs)?.score ?? -.infinity)
        }
        .sorted { $0.pre != $1.pre ? $0.pre > $1.pre : byRatingThenID($0.candidate, $1.candidate) }
    var picked = Set<String>()
    var shortlist: [Candidate] = []
    func take(_ candidate: Candidate) {
        if picked.contains(candidate.id) || shortlist.count >= RecommendConfig.candidateDetailFetchLimit { return }
        picked.insert(candidate.id)
        shortlist.append(candidate)
    }
    preScored.prefix(RecommendConfig.shortlistByScore).forEach { take($0.candidate) }

    // Every genre the profile likes gets candidates to score, in proportion to its share of the profile's taste, so a minority taste isn't
    // left with nothing to be picked from just because the biggest taste scores higher on genre alone.
    let shares = tasteShares(signalled, ownFeatures: ownFeatures, prefs)
    for (genre, share) in shares.sorted(by: { $0.value != $1.value ? $0.value > $1.value : $0.key < $1.key }) {
        let quota = max(RecommendConfig.shortlistGenreMin, Int((share * Double(RecommendConfig.shortlistGenreBudget)).rounded(.up)))
        preScored
            .filter { primaryGenre(normaliseGenres($0.candidate.genres), prefs) == genre }
            .prefix(quota)
            .forEach { take($0.candidate) }
    }

    let owners = signalled.filter { $0.weight > 0 }.prefix(RecommendConfig.shortlistSourceTitles)
    let perOwner: [[Candidate]] = owners.map { owner in
        let ownGenres = Set(ownFeatures[owner.id]?.genres ?? [])
        func overlap(_ c: Candidate) -> Double {
            let genres = normaliseGenres(c.genres)
            let shared = genres.filter { ownGenres.contains($0) }.count
            return shared == 0 ? 0 : Double(shared) / Double(ownGenres.count + genres.count - shared)
        }
        return pool
            .map { ($0, overlap($0)) }
            .filter { $0.1 > 0 }
            .sorted { $0.1 != $1.1 ? $0.1 > $1.1 : byRatingThenID($0.0, $1.0) }
            .map { $0.0 }
    }
    var round = 0
    while shortlist.count < RecommendConfig.candidateDetailFetchLimit && round < pool.count {
        var progressed = false
        for list in perOwner {
            if let next = list.first(where: { !picked.contains($0.id) }) {
                take(next)
                progressed = true
            }
        }
        if !progressed { break }
        round += 1
    }
    // Anything still free is filled by overall match.
    preScored.forEach { take($0.candidate) }

    // Step 3: full features for the shortlist.
    let details = await input.loadFeatures(shortlist.map { TitleRef(id: $0.id, providerId: $0.providerId, type: $0.type) }, RecommendConfig.candidateDetailFetchLimit)

    // A candidate that is itself one of the profile's titles (saved or liked but not finished) is judged against the profile WITHOUT that title,
    // so it can neither boost its own score nor be named as its own reason.
    let ownIDs = Set(signalled.map(\.id))
    var withoutSelf: [String: TastePreferences] = [:]
    func prefsFor(_ id: String) -> TastePreferences {
        if !ownIDs.contains(id) { return prefs }
        if let cached = withoutSelf[id] { return cached }
        let built = buildPreferences(signalled.filter { $0.id != id }, featuresByID: ownFeatures)
        withoutSelf[id] = built
        return built
    }
    var scored: [ScoredCandidate] = []
    for candidate in shortlist {
        let fetched = details[candidate.id]
        let features = Features(
            genres: (fetched?.genres.isEmpty == false) ? fetched!.genres : normaliseGenres(candidate.genres),
            directors: fetched?.directors ?? [],
            cast: fetched?.cast ?? []
        )
        let candidatePrefs = prefsFor(candidate.id)
        guard let result = scoreCandidate(features, candidatePrefs) else { continue }
        scored.append(ScoredCandidate(
            id: candidate.id, candidate: candidate, score: result.score,
            sources: result.score > 0 ? rankSources(features, candidatePrefs) : [],
            genre: primaryGenre(features.genres, prefs)
        ))
    }
    if scored.isEmpty { return popularFallback(pool: pool, excludeIDs: input.excludeIDs) }

    // Step 4. What is not in the composed row follows in score order, so the source cap can still pull in a next-best pick when it has to
    // skip one. Without a seed the order is fully deterministic.
    let sorted = scored.sorted { $0.score != $1.score ? $0.score > $1.score : byRatingThenID($0.candidate, $1.candidate) }
    let composed = compose(sorted, limit: RecommendConfig.maxResults, shares: shares, previous: input.previousShown, seed: input.seed)
    let composedIDs = Set(composed.map(\.id))
    let ordered = composed + sorted.filter { !composedIDs.contains($0.id) }
    let items = diversify(ordered, limit: RecommendConfig.maxResults).map { Picked(id: $0.pick.id, score: $0.pick.score, reason: $0.source.map(reasonFor)) }
    return .personal(items)
}
