import Foundation

/// The parts of a Stremio addon manifest the app uses (the protocol is the same one the Android and web apps speak).
public struct AddonManifest: Codable, Equatable, Sendable {
    public var id: String
    public var name: String
    public var version: String?
    public var description: String?
    public var catalogs: [CatalogDefinition]?
    public var types: [String]?
    public var idPrefixes: [String]?
    public var resources: [AddonResource]?

    public init(id: String, name: String, version: String? = nil, description: String? = nil, catalogs: [CatalogDefinition]? = nil,
                types: [String]? = nil, idPrefixes: [String]? = nil, resources: [AddonResource]? = nil) {
        self.id = id
        self.name = name
        self.version = version
        self.description = description
        self.catalogs = catalogs
        self.types = types
        self.idPrefixes = idPrefixes
        self.resources = resources
    }

    /// Whether this addon can give streams for [id] of [type]: it lists a "stream" resource whose types and id prefixes (its own, else the
    /// manifest's) allow it. An addon that says nothing about types or prefixes is asked for everything.
    public func providesStreams(type: String, id titleId: String) -> Bool {
        for resource in resources ?? [] where resource.name == "stream" {
            let allowedTypes = resource.types ?? types
            let prefixes = resource.idPrefixes ?? idPrefixes
            if let allowedTypes, !allowedTypes.contains(type) { continue }
            if let prefixes, !prefixes.isEmpty, !prefixes.contains(where: { titleId.hasPrefix($0) }) { continue }
            return true
        }
        return false
    }

    /// Whether this addon offers a catalogue with [id] for [type] (Cinemeta has "top", "year" and "imdbRating").
    public func offersCatalog(type: String, id catalogId: String) -> Bool {
        (catalogs ?? []).contains { $0.type == type && $0.id == catalogId }
    }
}

/// A manifest's `resources` entry: either a plain name ("catalog") or {"name": "stream", "types": [...], "idPrefixes": [...]}.
public struct AddonResource: Codable, Equatable, Sendable {
    public var name: String
    public var types: [String]?
    public var idPrefixes: [String]?

    public init(name: String, types: [String]? = nil, idPrefixes: [String]? = nil) {
        self.name = name
        self.types = types
        self.idPrefixes = idPrefixes
    }

    private enum CodingKeys: String, CodingKey { case name, types, idPrefixes }

    public init(from decoder: Decoder) throws {
        if let single = try? decoder.singleValueContainer(), let text = try? single.decode(String.self) {
            self.init(name: text)
            return
        }
        // Never throws: one odd entry must not make the whole manifest unreadable.
        let keyed = try? decoder.container(keyedBy: CodingKeys.self)
        self.init(
            name: (try? keyed?.decode(String.self, forKey: .name)) ?? "",
            types: (try? keyed?.decodeIfPresent([String].self, forKey: .types)) ?? nil,
            idPrefixes: (try? keyed?.decodeIfPresent([String].self, forKey: .idPrefixes)) ?? nil
        )
    }
}

/// A filter a catalogue accepts: "genre" (with the options it lists), "skip" (paging), "search".
public struct CatalogExtra: Codable, Equatable, Sendable {
    public var name: String
    public var isRequired: Bool?
    public var options: [String]?

    public init(name: String, isRequired: Bool? = nil, options: [String]? = nil) {
        self.name = name
        self.isRequired = isRequired
        self.options = options
    }
}

public struct CatalogDefinition: Codable, Equatable, Sendable {
    public var type: String
    public var id: String
    public var name: String?
    public var extra: [CatalogExtra]?

    public init(type: String, id: String, name: String? = nil, extra: [CatalogExtra]? = nil) {
        self.type = type
        self.id = id
        self.name = name
        self.extra = extra
    }

    var genreExtra: CatalogExtra? { (extra ?? []).first { $0.name == "genre" } }
    var genreOptions: [String] { genreExtra?.options ?? [] }
    /// A catalogue that does not need a genre to answer.
    var isBase: Bool { genreExtra?.isRequired != true }
    var supportsSkip: Bool { (extra ?? []).contains { $0.name == "skip" } }
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
