import Foundation

public enum TasteCategory: Sendable, CaseIterable {
    case genre, director, cast

    var key: String {
        switch self {
        case .genre: return "genre"
        case .director: return "director"
        case .cast: return "cast"
        }
    }

    var weight: Double {
        switch self {
        case .genre: return RecommendConfig.categoryWeightGenre
        case .director: return RecommendConfig.categoryWeightDirector
        case .cast: return RecommendConfig.categoryWeightCast
        }
    }
}

/// What the addon tells us about a title, normalised: lower-cased, trimmed, unique. Any list may be empty (metadata is often partial).
public struct Features: Equatable, Codable, Sendable {
    public var genres: [String]
    public var directors: [String]
    public var cast: [String]

    public init(genres: [String] = [], directors: [String] = [], cast: [String] = []) {
        self.genres = genres
        self.directors = directors
        self.cast = cast
    }

    func list(_ category: TasteCategory) -> [String] {
        switch category {
        case .genre: return genres
        case .director: return directors
        case .cast: return cast
        }
    }

    public var hasAny: Bool { !genres.isEmpty || !directors.isEmpty || !cast.isEmpty }
}

public func normaliseName(_ name: String) -> String {
    name.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ").lowercased()
}

private func unique(_ names: [String]) -> [String] {
    var seen = Set<String>()
    var out: [String] = []
    for name in names {
        let normal = normaliseName(name)
        if !normal.isEmpty, seen.insert(normal).inserted { out.append(normal) }
    }
    return out
}

/// Features from raw lists (the shape an addon's meta uses), with a name list cut to a sensible length and a director entry like "A, B" split in two.
public func featuresFromNames(genres: [String], directors: [String], cast: [String]) -> Features {
    let splitDirectors = directors.flatMap { $0.components(separatedBy: CharacterSet(charactersIn: ",/&")) }
    return Features(genres: unique(genres), directors: unique(splitDirectors), cast: Array(unique(cast).prefix(RecommendConfig.castFeatureLimit)))
}

/// Features from a title's full details (an addon's meta answer).
public func featuresFromMeta(_ meta: MetaDetail) -> Features {
    featuresFromNames(genres: meta.genres ?? [], directors: meta.director ?? [], cast: meta.cast ?? [])
}

public func normaliseGenres(_ genres: [String]) -> [String] {
    var seen = Set<String>()
    return genres.map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }.filter { !$0.isEmpty && seen.insert($0).inserted }
}
