import Foundation

public extension MetaDetail {
    /// The episode after this one: the next in the same season, else the first of the next season. Season 0 (specials) is skipped.
    func episode(after season: Int, _ episode: Int) -> EpisodeInfo? {
        let numbers = seasonNumbers
        guard let index = numbers.firstIndex(of: season) else { return nil }
        let inSeason = seasons[season] ?? []
        if let next = inSeason.first(where: { ($0.episode ?? 0) > episode }) { return next }
        for later in numbers[(index + 1)...] {
            if let first = seasons[later]?.first { return first }
        }
        return nil
    }
}

/// How far ahead of the picture a torrent is fetched (Settings > Player).
public enum TorrentBuffer: String, CaseIterable, Identifiable, Sendable {
    case small = "Small", normal = "Normal", large = "Large"
    public var id: String { rawValue }

    /// What must have arrived before the video starts.
    public var startBytes: Int64 {
        switch self {
        case .small: return 3 * 1_048_576
        case .normal: return 6 * 1_048_576
        case .large: return 16 * 1_048_576
        }
    }

    /// How many pieces after the playing spot are asked for first.
    public var piecesAhead: Int {
        switch self {
        case .small: return 12
        case .normal: return 24
        case .large: return 64
        }
    }

    public var detail: String {
        switch self {
        case .small: return "Starts soonest; may stall on slow torrents."
        case .normal: return "A good balance."
        case .large: return "Rides out slow patches; takes longer to start and uses more data."
        }
    }

    public static let key = "ArcTVTorrentBuffer"
    public static var current: TorrentBuffer { UserDefaults.standard.string(forKey: key).flatMap(TorrentBuffer.init(rawValue:)) ?? .normal }
}

/// The most disk space a torrent may use (the file being watched is kept until you stop).
public enum TorrentStorage {
    public static let options: [Int] = [5, 10, 20, 50, 0] // gigabytes; 0 is no limit
    public static let key = "ArcTVTorrentStorageGB"
    public static var currentGB: Int { UserDefaults.standard.object(forKey: key) as? Int ?? 50 }

    public static func label(_ gigabytes: Int) -> String { gigabytes == 0 ? "No limit" : "\(gigabytes) GB" }

    /// True when a file of `size` bytes is allowed under `gigabytes` (0 means anything).
    public static func allows(size: Int64, gigabytes: Int) -> Bool {
        gigabytes == 0 || size <= Int64(gigabytes) * 1_073_741_824
    }
}
