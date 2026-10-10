import Foundation

/// Keeping Home fresh without making it irrelevant. A catalogue row that always shows the first 100 titles shows the same films to everyone, every
/// day. Instead each row draws from a few pages deep into the same ranking (so everything is still popular / new / well rated), and the order within
/// it is a gentle, seeded shuffle that favours the higher ranks. The seed is the account plus the day, so a row is steady while you use the app and
/// different tomorrow. A port of the web app's `domain/homeVariety.ts`.
public enum HomeVariety {
    /// A stable 32-bit number from text (FNV-1a), used to seed the shuffles.
    public static func hashSeed(_ text: String) -> UInt32 {
        var hash: UInt32 = 0x811c9dc5
        for unit in text.utf16 {
            hash ^= UInt32(unit)
            hash = hash &* 0x01000193
        }
        return hash
    }

    /// Today's date (local) as YYYY-MM-DD, so the rows change at the person's own midnight.
    public static func dayStamp(_ now: Date = Date()) -> String {
        let parts = Calendar.current.dateComponents([.year, .month, .day], from: now)
        return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }

    /// Which catalogue page (0 = the top 100) a row reads today. `weights` is the chance of each page; the first is the likeliest.
    public static func pickPage(seed: String, rowKey: String, weights: [Double]) -> Int {
        let random = SeededRandom(seed: Int(hashSeed("\(seed)|\(rowKey)|page"))).next()
        let total = weights.reduce(0, +)
        var acc = 0.0
        for (index, weight) in weights.enumerated() {
            acc += weight / total
            if random < acc { return index }
        }
        return weights.count - 1
    }

    /// A gentle shuffle: every item keeps a chance to land near the top but a better-ranked one is likelier to. Weight falls with rank
    /// (1 / (1 + rank / 25)), and the order is a weighted random draw (Efraimidis-Spirakis keys) seeded by `seed` + `rowKey`.
    public static func varyOrder<T>(_ items: [T], seed: String, rowKey: String) -> [T] {
        let random = SeededRandom(seed: Int(hashSeed("\(seed)|\(rowKey)|order")))
        return items.enumerated()
            .map { rank, item in (item: item, key: pow(random.next(), 1 / (1 / (1 + Double(rank) / 25)))) }
            .sorted { $0.key > $1.key }
            .map(\.item)
    }

    /// The genres Home shows as rows, in this order: wide appeal. Every other genre stays on the Movies and TV Shows pages.
    public static let homeGenres = ["Action", "Comedy", "Drama", "Thriller", "Horror", "Sci-Fi", "Crime", "Animation", "Documentary"]

    /// Which of an addon's declared genres become Home rows: the curated ones it declares, in curated order (case-insensitive).
    public static func homeGenres(declared: [String]) -> [String] {
        var byLower: [String: String] = [:]
        for genre in declared where byLower[genre.lowercased()] == nil { byLower[genre.lowercased()] = genre }
        return homeGenres.compactMap { byLower[$0.lowercased()] }
    }
}
