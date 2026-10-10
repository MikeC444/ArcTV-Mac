import Foundation

/// A file inside a torrent.
public struct TorrentFile: Equatable, Sendable {
    public var index: Int
    public var name: String
    public var size: Int64

    public init(index: Int, name: String, size: Int64) {
        self.index = index
        self.name = name
        self.size = size
    }
}

public extension AddonStream {
    /// The magnet link for a torrent stream: its hash, a name, and the trackers the addon listed.
    var magnetURI: String? {
        guard let hash = infoHash?.trimmingCharacters(in: .whitespaces), !hash.isEmpty else { return nil }
        var text = "magnet:?xt=urn:btih:\(hash)"
        let name = behaviorHints?.filename ?? title?.split(separator: "\n").first.map(String.init)
        if let name, let encoded = name.addingPercentEncoding(withAllowedCharacters: .alphanumerics) { text += "&dn=\(encoded)" }
        var seen = Set<String>()
        for entry in sources ?? [] where entry.hasPrefix("tracker:") {
            let tracker = String(entry.dropFirst("tracker:".count))
            guard !tracker.isEmpty, seen.insert(tracker).inserted,
                  let encoded = tracker.addingPercentEncoding(withAllowedCharacters: .alphanumerics) else { continue }
            text += "&tr=\(encoded)"
        }
        return text
    }
}

/// Which file of a torrent to play.
public enum TorrentFileChoice {
    static let videoExtensions: Set<String> = ["mkv", "mp4", "m4v", "mov", "avi", "webm", "ts", "m2ts", "wmv", "flv", "mpg", "mpeg"]

    public static func isVideo(_ name: String) -> Bool {
        guard let dot = name.lastIndex(of: ".") else { return false }
        return videoExtensions.contains(name[name.index(after: dot)...].lowercased())
    }

    /// The addon's own pick when it is a video; else, for an episode, the video that names it (S01E02 or 1x02); else the biggest video.
    public static func pick(from files: [TorrentFile], hint: Int?, season: Int?, episode: Int?) -> Int? {
        let videos = files.filter { isVideo($0.name) }
        if let hint, let file = files.first(where: { $0.index == hint }), isVideo(file.name) { return file.index }
        if let season, let episode {
            let patterns = [
                String(format: "s%02de%02d", season, episode),
                String(format: "s%de%d", season, episode),
                "\(season)x\(String(format: "%02d", episode))"
            ]
            let matches = videos.filter { file in
                let lower = file.name.lowercased()
                return patterns.contains { lower.contains($0) }
            }
            if let best = matches.max(by: { $0.size < $1.size }) { return best.index }
        }
        return videos.max(by: { $0.size < $1.size })?.index
    }
}

/// An HTTP `Range` request header, as the player sends it when it seeks.
public enum ByteRange {
    /// The first and last byte to send for a file of `size` bytes, or nil when there is no usable range (send everything) or it can't be met.
    public static func parse(_ header: String?, size: Int64) -> (start: Int64, end: Int64)? {
        guard size > 0, let header, header.lowercased().hasPrefix("bytes=") else { return nil }
        let spec = header.dropFirst("bytes=".count).split(separator: ",").first.map(String.init) ?? ""
        let parts = spec.split(separator: "-", maxSplits: 1, omittingEmptySubsequences: false).map { $0.trimmingCharacters(in: .whitespaces) }
        guard parts.count == 2 else { return nil }
        if parts[0].isEmpty {
            guard let suffix = Int64(parts[1]), suffix > 0 else { return nil }
            return (max(0, size - suffix), size - 1)
        }
        guard let start = Int64(parts[0]), start < size else { return nil }
        let end = Int64(parts[1]).map { min($0, size - 1) } ?? size - 1
        return end >= start ? (start, end) : nil
    }
}
