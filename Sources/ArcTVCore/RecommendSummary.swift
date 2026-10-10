import Foundation

/// What Settings > Recommendations says about a profile's taste: how many titles feed it and how many points each kind of title adds. Counted the
/// way the engine counts: a rated title counts once, by its rating, and a title that is only saved or finished counts for the smaller amount.
/// The points are weights, not a score.
public struct RecommendationSummary: Equatable, Sendable {
    public var likes: Int
    public var dislikes: Int
    /// Titles in My List that are finished and not rated.
    public var finished: Int
    /// Titles in My List that are not finished and not rated.
    public var saved: Int

    public init(likes: Int, dislikes: Int, finished: Int, saved: Int) {
        self.likes = likes
        self.dislikes = dislikes
        self.finished = finished
        self.saved = saved
    }

    public var likePoints: Int { likes * Int(RecommendConfig.weightLike) }
    public var dislikePoints: Int { dislikes * Int(RecommendConfig.weightDislike) }
    public var listPoints: Int { finished * Int(RecommendConfig.weightCompleted) + saved * Int(RecommendConfig.weightWatchlist) }

    /// Titles that give the engine a signal at all.
    public var signals: Int { likes + dislikes + finished + saved }

    /// More than the engine looks at: only its strongest signals shape the picks.
    public var overLimit: Bool { signals > RecommendConfig.interactionDetailFetchLimit }

    /// Personal picks start once there are enough signals and at least one is positive; until then Home shows popular titles.
    public var ready: Bool { signals >= RecommendConfig.minInteractionsForPersonalisation && likes + finished + saved > 0 }
}

public func summarizeRecommendations(ratings: [String: Rating], list: [WatchlistItem]) -> RecommendationSummary {
    let unrated = list.filter { ratings[$0.contentId] == nil }
    return RecommendationSummary(
        likes: ratings.values.filter { $0 == .like }.count,
        dislikes: ratings.values.filter { $0 == .dislike }.count,
        finished: unrated.filter { $0.watched == true }.count,
        saved: unrated.filter { $0.watched != true }.count
    )
}

/// "+20 points", "−15 points", "0 points", "+1 point".
public func pointsLabel(_ points: Int) -> String {
    let sign = points > 0 ? "+" : (points < 0 ? "−" : "")
    let n = abs(points)
    return "\(sign)\(n) \(n == 1 ? "point" : "points")"
}
