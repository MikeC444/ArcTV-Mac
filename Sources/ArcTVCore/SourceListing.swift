import Foundation

/// What can be read off a source's release name, for the source list's badges and filters.
public extension SourceItem {
    private var text: String {
        [stream.name, stream.title, stream.description, stream.behaviorHints?.filename].compactMap { $0 }.joined(separator: " ")
    }

    /// Seeders, from the "👤 12" line torrent addons write.
    var seeders: Int? {
        guard let range = text.range(of: #"👤\s*(\d+)"#, options: .regularExpression) else { return nil }
        return Int(text[range].filter(\.isNumber))
    }

    /// REMUX, BluRay, WEB-DL, WEBRip, HDTV or DVDRip when the name says so.
    var sourceTag: String? {
        let lower = text.lowercased()
        let pairs: [(String, String)] = [
            ("remux", "REMUX"), ("blu-ray", "BluRay"), ("bluray", "BluRay"), ("bdrip", "BluRay"), ("web-dl", "WEB-DL"), ("webdl", "WEB-DL"),
            ("webrip", "WEBRip"), ("hdtv", "HDTV"), ("dvdrip", "DVDRip")
        ]
        return pairs.first { lower.contains($0.0) }?.1
    }

    /// The video format and any HDR: "HEVC  ·  HDR10+  ·  Dolby Vision".
    var codecText: String? {
        let lower = text.lowercased()
        var parts: [String] = []
        if lower.contains("av1") { parts.append("AV1") }
        else if lower.contains("hevc") || lower.contains("x265") || lower.contains("h265") || lower.contains("h.265") { parts.append("HEVC") }
        else if lower.contains("x264") || lower.contains("h264") || lower.contains("h.264") || lower.contains("avc") { parts.append("H.264") }
        if lower.contains("hdr10+") || lower.contains("hdr10plus") { parts.append("HDR10+") }
        else if lower.contains("hdr") { parts.append("HDR") }
        if lower.contains("dolby vision") || lower.range(of: #"\bdv\b"#, options: .regularExpression) != nil { parts.append("Dolby Vision") }
        return parts.isEmpty ? nil : parts.joined(separator: "  ·  ")
    }

    /// The sound: Atmos, TrueHD, DTS, DD+ and so on, when the name says so.
    var audioTag: String? {
        let lower = text.lowercased()
        let pairs: [(String, String)] = [
            ("atmos", "Atmos"), ("truehd", "TrueHD"), ("dts-hd", "DTS-HD"), ("dts", "DTS"), ("ddp", "DD+"), ("eac3", "DD+"), ("dd+", "DD+"),
            ("ac3", "Dolby Digital"), ("aac", "AAC")
        ]
        return pairs.first { lower.contains($0.0) }?.1
    }

    /// File size in bytes, from the addon's hint or the "21.3 GB" in the name.
    var sizeBytes: Int64? {
        if let bytes = stream.behaviorHints?.videoSize, bytes > 0 { return bytes }
        guard let range = text.range(of: #"(\d+(\.\d+)?)\s?(GB|MB)"#, options: [.regularExpression, .caseInsensitive]) else { return nil }
        let found = text[range].lowercased()
        let number = Double(found.filter { $0.isNumber || $0 == "." }) ?? 0
        return Int64(number * (found.contains("gb") ? 1_073_741_824 : 1_048_576))
    }
}

/// The quality pills on the source page.
public enum SourceFilter: String, CaseIterable, Identifiable, Sendable {
    case all = "All Sources", uhd = "4K", fhd = "1080p", hd = "720p", other = "Other"
    public var id: String { rawValue }

    func matches(_ quality: Quality) -> Bool {
        switch self {
        case .all: return true
        case .uhd: return quality == .p2160
        case .fhd: return quality == .p1080
        case .hd: return quality == .p720
        case .other: return quality < .p720
        }
    }
}

public enum SourceSort: String, CaseIterable, Sendable {
    case quality = "Quality", seeders = "Seeders", size = "Size"

    public var next: SourceSort {
        let all = SourceSort.allCases
        return all[(all.firstIndex(of: self)! + 1) % all.count]
    }
}

public enum SourceListing {
    /// The best source that plays straight away (the list is already best first), marked "Recommended".
    public static func recommendedID(in items: [SourceItem]) -> String? { items.first(where: \.isPlayable)?.id }

    /// The sources after filtering and sorting. Quality keeps the list's own order (direct links first, best quality first); the recommended
    /// source always stays on top.
    public static func arrange(_ items: [SourceItem], filter: SourceFilter, sort: SourceSort) -> [SourceItem] {
        let recommended = recommendedID(in: items)
        let kept = items.filter { filter.matches($0.quality) || $0.id == recommended }
        let sorted: [SourceItem]
        switch sort {
        case .quality: sorted = kept
        case .seeders: sorted = kept.enumerated().sorted { ($0.element.seeders ?? -1, -$0.offset) > ($1.element.seeders ?? -1, -$1.offset) }.map(\.element)
        case .size: sorted = kept.enumerated().sorted { ($0.element.sizeBytes ?? -1, -$0.offset) > ($1.element.sizeBytes ?? -1, -$1.offset) }.map(\.element)
        }
        guard let recommended, let top = sorted.first(where: { $0.id == recommended }) else { return sorted }
        return [top] + sorted.filter { $0.id != recommended }
    }
}
