import Foundation

extension MetaPreview {
    /// The release year from `releaseInfo` ("2026", "2019-2024"), if it starts with one.
    public var year: Int? {
        guard let info = releaseInfo, info.count >= 4, let value = Int(info.prefix(4)) else { return nil }
        return value
    }
}

/// How Movies and TV Shows are ordered (the web app's three pills).
public enum BrowseSort: String, CaseIterable, Identifiable, Sendable {
    case featured = "Featured"
    case highestRated = "Highest Rated"
    case newest = "Newest"

    public var id: String { rawValue }

    public func apply(_ items: [MetaPreview]) -> [MetaPreview] {
        switch self {
        case .featured:
            return items
        case .highestRated:
            return items.sorted { (Double($0.imdbRating ?? "") ?? -1) > (Double($1.imdbRating ?? "") ?? -1) }
        case .newest:
            return items.sorted { ($0.year ?? -1) > ($1.year ?? -1) }
        }
    }
}

/// The genres Cinemeta's catalogues can be filtered by (the web app's drop-down).
public enum Genres {
    /// The Movies drop-down: exactly the genres Cinemeta's catalogue lists, in its order.
    public static let movies = ["Action", "Adventure", "Animation", "Biography", "Comedy", "Crime", "Documentary", "Drama", "Family", "Fantasy", "History", "Horror", "Mystery", "Romance", "Sci-Fi", "Sport", "Thriller", "War", "Western"]
    /// The TV Shows drop-down: the same, and three more.
    public static let shows = movies + ["Reality-TV", "Talk-Show", "Game-Show"]

    public static let all = [
        "Action", "Adventure", "Animation", "Biography", "Comedy", "Crime", "Documentary", "Drama", "Family", "Fantasy",
        "History", "Horror", "Music", "Mystery", "Romance", "Sci-Fi", "Sport", "Thriller", "War", "Western"
    ]
}

/// Titles with no repeats, keeping the first of each id.
public func distinctByID(_ items: [MetaPreview]) -> [MetaPreview] {
    var seen = Set<String>()
    return items.filter { seen.insert($0.id).inserted }
}

/// Movies and shows from one search, taking turns so neither kind buries the other.
public func interleave(_ first: [MetaPreview], _ second: [MetaPreview]) -> [MetaPreview] {
    var out: [MetaPreview] = []
    for index in 0..<max(first.count, second.count) {
        if index < first.count { out.append(first[index]) }
        if index < second.count { out.append(second[index]) }
    }
    return out
}
