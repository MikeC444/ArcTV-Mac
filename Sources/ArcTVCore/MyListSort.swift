import Foundation

/// How My List is ordered (the web app's sort drop-down).
public enum ListSort: String, CaseIterable, Identifiable, Sendable {
    case recent = "Recently Added"
    case title = "A–Z"
    case highestRated = "Highest Rated"
    case newest = "Newest"

    public var id: String { rawValue }

    /// `items` come newest-added first, as the account sends them.
    public func apply(_ items: [WatchlistItem]) -> [WatchlistItem] {
        switch self {
        case .recent: return items
        case .title: return items.sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
        case .highestRated: return items.sorted { ($0.rating ?? -1) > ($1.rating ?? -1) }
        case .newest: return items.sorted { ($0.year ?? -1) > ($1.year ?? -1) }
        }
    }
}
