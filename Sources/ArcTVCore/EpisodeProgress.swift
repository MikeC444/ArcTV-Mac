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

    /// Has this episode come out? An episode with no date, or one that cannot be read, counts as out; one dated after `now` has not.
    static func isOut(_ episode: EpisodeInfo, now: Date) -> Bool {
        guard let text = episode.released, !text.isEmpty else { return true }
        let plain = ISO8601DateFormatter()
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        guard let date = fractional.date(from: text) ?? plain.date(from: text) else { return true }
        return date <= now
    }

    /// The episode a show should point at once `finished` is done: the first one not yet watched after it, or, with none left after it, the first
    /// not yet watched from the start of the show. Nil when every episode that is out has been watched, which is when the show leaves Continue
    /// Watching. Season 0 (specials) and episodes that are not out yet are left out, so a show that is caught up with what has aired is finished
    /// for now. The finished episode counts as watched whatever the statuses say.
    public static func nextToWatch(seasons: [Int: [EpisodeInfo]], statuses: [String: EpisodeStatus], finished: (season: Int, episode: Int),
                                   now: Date = Date()) -> EpisodeInfo? {
        let ordered = seasons.keys.filter { $0 > 0 }.sorted().flatMap { seasons[$0] ?? [] }.filter { isOut($0, now: now) }
        let finishedKey = key(season: finished.season, episode: finished.episode)
        func done(_ episode: EpisodeInfo) -> Bool {
            guard let k = key(season: episode.season, episode: episode.episode) else { return true }
            return k == finishedKey || statuses[k]?.watched == true
        }
        let start = ordered.firstIndex { key(season: $0.season, episode: $0.episode) == finishedKey }.map { $0 + 1 } ?? 0
        return ordered[start...].first { !done($0) } ?? ordered[..<start].first { !done($0) }
    }
}

extension AuthClient {
    /// The finished and part-way episodes of one show (reads the profile's watch history).
    public func episodeStatuses(accessToken: String, contentId: String) async throws -> [String: EpisodeStatus] {
        let all = try await history(accessToken: accessToken)
        return EpisodeProgress.statuses(from: all.items, contentId: contentId)
    }
}
