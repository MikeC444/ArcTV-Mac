import Foundation

/// One saved title on the account's My List (GET /user/watchlist).
public struct WatchlistItem: Codable, Equatable, Identifiable, Sendable {
    public var providerId: String
    public var contentId: String
    public var contentType: String
    public var title: String
    public var posterUrl: String?
    public var backdropUrl: String?
    public var year: Int?
    public var rating: Double?
    public var watched: Bool?
    public var updatedAt: String

    public var id: String { contentId }

    public init(providerId: String, contentId: String, contentType: String, title: String, posterUrl: String? = nil, backdropUrl: String? = nil,
                year: Int? = nil, rating: Double? = nil, watched: Bool? = nil, updatedAt: String) {
        self.providerId = providerId
        self.contentId = contentId
        self.contentType = contentType
        self.title = title
        self.posterUrl = posterUrl
        self.backdropUrl = backdropUrl
        self.year = year
        self.rating = rating
        self.watched = watched
        self.updatedAt = updatedAt
    }

    /// As a poster-card title: the backend's MOVIE / TV_SHOW become the addon protocol's movie / series.
    public var asPreview: MetaPreview {
        MetaPreview(
            id: contentId, type: contentType == "MOVIE" ? "movie" : "series", name: title, poster: posterUrl, background: backdropUrl,
            releaseInfo: year.map(String.init), imdbRating: rating.map { String($0) }
        )
    }
}

struct WatchlistResponse: Decodable {
    var items: [WatchlistItem]
}

extension AuthClient {
    /// The account's My List, newest first as the backend orders it.
    public func watchlist(accessToken: String) async throws -> [WatchlistItem] {
        guard let url = URL(string: baseURL + "/user/watchlist") else { throw APIError.badURL(baseURL) }
        var request = URLRequest(url: url)
        request.timeoutInterval = 60
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue(AppInfo.version, forHTTPHeaderField: "X-ArcTV-App-Version")
        let data = try await HTTP.data(for: request)
        guard let decoded = try? JSONDecoder().decode(WatchlistResponse.self, from: data) else { throw APIError.unreadable }
        return decoded.items
    }
}
