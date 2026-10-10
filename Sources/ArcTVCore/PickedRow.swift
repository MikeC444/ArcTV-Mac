import Foundation

/// One pick on the Home row: the title and, in a personalised row, why it is there.
public struct PickedEntry: Equatable, Identifiable, Sendable {
    public var item: MetaPreview
    public var reason: String?
    public var id: String { item.id }
}

/// The "Picked for you" row, ready to place on Home.
public struct PickedRow: Equatable, Sendable {
    public var title: String
    public var personal: Bool
    public var entries: [PickedEntry]
}

/// The row from an engine result: nil when there is nothing to show. `hiddenIDs` are titles that must not show now (rated Like or Not for me,
/// finished, or in Continue Watching) and `dismissed` those removed by hand; they are dropped at once, before any recompute, so they disappear
/// the moment they are marked.
public func pickedRow(result: EngineResult?, pool: [MetaPreview], hiddenIDs: Set<String>, dismissed: Set<String>) -> PickedRow? {
    guard let result, !result.items.isEmpty else { return nil }
    let byID = Dictionary(pool.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
    let personal = result.isPersonal
    let entries: [PickedEntry] = result.items.compactMap { pick in
        guard let item = byID[pick.id], !hiddenIDs.contains(pick.id), !dismissed.contains(pick.id) else { return nil }
        return PickedEntry(item: item, reason: personal ? pick.reason : nil)
    }
    if entries.isEmpty { return nil }
    return PickedRow(title: personal ? RecommendConfig.pickedRowTitle : RecommendConfig.popularRowTitle,
                     personal: personal, entries: Array(entries.prefix(RecommendConfig.maxResults)))
}

/// Titles taken out of the row by hand: each stays out for `pickedDismissDays` days, then the algorithm decides again.
public enum PickedDismissals {
    public static var window: TimeInterval { TimeInterval(RecommendConfig.pickedDismissDays) * 24 * 3600 }

    /// The ids still out of the row at `now`.
    public static func active(_ removed: [String: Date], now: Date = Date()) -> Set<String> {
        Set(removed.filter { now.timeIntervalSince($0.value) < window }.keys)
    }

    /// Only the removals that still count, newest wins when the same title appears twice.
    public static func merged(_ local: [String: Date], with server: [PickedDismissal], now: Date = Date()) -> [String: Date] {
        var out = local.filter { now.timeIntervalSince($0.value) < window }
        for item in server {
            guard let at = ISODate.date(from: item.dismissedAt), now.timeIntervalSince(at) < window else { continue }
            if (out[item.contentId] ?? .distantPast) < at { out[item.contentId] = at }
        }
        return out
    }
}
