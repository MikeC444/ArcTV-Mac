import Foundation

/// Small seeded generator (mulberry32): the same seed always gives the same sequence, so one launch is stable and the step is testable. The
/// same arithmetic as the web and Fire TV apps' `seededRandom`.
public final class SeededRandom {
    private var a: UInt32

    public init(seed: Int) { a = UInt32(truncatingIfNeeded: seed) }

    public func next() -> Double {
        a = a &+ 0x6d2b79f5
        var t = a
        t = (t ^ (t >> 15)) &* (t | 1)
        t = t ^ (t &+ ((t ^ (t >> 7)) &* (t | 61)))
        return Double(t ^ (t >> 14)) / 4294967296.0
    }
}

public protocol ComposePick {
    var id: String { get }
    var score: Double { get }
    /// The genre the pick stands for in the profile (see `primaryGenre`); nil when it matches none of the profile's genres.
    var genre: String? { get }
}

/// The genre a title "stands for" in this profile: of its own genres, the one the profile likes most overall (ties: alphabetical). Nil when none of
/// its genres has a positive weight. Used on both the profile's own titles and candidates, so the two are bucketed the same way.
public func primaryGenre(_ genres: [String], _ prefs: TastePreferences) -> String? {
    var best: String?
    var bestWeight = 0.0
    for genre in Set(genres).sorted() {
        let weight = prefs.genre[genre] ?? 0
        if weight > bestWeight {
            best = genre
            bestWeight = weight
        }
    }
    return best
}

/// How the profile's taste splits across genres: each of its own titles with a positive signal counts, by its signal weight, towards that title's
/// primary genre. Shares sum to 1; empty when there is nothing positive to go on.
public func tasteShares(_ signalled: [Interaction], ownFeatures: [String: Features], _ prefs: TastePreferences) -> [String: Double] {
    var raw: [String: Double] = [:]
    var total = 0.0
    for interaction in signalled where interaction.weight > 0 {
        guard let genre = primaryGenre(ownFeatures[interaction.id]?.genres ?? [], prefs) else { continue }
        raw[genre, default: 0] += interaction.weight
        total += interaction.weight
    }
    if total <= 0 { return [:] }
    return raw.mapValues { $0 / total }
}

/// Composition step: applied after scoring and before the diversity step; it only CHOOSES and ORDERS picks that were genuinely scored.
///
///  1. The `anchors` best-scoring picks overall are always kept.
///  2. Every other place is given to a genre by the profile's own taste split (Sainte-Lague proportional apportionment: a place goes to the genre
///     with the highest share / (2 x places it already holds + 1)).
///  3. Within a genre the pick is drawn with a seeded weighted draw over that genre's other scored picks (score > 0 and at least `floor` of that
///     genre's best), higher scores likelier, and a pick shown last time `repeatWeight` times as likely. With no seed, the genre's best is taken.
///  4. If a genre runs out, its place goes to the next genre; if all run out, the best remaining scores fill the row.
public func compose<T: ComposePick>(_ sortedByScore: [T], limit: Int, shares: [String: Double] = [:],
                                    anchors: Int = RecommendConfig.rotationAnchors, floor: Double = RecommendConfig.rotationFloor,
                                    repeatWeight: Double = RecommendConfig.rotationRepeatWeight, previous: Set<String> = [],
                                    seed: Int? = nil) -> [T] {
    if sortedByScore.count <= min(anchors, limit) { return Array(sortedByScore.prefix(limit)) }
    let random = seed.map { SeededRandom(seed: $0) }

    var row = Array(sortedByScore.prefix(min(anchors, limit)))
    var used = Set(row.map(\.id))
    var count: [String: Int] = [:]
    for p in row { if let genre = p.genre { count[genre, default: 0] += 1 } }

    // Each genre's remaining scored picks, best first (nil-genre picks only ever fill at the end).
    var buckets: [String: [T]] = [:]
    for p in sortedByScore {
        guard let genre = p.genre, !used.contains(p.id), p.score > 0 else { continue }
        buckets[genre, default: []].append(p)
    }

    // The floor is measured against each genre's best scored pick overall, not against whatever is left of it.
    var genreBest: [String: Double] = [:]
    for p in sortedByScore {
        if let genre = p.genre, p.score > 0, genreBest[genre] == nil { genreBest[genre] = p.score }
    }

    func drawFrom(_ bucket: [T]) -> T? {
        guard let first = bucket.first else { return nil }
        let best = genreBest[first.genre ?? ""] ?? first.score
        let eligible = bucket.filter { $0.score >= best * floor }
        guard var winner = eligible.first else { return nil }
        guard let random else { return winner }
        // Weighted draw of one: Efraimidis-Spirakis key = u^(1/weight), largest wins.
        var winnerKey = -1.0
        for p in eligible {
            let weight = max(1e-6, pow(p.score / best, 2) * (previous.contains(p.id) ? repeatWeight : 1.0))
            let key = pow(random.next(), 1.0 / weight)
            if key > winnerKey {
                winner = p
                winnerKey = key
            }
        }
        return winner
    }

    while row.count < limit {
        // Genres in order of Sainte-Lague priority: a proportional split of the places that also mixes the genres through the row.
        let wanted = buckets.filter { !$0.value.isEmpty }
            .map { (genre: $0.key, priority: (shares[$0.key] ?? 0) / Double(2 * (count[$0.key] ?? 0) + 1)) }
            .sorted {
                if $0.priority != $1.priority { return $0.priority > $1.priority }
                let a = shares[$0.genre] ?? 0
                let b = shares[$1.genre] ?? 0
                if a != b { return a > b }
                return $0.genre < $1.genre
            }
        var found: T?
        for entry in wanted {
            found = drawFrom(buckets[entry.genre] ?? [])
            if found != nil { break }
        }
        guard let pick = found else { break }
        row.append(pick)
        used.insert(pick.id)
        if let genre = pick.genre {
            count[genre, default: 0] += 1
            buckets[genre] = (buckets[genre] ?? []).filter { $0.id != pick.id }
        }
    }
    // Nothing left that clears the bar: the best remaining scores fill the row.
    for p in sortedByScore {
        if row.count >= limit { break }
        if used.insert(p.id).inserted { row.append(p) }
    }
    return row
}
