import Foundation

/// The parts of a Stremio addon manifest the app uses (the protocol is the same one the Android and web apps speak).
public struct AddonManifest: Codable, Equatable, Sendable {
    public var id: String
    public var name: String
    public var version: String?
    public var description: String?
    public var catalogs: [CatalogDefinition]?

    public init(id: String, name: String, version: String? = nil, description: String? = nil, catalogs: [CatalogDefinition]? = nil) {
        self.id = id
        self.name = name
        self.version = version
        self.description = description
        self.catalogs = catalogs
    }

    /// Whether this addon offers a catalogue with [id] for [type] (Cinemeta has "top", "year" and "imdbRating").
    public func offersCatalog(type: String, id catalogId: String) -> Bool {
        (catalogs ?? []).contains { $0.type == type && $0.id == catalogId }
    }
}

public struct CatalogDefinition: Codable, Equatable, Sendable {
    public var type: String
    public var id: String
    public var name: String?

    public init(type: String, id: String, name: String? = nil) {
        self.type = type
        self.id = id
        self.name = name
    }
}

/// One title in a catalogue: enough for a poster card now, and for a details page later.
public struct MetaPreview: Codable, Equatable, Identifiable, Sendable {
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

    public init(id: String, type: String, name: String, poster: String? = nil, background: String? = nil, logo: String? = nil,
                description: String? = nil, releaseInfo: String? = nil, imdbRating: String? = nil, genres: [String]? = nil, runtime: String? = nil) {
        self.id = id
        self.type = type
        self.name = name
        self.poster = poster
        self.background = background
        self.logo = logo
        self.description = description
        self.releaseInfo = releaseInfo
        self.imdbRating = imdbRating
        self.genres = genres
        self.runtime = runtime
    }
}

struct CatalogResponse: Codable {
    var metas: [MetaPreview]?
}
