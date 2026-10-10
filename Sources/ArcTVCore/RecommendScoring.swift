import Foundation

/// Cosine similarity of two sparse vectors; negative preferences stay negative. nil when either vector has no magnitude.
func cosine(_ a: [String: Double], _ b: [String: Double]) -> Double? {
    var dot = 0.0
    var na = 0.0
    var nb = 0.0
    for key in a.keys.sorted() {
        let value = a[key] ?? 0
        na += value * value
        if let other = b[key] { dot += value * other }
    }
    for key in b.keys.sorted() { nb += (b[key] ?? 0) * (b[key] ?? 0) }
    if na == 0 || nb == 0 { return nil }
    return dot / (na.squareRoot() * nb.squareRoot())
}

public struct ScoreResult: Equatable, Sendable {
    /// Internal ranking value in [-1, 1]. Not a probability and not a rating.
    public var score: Double
    /// The per-category cosine similarities that went into it (only the categories that could be compared).
    public var categories: [TasteCategory: Double]
}

/// Weighted mean of the category similarities. A category with no candidate metadata, or where the profile has no nonzero preference, is omitted
/// and the remaining weights renormalised; if nothing can be compared the candidate is unscored (nil).
public func scoreCandidate(_ features: Features?, _ prefs: TastePreferences) -> ScoreResult? {
    guard let features else { return nil }
    var categories: [TasteCategory: Double] = [:]
    var weighted = 0.0
    var total = 0.0
    for category in TasteCategory.allCases {
        let list = features.list(category)
        if list.isEmpty || !prefs.has(category) { continue }
        let vector = Dictionary(list.map { ($0, 1.0) }, uniquingKeysWith: { first, _ in first })
        guard let similarity = cosine(vector, prefs.vector(category)) else { continue }
        categories[category] = similarity
        weighted += category.weight * similarity
        total += category.weight
    }
    if total == 0 { return nil }
    return ScoreResult(score: weighted / total, categories: categories)
}

private func verb(_ kind: SignalKind) -> String {
    switch kind {
    case .like: return "liked"
    case .completed: return "watched"
    case .watchlist: return "saved"
    case .dislike: return ""
    }
}

private func strength(_ kind: SignalKind) -> Int {
    switch kind {
    case .like: return 3
    case .completed: return 2
    case .watchlist: return 1
    case .dislike: return 0
    }
}

/// One of the profile's titles and how much of a candidate's score it accounts for.
public struct Source: Equatable, Sendable {
    public var id: String
    public var title: String
    public var kind: SignalKind
    /// Weighted sum over the candidate's genres / directors / cast of what this title added to each feature.
    public var total: Double = 0
    /// The part of `total` that came through directors.
    public var director: Double = 0
}

/// Every title the profile has a positive signal for, credited with the part of this candidate's score it contributed, biggest first; ties go to
/// the stronger signal (like, finished, saved), then id. Disliked titles are never sources.
public func rankSources(_ features: Features?, _ prefs: TastePreferences) -> [Source] {
    guard let features else { return [] }
    var credit: [String: Source] = [:]
    for category in TasteCategory.allCases {
        for feature in features.list(category) {
            for c in prefs.contributions[contributionKey(category, feature)] ?? [] {
                if c.amount <= 0 || c.kind == .dislike { continue }
                var entry = credit[c.id] ?? Source(id: c.id, title: c.title, kind: c.kind)
                let part = category.weight * c.amount
                entry.total += part
                if category == .director { entry.director += part }
                credit[c.id] = entry
            }
        }
    }
    return credit.values.sorted {
        if $0.total != $1.total { return $0.total > $1.total }
        if strength($0.kind) != strength($1.kind) { return strength($0.kind) > strength($1.kind) }
        return $0.id < $1.id
    }
}

/// The reason line for a source: "Because you liked X", or "More from directors you enjoy" when it mostly matches through a shared director.
public func reasonFor(_ source: Source) -> String {
    source.director > source.total / 2 ? "More from directors you enjoy" : "Because you \(verb(source.kind)) \(source.title)"
}

public protocol ScoredPick {
    var id: String { get }
    var score: Double { get }
    /// Titles of the profile's that contributed to this pick, best first (see `rankSources`).
    var sources: [Source] { get }
}

public struct DiversifiedPick<T> {
    public var pick: T
    /// The source title this pick is explained by (nil when none contributed positively).
    public var source: Source?
}

/// Diversity step -- separate from scoring and applied after it. Walks the picks best score first and gives each the strongest of its contributing
/// titles that is not yet "used up" (one title can explain at most `maxPerSource` picks); a pick whose contributors are all used up waits and only
/// fills spare places at the end. One cluster of the profile's taste can't crowd out the rest, and every stated reason names a title that really
/// contributed to that pick.
public func diversify<T: ScoredPick>(_ sortedByScore: [T], limit: Int = RecommendConfig.maxResults,
                                     maxPerSource: Int = RecommendConfig.maxPicksPerSource) -> [DiversifiedPick<T>] {
    var used: [String: Int] = [:]
    var chosen: [DiversifiedPick<T>] = []
    var waiting: [T] = []
    for pick in sortedByScore {
        if chosen.count >= limit { break }
        if pick.sources.isEmpty {
            chosen.append(DiversifiedPick(pick: pick, source: nil))
            continue
        }
        guard let source = pick.sources.first(where: { (used[$0.id] ?? 0) < maxPerSource }) else {
            waiting.append(pick)
            continue
        }
        used[source.id, default: 0] += 1
        chosen.append(DiversifiedPick(pick: pick, source: source))
    }
    for pick in waiting {
        if chosen.count >= limit { break }
        chosen.append(DiversifiedPick(pick: pick, source: pick.sources.first))
    }
    return chosen
}

/// The reason for the single best source, or nil when nothing positive matched (no reason is ever invented).
public func explainCandidate(_ features: Features?, _ prefs: TastePreferences) -> String? {
    rankSources(features, prefs).first.map(reasonFor)
}
