import Foundation

/// Talks the Stremio addon protocol: fetch a manifest, then use it to pull catalogues.
public struct AddonClient: Sendable {
    public init() {}

    public func fetchManifest(_ manifestURL: String) async throws -> AddonManifest {
        let data = try await HTTP.get(manifestURL)
        do {
            return try JSONDecoder().decode(AddonManifest.self, from: data)
        } catch {
            throw APIError.unreadable
        }
    }

    public func fetchCatalog(manifestURL: String, type: String, catalogId: String, extra: [String: String] = [:]) async throws -> [MetaPreview] {
        let url = AddonURL.catalogURL(manifestURL: manifestURL, type: type, catalogId: catalogId, extra: extra)
        let data = try await HTTP.get(url)
        do {
            return try JSONDecoder().decode(CatalogResponse.self, from: data).metas ?? []
        } catch {
            throw APIError.unreadable
        }
    }

    /// One page of a type's Popular catalogue, optionally for a genre; [skip] is how many titles are already loaded (Stremio's paging).
    public func browse(manifestURL: String, type: String, genre: String?, skip: Int) async throws -> [MetaPreview] {
        var extra: [String: String] = [:]
        if let genre, !genre.isEmpty { extra["genre"] = genre }
        if skip > 0 { extra["skip"] = String(skip) }
        return try await fetchCatalog(manifestURL: manifestURL, type: type, catalogId: "top", extra: extra)
    }

    /// Movies and shows matching [query], taking turns.
    public func search(manifestURL: String, query: String) async -> [MetaPreview] {
        async let movies = try? fetchCatalog(manifestURL: manifestURL, type: "movie", catalogId: "top", extra: ["search": query])
        async let shows = try? fetchCatalog(manifestURL: manifestURL, type: "series", catalogId: "top", extra: ["search": query])
        let foundMovies = await movies ?? []
        let foundShows = await shows ?? []
        return distinctByID(interleave(foundMovies, foundShows))
    }
}
