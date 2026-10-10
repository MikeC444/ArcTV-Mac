import Foundation

/// Timestamps the backend expects: ISO-8601 in UTC with milliseconds ("2026-10-10T00:20:00.123Z").
public enum ISODate {
    public static func now() -> String { string(from: Date()) }

    public static func string(from date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: date)
    }

    /// Reads a backend timestamp, with or without fractional seconds.
    public static func date(from text: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: text) { return date }
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: text)
    }
}

/// A title the account can pick up again (`GET /user/continue-watching`).
public struct ContinueItem: Codable, Equatable, Identifiable, Sendable {
    public var providerId: String
    public var contentId: String
    public var contentType: String
    public var seasonNumber: Int?
    public var episodeNumber: Int?
    public var episodeTitle: String?
    public var title: String
    public var posterUrl: String?
    public var backdropUrl: String?
    public var positionMs: Int64
    public var durationMs: Int64
    public var lastWatchedAt: String

    public var id: String { contentId }

    /// 0 to 1: how far through it is.
    public var progress: Double {
        durationMs > 0 ? min(1, max(0, Double(positionMs) / Double(durationMs))) : 0
    }

    public var positionSeconds: Double { Double(positionMs) / 1000 }

    /// "S1 E3" for an episode, empty for a movie.
    public var episodeLabel: String? {
        guard let season = seasonNumber, let episode = episodeNumber else { return nil }
        return "S\(season) E\(episode)"
    }

    public var asPreview: MetaPreview {
        MetaPreview(id: contentId, type: contentType == "MOVIE" ? "movie" : "series", name: title, poster: posterUrl, background: backdropUrl)
    }
}

struct ContinueResponse: Decodable {
    var items: [ContinueItem]
}

/// A playback position report (`POST /user/watch-progress`): feeds Continue Watching and the watch history.
struct ProgressReport: Encodable {
    var providerId: String
    var contentId: String
    var contentType: String
    var seasonNumber: Int?
    var episodeNumber: Int?
    var episodeTitle: String?
    var title: String
    var posterUrl: String?
    var backdropUrl: String?
    var positionMs: Int64
    var durationMs: Int64
    var completed: Bool
    var watchedAt: String
}

public extension MetaDetail {
    /// This title as a My List entry.
    func watchlistItem(watched: Bool) -> WatchlistItem {
        WatchlistItem(
            providerId: AppInfo.cinemetaProviderId, contentId: id, contentType: type == "movie" ? "MOVIE" : "TV_SHOW", title: name,
            posterUrl: poster, backdropUrl: background, year: year, rating: Double(imdbRating ?? ""), watched: watched, updatedAt: ISODate.now()
        )
    }

    /// The release year from `releaseInfo`.
    var year: Int? {
        guard let info = releaseInfo, info.count >= 4, let value = Int(info.prefix(4)) else { return nil }
        return value
    }
}

extension AuthClient {
    func sendJSON(_ method: String, _ path: String, query: [String: String] = [:], body: Data?, accessToken: String, headers: [String: String] = [:]) async throws -> Data {
        guard var components = URLComponents(string: baseURL + path) else { throw APIError.badURL(baseURL + path) }
        if !query.isEmpty { components.queryItems = query.sorted { $0.key < $1.key }.map { URLQueryItem(name: $0.key, value: $0.value) } }
        guard let url = components.url else { throw APIError.badURL(baseURL + path) }
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.timeoutInterval = 60
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue(AppInfo.version, forHTTPHeaderField: "X-ArcTV-App-Version")
        if let profileID, profileID != Profile.mainID, !Profile.isAccountLevel(path) { request.setValue(profileID, forHTTPHeaderField: "X-ArcTV-Profile") }
        for (name, value) in headers { request.setValue(value, forHTTPHeaderField: name) }
        if let body {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = body
        }
        return try await HTTP.data(for: request)
    }

    public func continueWatching(accessToken: String) async throws -> [ContinueItem] {
        let data = try await sendJSON("GET", "/user/continue-watching", body: nil, accessToken: accessToken)
        guard let decoded = try? JSONDecoder().decode(ContinueResponse.self, from: data) else { throw APIError.unreadable }
        return decoded.items
    }

    /// Reports where someone is in a title. [positionSeconds] and [durationSeconds] are from the player.
    public func reportProgress(accessToken: String, title: MetaDetail, season: Int?, episode: Int?, episodeTitle: String?,
                               positionSeconds: Double, durationSeconds: Double, completed: Bool) async throws {
        let report = ProgressReport(
            providerId: AppInfo.cinemetaProviderId, contentId: title.id, contentType: title.type == "movie" ? "MOVIE" : "TV_SHOW",
            seasonNumber: season, episodeNumber: episode, episodeTitle: episodeTitle, title: title.name, posterUrl: title.poster,
            backdropUrl: title.background, positionMs: Int64(max(0, positionSeconds) * 1000), durationMs: Int64(max(0, durationSeconds) * 1000),
            completed: completed, watchedAt: ISODate.now()
        )
        _ = try await sendJSON("POST", "/user/watch-progress", body: try JSONEncoder().encode(report), accessToken: accessToken)
    }

    /// Takes a title out of Continue Watching (without marking it watched).
    public func removeContinueWatching(accessToken: String, item: ContinueItem) async throws {
        _ = try await sendJSON(
            "DELETE", "/user/continue-watching",
            query: ["providerId": item.providerId, "contentId": item.contentId, "contentType": item.contentType, "updatedAt": ISODate.now()],
            body: nil, accessToken: accessToken
        )
    }

    /// Adds a title to My List, or updates it (its watched flag).
    public func saveToWatchlist(accessToken: String, item: WatchlistItem) async throws {
        _ = try await sendJSON("POST", "/user/watchlist", body: try JSONEncoder().encode(item), accessToken: accessToken)
    }

    public func removeFromWatchlist(accessToken: String, item: WatchlistItem) async throws {
        _ = try await sendJSON(
            "DELETE", "/user/watchlist",
            query: ["providerId": item.providerId, "contentId": item.contentId, "contentType": item.contentType, "updatedAt": ISODate.now()],
            body: nil, accessToken: accessToken
        )
    }
}
