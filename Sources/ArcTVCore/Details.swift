import Foundation

/// An episode of a show (`videos` in an addon's meta answer).
public struct EpisodeInfo: Codable, Equatable, Identifiable, Sendable {
    public var id: String
    public var title: String?
    public var name: String?
    public var season: Int?
    public var episode: Int?
    public var released: String?
    public var thumbnail: String?
    public var overview: String?

    public var displayTitle: String { title ?? name ?? "Episode \(episode ?? 0)" }
}

/// A person in the cast: a name, the character and a photo when the addon (or the account's cast lookup) has them.
public struct CastMember: Equatable, Identifiable, Sendable {
    public var name: String
    public var role: String?
    public var photoURL: String?
    public var id: String { name }

    public init(name: String, role: String? = nil, photoURL: String? = nil) {
        self.name = name
        self.role = role
        self.photoURL = photoURL
    }
}

public struct AppExtras: Codable, Equatable, Sendable {
    public var cast: [CastExtra]?
}

public struct CastExtra: Codable, Equatable, Sendable {
    public var name: String?
    public var character: String?
    public var photo: String?
}

/// What a title's details page shows (an addon's `/meta/<type>/<id>.json`).
public struct MetaDetail: Codable, Equatable, Identifiable, Sendable {
    public var id: String
    public var type: String
    public var name: String
    public var poster: String?
    public var background: String?
    public var logo: String?
    public var description: String?
    public var releaseInfo: String?
    public var imdbRating: String?
    public var genres: [String]?
    public var runtime: String?
    public var director: [String]?
    public var cast: [String]?
    public var videos: [EpisodeInfo]?
    /// Cinemeta's extra: the cast with photos and characters.
    public var app_extras: AppExtras?

    /// The cast with photos and characters when the addon sends them (Cinemeta's `app_extras.cast`); names the extended list lacks follow it, so
    /// nobody in `cast` disappears.
    public var castMembers: [CastMember] {
        let photographed = (app_extras?.cast ?? []).compactMap { extra -> CastMember? in
            guard let name = extra.name, !name.trimmingCharacters(in: .whitespaces).isEmpty else { return nil }
            return CastMember(name: name.htmlDecoded, role: extra.character.flatMap { $0.isEmpty ? nil : $0.htmlDecoded }, photoURL: extra.photo.flatMap { $0.isEmpty ? nil : $0 })
        }
        let known = Set(photographed.map(\.name))
        return photographed + (cast ?? []).map(\.htmlDecoded).filter { !$0.isEmpty && !known.contains($0) }.map { CastMember(name: $0) }
    }

    /// Episodes grouped by season, episodes in order. Empty for a movie.
    public var seasons: [Int: [EpisodeInfo]] {
        var grouped: [Int: [EpisodeInfo]] = [:]
        for video in videos ?? [] {
            guard let season = video.season, video.episode != nil else { continue }
            grouped[season, default: []].append(video)
        }
        return grouped.mapValues { $0.sorted { ($0.episode ?? 0) < ($1.episode ?? 0) } }
    }

    /// The seasons in order. Season 0 ("Specials") is left out, as on the web app.
    public var seasonNumbers: [Int] { seasons.keys.filter { $0 > 0 }.sorted() }

    /// The preview card fields this detail came from, for places that show a poster.
    public var preview: MetaPreview {
        MetaPreview(id: id, type: type, name: name, poster: poster, background: background, logo: logo, description: description,
                    releaseInfo: releaseInfo, imdbRating: imdbRating, genres: genres, runtime: runtime)
    }
}

struct MetaResponse: Codable {
    var meta: MetaDetail?
}

public extension MetaPreview {
    /// The details page's starting point while the full answer loads (and what it shows if the addon has nothing more).
    var asDetail: MetaDetail {
        MetaDetail(id: id, type: type, name: name, poster: poster, background: background, logo: logo, description: description,
                   releaseInfo: releaseInfo, imdbRating: imdbRating, genres: genres, runtime: runtime)
    }
}

/// The id addons expect for a stream request: the title's id, plus ":season:episode" for an episode.
public func streamID(titleID: String, season: Int?, episode: Int?) -> String {
    if let season, let episode { return "\(titleID):\(season):\(episode)" }
    return titleID
}
