import Foundation

/// Like / Not for me.
public enum Rating: String, Codable, Sendable {
    case like
    case dislike
}

public enum SignalKind: String, Sendable {
    case like, dislike, completed, watchlist
}

/// What is currently stored about one title for one profile. Built from the stores each time, never accumulated: edits and removals just work.
public struct InteractionInput: Equatable, Sendable {
    public var id: String
    public var title: String
    public var rating: Rating?
    /// Finished (a My List entry marked watched).
    public var completed: Bool
    public var inWatchlist: Bool

    public init(id: String, title: String, rating: Rating? = nil, completed: Bool = false, inWatchlist: Bool = false) {
        self.id = id
        self.title = title
        self.rating = rating
        self.completed = completed
        self.inWatchlist = inWatchlist
    }
}

public struct Interaction: Equatable, Sendable {
    public var id: String
    public var title: String
    public var kind: SignalKind
    public var weight: Double

    public init(id: String, title: String, kind: SignalKind, weight: Double) {
        self.id = id
        self.title = title
        self.kind = kind
        self.weight = weight
    }
}

/// The single strongest applicable signal for a title, or nil when it carries none. Explicit feedback comes first, so a disliked title stays
/// negative even if it was finished or saved. Opening a page, starting playback and failures are not inputs at all.
public func interactionOf(_ input: InteractionInput) -> Interaction? {
    if input.rating == .like { return Interaction(id: input.id, title: input.title, kind: .like, weight: RecommendConfig.weightLike) }
    if input.rating == .dislike { return Interaction(id: input.id, title: input.title, kind: .dislike, weight: RecommendConfig.weightDislike) }
    if input.completed { return Interaction(id: input.id, title: input.title, kind: .completed, weight: RecommendConfig.weightCompleted) }
    if input.inWatchlist { return Interaction(id: input.id, title: input.title, kind: .watchlist, weight: RecommendConfig.weightWatchlist) }
    return nil
}

/// Stored facts -> one Interaction per title, in a stable order (strongest first, then id).
public func collectInteractions(_ inputs: [InteractionInput]) -> [Interaction] {
    var byID: [String: InteractionInput] = [:]
    for input in inputs {
        if var merged = byID[input.id] {
            merged.title = input.title
            merged.rating = input.rating ?? merged.rating
            merged.completed = input.completed || merged.completed
            merged.inWatchlist = input.inWatchlist || merged.inWatchlist
            byID[input.id] = merged
        } else {
            byID[input.id] = input
        }
    }
    return byID.values.compactMap(interactionOf).sorted {
        abs($0.weight) != abs($1.weight) ? abs($0.weight) > abs($1.weight) : $0.id < $1.id
    }
}

/// What the profile's stored data says, as engine inputs: My List entries (finished or just saved), then the ratings on top.
public func interactionInputs(list: [WatchlistItem], ratings: [String: (title: String, rating: Rating)]) -> [InteractionInput] {
    var inputs: [String: InteractionInput] = [:]
    for item in list {
        inputs[item.contentId] = InteractionInput(id: item.contentId, title: item.title, completed: item.watched == true, inWatchlist: true)
    }
    for (id, entry) in ratings {
        var base = inputs[id] ?? InteractionInput(id: id, title: entry.title)
        base.rating = entry.rating
        inputs[id] = base
    }
    return Array(inputs.values)
}

/// Never recommended: finished titles, anything rated Like or Not for me (a liked title informs the picks but is never picked itself),
/// anything in Continue Watching, and titles taken out of the row by hand (kept out, but not a taste signal).
public func excludedFromPicks(list: [WatchlistItem], ratedIDs: Set<String>, continueIDs: Set<String>, dismissed: Set<String> = []) -> Set<String> {
    var ids = Set<String>()
    for item in list where item.watched == true { ids.insert(item.contentId) }
    return ids.union(ratedIDs).union(continueIDs).union(dismissed)
}

/// A short fingerprint of the preference data: it changes exactly when a recommendation could.
public func signatureOf(_ interactions: [Interaction]) -> String {
    interactions.map { "\($0.id):\($0.kind.rawValue)" }.sorted().joined(separator: "|")
}
