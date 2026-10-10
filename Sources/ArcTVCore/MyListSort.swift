import Foundation

/// How My List is ordered (the web app's sort drop-down).
public enum ListSort: String, CaseIterable, Identifiable, Sendable {
    case recent = "Recently Added"
    case title = "A–Z"
    case highestRated = "Highest Rated"
    case newest = "Newest"

    public var id: String { rawValue }

    /// `items` come oldest-added first, as the account sends them. Every order starts from newest-added first, so titles that tie (same rating, same
    /// year) stay in recently-added order, as on the other apps.
    public func apply(_ items: [WatchlistItem]) -> [WatchlistItem] {
        let recent = Array(items.reversed())
        switch self {
        case .recent: return recent
        case .title: return recent.sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
        case .highestRated: return recent.sorted { ($0.rating ?? -1) > ($1.rating ?? -1) }
        case .newest: return recent.sorted { ($0.year ?? -1) > ($1.year ?? -1) }
        }
    }
}
