import Foundation

/// "Picked for you": every number that shapes the recommendation lives here, named, so tuning never means hunting through logic. These are the
/// Fire TV app's values (which come from the web app), so every Arc TV app ranks the same way. The score is an internal ranking value only: it
/// is not the IMDb rating, a star rating, or a probability that someone will enjoy a title.
public enum RecommendConfig {
    /// What one title says about a profile's taste. The strongest applicable signal wins; explicit feedback always takes precedence.
    public static let weightLike = 5.0
    public static let weightDislike = -5.0
    /// Finished, with no explicit feedback.
    public static let weightCompleted = 2.0
    /// On My List, with no explicit feedback and not finished.
    public static let weightWatchlist = 1.0

    /// How the three similarities combine. A category with no usable data is left out and the rest are renormalised.
    public static let categoryWeightGenre = 0.6
    public static let categoryWeightDirector = 0.25
    public static let categoryWeightCast = 0.15

    public static let maxResults = 20

    /// Composition: the best `rotationAnchors` picks always stay; the other places follow the profile's genre split, drawn from each genre's other
    /// scored candidates that reach `rotationFloor` of that genre's best. A pick shown last time counts `rotationRepeatWeight` times as much.
    public static let rotationAnchors = 5
    public static let rotationFloor = 0.6
    public static let rotationRepeatWeight = 0.15

    /// Shortlist: every genre the profile likes gets at least `shortlistGenreMin` candidates, out of a budget shared by taste share.
    public static let shortlistGenreBudget = 36
    public static let shortlistGenreMin = 4

    /// Diversity: one title of the profile's can be the stated reason for at most this many picks.
    public static let maxPicksPerSource = 3
    /// Shortlist: this many by overall genre match, the rest round-robin from the best matches of each of the profile's own titles.
    public static let shortlistByScore = 20
    /// How many of the profile's own titles take a turn in the round-robin (strongest signals first).
    public static let shortlistSourceTitles = 12

    /// Fewer than this many signals (with at least one positive) and the row is the labelled popular fallback instead.
    public static let minInteractionsForPersonalisation = 3

    /// Billing-order cast beyond this adds noise, not taste.
    public static let castFeatureLimit = 12

    /// Network budget: how many candidates get a detail lookup per refresh, how many of the profile's own titles are looked up, and how many run at once.
    public static let candidateDetailFetchLimit = 60
    public static let interactionDetailFetchLimit = 60
    public static let detailFetchConcurrency = 4

    /// Cache of title features (genres / directors / cast) so a refresh rarely touches the network.
    public static let featureCacheMaxEntries = 800
    public static let featureCacheTTL: TimeInterval = 30 * 24 * 3600

    /// How long a title removed from "Picked for you" stays out of the row; after that the algorithm decides again.
    public static let pickedDismissDays = 5
    public static let pickedRowTitle = "Picked for you · ArcTV Plus"
    public static let popularRowTitle = "Popular movies, not personalised yet · ArcTV Plus"
}
