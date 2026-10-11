import Foundation

/// What the account's history says about one episode: finished, or how far in it got (0 to 1).
public struct EpisodeStatus: Equatable, Sendable {
    public var watched: Bool
    public var fraction: Double

    public init(watched: Bool, fraction: Double) {
        self.watched = watched
        self.fraction = fraction
    }
}

public enum EpisodeProgress {
    /// How long an episode is taken to be when it is marked watched and nothing says (the history wants a length).
    public static let fallbackRuntimeMinutes = 45

    /// The key an episode is tracked under: "season:episode".
    public static func key(season: Int?, episode: Int?) -> String? {
        guard let season, let episode else { return nil }
        return "\(season):\(episode)"
    }

    /// The finished and part-way episodes of one show, from the watch history (one row per episode). A finished episode is watched; otherwise the
    /// fraction is how far in it got, and an episode that was never started has no entry.
    public static func statuses(from history: [HistoryItem], contentId: String) -> [String: EpisodeStatus] {
        var result: [String: EpisodeStatus] = [:]
        for row in history where row.contentId == contentId && row.contentType == "TV_SHOW" {
            guard let key = key(season: row.seasonNumber, episode: row.episodeNumber) else { continue }
            if row.completed {
                result[key] = EpisodeStatus(watched: true, fraction: 1)
            } else if row.durationMs > 0, row.positionMs > 0 {
                result[key] = EpisodeStatus(watched: false, fraction: min(1, max(0, Double(row.positionMs) / Double(row.durationMs))))
            }
        }
        return result
    }

    /// The episode after the furthest one watched (a season caught up moves on to the next season); nil when nothing is watched or the last
    /// episode is the furthest, so the caller falls back to the first. Season 0 (specials) is left out, as on the title page.
    public static func nextEpisode(seasons: [Int: [EpisodeInfo]], statuses: [String: EpisodeStatus]) -> EpisodeInfo? {
        let ordered = seasons.keys.filter { $0 > 0 }.sorted().flatMap { seasons[$0] ?? [] }
        guard let last = ordered.lastIndex(where: { episode in
            key(season: episode.season, episode: episode.episode).flatMap { statuses[$0]?.watched } == true
        }) else { return nil }
        return ordered.indices.contains(last + 1) ? ordered[last + 1] : nil
    }
}

extension AuthClient {
    /// The finished and part-way episodes of one show (reads the profile's watch history).
    public func episodeStatuses(accessToken: String, contentId: String) async throws -> [String: EpisodeStatus] {
        let all = try await history(accessToken: accessToken)
        return EpisodeProgress.statuses(from: all.items, contentId: contentId)
    }
}
