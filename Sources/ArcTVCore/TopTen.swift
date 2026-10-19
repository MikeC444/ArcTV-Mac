import Foundation

/// Netflix's page opens with a "Top 10 Today" row: ten titles from TMDB's popularity list for the service in the viewer's country, a series and a movie
/// in turn (not Netflix's own chart). The same rules as the web app's `TopTenRow.tsx` and the Fire TV app's `TopTen.kt`.
public enum TopTen {
    /// How many titles the row shows.
    public static let count = 10
    /// How many candidates are looked at when some genres are blocked (the ten shown come from the first few that are left).
    public static let pool = 30
    /// The service whose page has the Top 10 row, wide pictures and the red N (the web app does this for Netflix only).
    public static let service = "netflix"

    /// Series and movies taken in turn (each list is most popular first, a series first), without repeats.
    public static func rankedPool(movies: [MetaPreview], shows: [MetaPreview], limit: Int) -> [MetaPreview] {
        var out: [MetaPreview] = []
        var seen = Set<String>()
        var index = 0
        while out.count < limit, index < max(movies.count, shows.count) {
            for candidate in [shows.indices.contains(index) ? shows[index] : nil, movies.indices.contains(index) ? movies[index] : nil] {
                if let candidate, out.count < limit, seen.insert(candidate.id).inserted { out.append(candidate) }
            }
            index += 1
        }
        return out
    }

    public static func pick(movies: [MetaPreview], shows: [MetaPreview]) -> [MetaPreview] {
        rankedPool(movies: movies, shows: shows, limit: count)
    }

    /// The first `count` of `candidates` (in order) that carry none of the blocked genres. TMDB's list has no genres, so each candidate's are looked up
    /// through `genresOf` (a chunk at a time, `count` at once); a title whose genres cannot be found is kept, as everywhere else a title with no genres is.
    public static func pickUnblocked(_ candidates: [MetaPreview], blocked: Set<String>, count: Int,
                                     genresOf: @escaping @Sendable (MetaPreview) async -> [String]?) async -> [MetaPreview] {
        var out: [MetaPreview] = []
        var at = 0
        while at < candidates.count, out.count < count {
            let chunk = Array(candidates[at..<min(at + count, candidates.count)])
            let genres = await withTaskGroup(of: (Int, [String]?).self) { group -> [[String]?] in
                for (index, item) in chunk.enumerated() { group.addTask { (index, await genresOf(item)) } }
                var results = [[String]?](repeating: nil, count: chunk.count)
                for await (index, found) in group { results[index] = found }
                return results
            }
            for (index, item) in chunk.enumerated() where out.count < count {
                var checked = item
                if let found = genres[index] { checked.genres = found }
                if !([checked].withoutBlocked(blocked)).isEmpty { out.append(item) }
            }
            at += count
        }
        return out
    }
}
