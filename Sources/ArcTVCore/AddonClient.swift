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
}
