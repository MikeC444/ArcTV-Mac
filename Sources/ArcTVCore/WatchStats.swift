import Foundation

/// One row of the watch history (`GET /user/history`): a movie or an episode, the furthest point reached and when it was last watched.
public struct HistoryItem: Codable, Equatable, Sendable {
    public var providerId: String
    public var contentId: String
    public var contentType: String
    public var seasonNumber: Int?
    public var episodeNumber: Int?
    public var title: String
    public var posterUrl: String?
    public var positionMs: Int64
    public var durationMs: Int64
    public var completed: Bool
    /// Marked watched by hand rather than played (the account records this); absent from an older backend.
    public var markedManually: Bool?
    public var watchedAt: String

    public init(providerId: String = "p", contentId: String, contentType: String, seasonNumber: Int? = nil, episodeNumber: Int? = nil, title: String = "t",
                posterUrl: String? = nil, positionMs: Int64, durationMs: Int64, completed: Bool, markedManually: Bool? = nil, watchedAt: String) {
        self.providerId = providerId
        self.contentId = contentId
        self.contentType = contentType
        self.seasonNumber = seasonNumber
        self.episodeNumber = episodeNumber
        self.title = title
        self.posterUrl = posterUrl
        self.positionMs = positionMs
        self.durationMs = durationMs
        self.completed = completed
        self.markedManually = markedManually
        self.watchedAt = watchedAt
    }

    /// Whether this row is only a tick the person pressed ("mark as watched" on an episode or a season) and not something that was played. New rows
    /// say so themselves. Older ones were written with the show's listed runtime as both the position and the length, in whole minutes, which real
    /// playback (a length in milliseconds, from the file) essentially never is, so those are recognised that way.
    public var isMarkedByHand: Bool {
        if markedManually == true { return true }
        return contentType == "TV_SHOW" && completed && durationMs > 0 && positionMs == durationMs && durationMs % 60_000 == 0
    }

    /// How much of this row counts as watched: all of it when finished, otherwise how far in it got (never more than its length).
    public var watchedMs: Int64 {
        let position = max(0, positionMs)
        if durationMs > 0 { return completed ? durationMs : min(position, durationMs) }
        return position
    }
}

/// One title's share of the history, for "Most watched".
public struct TopTitle: Equatable, Sendable {
    public var title: String
    public var posterUrl: String?
    public var type: String
    public var watchedMs: Int64
    /// Episodes of a show watched (1 for a movie).
    public var parts: Int
}

/// What the recap card says, worked out from the stats.
public struct StatsRecapText: Equatable, Sendable {
    public var heading: String
    /// The big number: "126 hours".
    public var hours: String
    public var lines: [String]
}

/// "Your stats": what the account's watch history says about how it is used. The history holds one row per movie or episode, so a title watched
/// twice counts once, on the day it was last watched. A port of the web app's `domain/stats.ts`.
public struct WatchStats: Equatable, Sendable {
    public static let heatDays = 91
    public static let weekdays = ["Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday", "Sunday"]

    public var isEmpty = true
    public var totalMs: Int64 = 0
    public var last7DaysMs: Int64 = 0
    public var last30DaysMs: Int64 = 0
    /// The 7 days before the last 7 (to say whether this week was busier or quieter).
    public var prev7DaysMs: Int64 = 0
    /// The 30 days before the last 30 (the same comparison for the month).
    public var prev30DaysMs: Int64 = 0
    public var movieMs: Int64 = 0
    public var showMs: Int64 = 0
    public var activeDays = 0
    public var avgPerActiveDayMs: Int64 = 0
    /// Time watched per local day for the last `heatDays` days, oldest first (the last entry is today).
    public var dailyMs = [Int64](repeating: 0, count: WatchStats.heatDays)
    public var titlesWatched = 0
    public var moviesFinished = 0
    public var episodesWatched = 0
    public var showsWatched = 0
    /// Milliseconds watched per weekday, Monday first.
    public var byWeekdayMs = [Int64](repeating: 0, count: 7)
    /// Index into `byWeekdayMs` (Monday = 0) of the busiest day, or nil with no history.
    public var busiestWeekday: Int?
    public var streakDays = 0
    public var longestStreakDays = 0
    public var firstWatchedAt: Date?
    /// The movie and the show with the most time watched, or nil when there is none of that kind.
    public var topMovie: TopTitle?
    public var topShow: TopTitle?

    /// The history from the moment Your stats was last reset onwards (all of it when it never was, or the time cannot be read).
    public static func afterReset(_ items: [HistoryItem], resetAt: String?) -> [HistoryItem] {
        guard let resetAt, let from = ISODate.date(from: resetAt) else { return items }
        return items.filter { item in ISODate.date(from: item.watchedAt).map { $0 >= from } ?? false }
    }

    public static func compute(_ items: [HistoryItem], now: Date = Date(), calendar: Calendar = .current) -> WatchStats {
        var stats = WatchStats()
        // Only what was played counts: a tick pressed by hand is not time watched, an episode watched, a day on the streak or anything else here.
        let valid = items.compactMap { item -> (HistoryItem, Date)? in
            item.isMarkedByHand ? nil : ISODate.date(from: item.watchedAt).map { (item, $0) }
        }
        if valid.isEmpty { return stats }
        stats.isEmpty = false
        let day: TimeInterval = 24 * 3600
        func dayNumber(_ date: Date) -> Int {
            let parts = calendar.dateComponents([.year, .month, .day], from: date)
            var utc = Calendar(identifier: .gregorian)
            utc.timeZone = TimeZone(identifier: "UTC")!
            return Int((utc.date(from: parts) ?? date).timeIntervalSince1970 / day)
        }
        let today = dayNumber(now)
        var days = Set<Int>()
        var titles = Set<String>()
        var shows = Set<String>()
        var first = Date.distantFuture
        var perTitle: [String: TopTitle] = [:]
        for (item, at) in valid {
            let ms = item.watchedMs
            let age = now.timeIntervalSince(at)
            stats.totalMs += ms
            if age <= 7 * day { stats.last7DaysMs += ms }
            if age <= 30 * day { stats.last30DaysMs += ms }
            if age > 7 * day, age <= 14 * day { stats.prev7DaysMs += ms }
            if age > 30 * day, age <= 60 * day { stats.prev30DaysMs += ms }
            if item.contentType == "MOVIE" { stats.movieMs += ms } else { stats.showMs += ms }
            let ago = today - dayNumber(at)
            if ago >= 0, ago < heatDays { stats.dailyMs[heatDays - 1 - ago] += ms }
            first = min(first, at)
            // `weekday` is Sunday = 1; the week here starts on Monday.
            stats.byWeekdayMs[(calendar.component(.weekday, from: at) + 5) % 7] += ms
            if ms > 0 { days.insert(dayNumber(at)) }
            let key = "\(item.providerId)|\(item.contentId)|\(item.contentType)"
            titles.insert(key)
            var entry = perTitle[key] ?? TopTitle(title: item.title, posterUrl: item.posterUrl, type: item.contentType, watchedMs: 0, parts: 0)
            entry.watchedMs += ms
            entry.parts += ms > 0 ? 1 : 0
            perTitle[key] = entry
            if item.contentType == "MOVIE" {
                if item.completed { stats.moviesFinished += 1 }
            } else {
                shows.insert(key)
                if item.completed { stats.episodesWatched += 1 }
            }
        }
        stats.titlesWatched = titles.count
        stats.showsWatched = shows.count
        stats.activeDays = days.count
        stats.avgPerActiveDayMs = days.isEmpty ? 0 : stats.totalMs / Int64(days.count)
        let busiest = stats.byWeekdayMs.max() ?? 0
        stats.busiestWeekday = busiest > 0 ? stats.byWeekdayMs.firstIndex(of: busiest) : nil

        let ordered = days.sorted()
        var run = 0
        for (index, value) in ordered.enumerated() {
            run = index > 0 && value == ordered[index - 1] + 1 ? run + 1 : 1
            stats.longestStreakDays = max(stats.longestStreakDays, run)
        }
        var cursor = days.contains(today) ? today : today - 1
        while days.contains(cursor) {
            stats.streakDays += 1
            cursor -= 1
        }
        stats.firstWatchedAt = first
        let ranked = perTitle.values.filter { $0.watchedMs > 0 }.sorted { $0.watchedMs != $1.watchedMs ? $0.watchedMs > $1.watchedMs : $0.title < $1.title }
        stats.topMovie = ranked.first { $0.type == "MOVIE" }
        stats.topShow = ranked.first { $0.type != "MOVIE" }
        return stats
    }

    /// "126 hours" / "1 hour 5 minutes" / "40 minutes" / "under a minute", for the big numbers.
    public static func duration(_ ms: Int64) -> String {
        let totalMinutes = Int(max(0, ms) / 60_000)
        if totalMinutes < 1 { return ms > 0 ? "under a minute" : "0 minutes" }
        let hours = totalMinutes / 60
        let minutes = totalMinutes % 60
        let h = "\(hours) \(hours == 1 ? "hour" : "hours")"
        let m = "\(minutes) \(minutes == 1 ? "minute" : "minutes")"
        if hours == 0 { return m }
        // Past a day's worth the minutes are noise.
        return hours >= 24 || minutes == 0 ? h : "\(h) \(m)"
    }

    /// "45m" / "3h" / "12.5h" for a bar label; empty for nothing.
    public static func short(_ ms: Int64) -> String {
        if ms <= 0 { return "" }
        let minutes = Int((Double(ms) / 60_000).rounded())
        if minutes < 60 { return "\(max(1, minutes))m" }
        let hours = Double(ms) / 3_600_000
        if hours < 10 {
            let tenth = (hours * 10).rounded() / 10
            return tenth == tenth.rounded() ? "\(Int(tenth))h" : "\(tenth)h"
        }
        return "\(Int(hours.rounded()))h"
    }

    /// What to say under the streak: how far it is from the best one. Nil when there is nothing to say.
    public static func streakNote(streak: Int, longest: Int) -> String? {
        if longest <= 0 { return nil }
        if streak <= 0 { return "best \(longest)" }
        if streak >= longest { return streak == longest ? "your best" : nil }
        let left = longest - streak
        return "best \(longest) \u{00B7} \(left) \(left == 1 ? "day" : "days") to match it"
    }

    /// "You watch most on Mondays." for the weekday bars; nil with no history.
    public static func weekdayLine(_ busiest: Int?) -> String? {
        busiest.map { "You watch most on \(weekdays[$0])s." }
    }

    /// The recap card's words; nil when there is nothing to recap yet.
    public var recap: StatsRecapText? {
        if isEmpty || totalMs <= 0 { return nil }
        var lines: [String] = []
        if let show = topShow { lines.append("Most watched show: \(show.title)") }
        if let movie = topMovie { lines.append("Most watched movie: \(movie.title)") }
        if longestStreakDays >= 2 { lines.append("Longest streak: \(longestStreakDays) days") }
        var counts: [String] = []
        if moviesFinished > 0 { counts.append("\(moviesFinished) \(moviesFinished == 1 ? "movie" : "movies") finished") }
        if episodesWatched > 0 { counts.append("\(episodesWatched) \(episodesWatched == 1 ? "episode" : "episodes") watched") }
        if !counts.isEmpty { lines.append(counts.joined(separator: " \u{00B7} ")) }
        return StatsRecapText(heading: "My Arc TV recap", hours: WatchStats.duration(totalMs), lines: lines)
    }

    /// This week against the one before: nil when there is nothing to compare.
    public static func weekChange(last7: Int64, prev7: Int64) -> (direction: String, percent: Int)? {
        guard prev7 > 0 else { return nil }
        let percent = Int((Double(last7 - prev7) / Double(prev7) * 100).rounded())
        return (percent > 0 ? "up" : percent < 0 ? "down" : "same", abs(percent))
    }

    /// The activity grid's cells, column by column (Monday first), padded to a Monday: nil for the blank cells that start the first week.
    public struct HeatCell: Equatable, Sendable {
        public var ms: Int64?
        public var level: Int
        public var label: String
        /// Month of the day, 0 to 11; nil for the blank cells.
        public var month: Int? = nil
    }

    public static func heatCells(_ dailyMs: [Int64], now: Date = Date(), calendar: Calendar = .current) -> [HeatCell] {
        let maxMs = dailyMs.max() ?? 0
        let start = calendar.startOfDay(for: calendar.date(byAdding: .day, value: -(dailyMs.count - 1), to: now) ?? now)
        let pad = (calendar.component(.weekday, from: start) + 5) % 7
        var cells = [HeatCell](repeating: HeatCell(ms: nil, level: 0, label: ""), count: pad)
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.setLocalizedDateFormatFromTemplate("EEEdMMM")
        for (index, ms) in dailyMs.enumerated() {
            let date = calendar.date(byAdding: .day, value: index, to: start) ?? start
            let level = ms <= 0 || maxMs <= 0 ? 0 : min(4, max(1, Int((Double(ms) / Double(maxMs) * 4).rounded(.up))))
            cells.append(HeatCell(ms: ms, level: level, label: formatter.string(from: date), month: calendar.component(.month, from: date) - 1))
        }
        return cells
    }

    /// The month names to print above the activity grid, one per week column: the month's short name where a new month starts and an empty string
    /// elsewhere. The first column is only named when the next column is not already a new month, so two names never sit side by side.
    public static func heatMonthLabels(_ cells: [HeatCell], symbols: [String] = DateFormatter().shortMonthSymbols) -> [String] {
        let columns = (cells.count + 6) / 7
        func month(of column: Int) -> Int? {
            let start = column * 7
            guard start < cells.count else { return nil }
            return cells[start..<min(start + 7, cells.count)].compactMap(\.month).first
        }
        var labels: [String] = []
        var previous: Int?
        for column in 0..<columns {
            let current = month(of: column)
            let isNew = current != nil && current != previous
            let next = month(of: 1)
            let crowded = column == 0 && next != nil && next != current
            labels.append(isNew && !crowded && symbols.indices.contains(current!) ? symbols[current!] : "")
            if current != nil { previous = current }
        }
        return labels
    }
}

private struct HistoryPage: Decodable {
    var items: [HistoryItem]
}

extension AuthClient {
    /// The profile's whole watch history, newest first, read a page at a time (a very long history is read up to 5,000 rows).
    public func history(accessToken: String) async throws -> (items: [HistoryItem], truncated: Bool) {
        let pageSize = 200
        var items: [HistoryItem] = []
        var before: String?
        for _ in 0..<25 {
            var query = ["limit": String(pageSize)]
            if let before { query["before"] = before }
            let data = try await sendJSON("GET", "/user/history", query: query, body: nil, accessToken: accessToken)
            guard let page = try? JSONDecoder().decode(HistoryPage.self, from: data) else { throw APIError.unreadable }
            items += page.items.filter { $0.contentType == "MOVIE" || $0.contentType == "TV_SHOW" }
            if page.items.count < pageSize { return (items, false) }
            before = page.items.last?.watchedAt
        }
        return (items, true)
    }
}
