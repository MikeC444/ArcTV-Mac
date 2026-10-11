import Foundation

/// A debrid service's short code as the addon writes it in the stream name ("RD"), with whether it already has the file stored.
public struct DebridTag: Equatable, Sendable {
    public var service: String
    public var cached: Bool

    /// "Cached on Real-Debrid", or "Not cached: may take a while to start" for a file the service still has to fetch.
    public var label: String {
        cached ? "Cached on \(DownloadLabels.serviceName(service))" : "Not cached: may take a while to start"
    }
}

/// What the Download panel says about a source, read from its release name: the kind of release, HDR, codec, cached state and a size warning.
/// The same rules as the web and phone apps.
public enum DownloadLabels {
    private static let serviceNames: [String: String] = [
        "RD": "Real-Debrid", "AD": "AllDebrid", "PM": "Premiumize", "DL": "Debrid-Link", "TB": "TorBox"
    ]

    public static func serviceName(_ code: String) -> String { serviceNames[code.uppercased()] ?? code.uppercased() }

    private static func text(_ item: SourceItem) -> String {
        [item.headline, item.stream.name, item.stream.behaviorHints?.filename].compactMap { $0 }.joined(separator: " ")
    }

    private static func matches(_ pattern: String, in text: String) -> Bool {
        text.range(of: pattern, options: [.regularExpression, .caseInsensitive]) != nil
    }

    /// "UHD Blu-ray REMUX", "4K WEB-DL", "Blu-ray", "HDTV" ...; the quality label when the name says nothing more.
    public static func kind(_ item: SourceItem) -> String {
        let name = text(item)
        let uhd = item.quality == .p2160
        if matches("remux", in: name) { return (uhd ? "UHD " : "") + "Blu-ray REMUX" }
        if matches("blu-?ray|bdrip|brrip|\\bbd(25|50)?\\b", in: name) { return (uhd ? "UHD " : "") + "Blu-ray" }
        if matches("web-?dl|web-?rip|\\bweb\\b", in: name) { return (uhd ? "4K " : "") + "WEB-DL" }
        if matches("hdtv", in: name) { return "HDTV" }
        if matches("dvd", in: name) { return "DVD" }
        if matches("\\b(cam|hdcam|ts|hdts|telesync)\\b", in: name) { return "Camera recording" }
        return item.quality.label
    }

    /// "Dolby Vision" or "HDR" when the release's name says so.
    public static func hdr(_ item: SourceItem) -> String? {
        let name = text(item)
        if matches("dolby[ ._-]?vision|\\bdovi\\b|\\bDV\\b", in: name) { return "Dolby Vision" }
        if matches("\\bhdr(10\\+?)?\\b", in: name) { return "HDR" }
        return nil
    }

    /// "AV1", "HEVC" or "H.264" when the release's name says so.
    public static func codec(_ item: SourceItem) -> String? {
        let name = text(item)
        if matches("\\bav1\\b", in: name) { return "AV1" }
        if matches("hevc|h\\.?265|x265", in: name) { return "HEVC" }
        if matches("\\bavc\\b|h\\.?264|x264", in: name) { return "H.264" }
        return nil
    }

    /// Read from the tag addons put at the start of a stream's name: "[RD+] ..." (stored) or "[RD download] ..." (the service has to fetch it first).
    public static func debrid(_ item: SourceItem) -> DebridTag? {
        guard let name = item.stream.name,
              let regex = try? NSRegularExpression(pattern: #"^\s*\[\s*([A-Za-z]{2,3})\s*(\+|download)\s*\]"#, options: [.caseInsensitive]),
              let match = regex.firstMatch(in: name, range: NSRange(name.startIndex..., in: name)),
              let service = Range(match.range(at: 1), in: name), let mark = Range(match.range(at: 2), in: name) else { return nil }
        return DebridTag(service: String(name[service]).uppercased(), cached: name[mark] == "+")
    }

    /// A 1080p or 4K file under this size is almost never a real copy (a stub, a sample or a mislabelled file).
    public static let unusuallySmallBytes: Int64 = 150_000_000

    public static func isUnusuallySmall(_ item: SourceItem) -> Bool {
        guard let bytes = item.stream.behaviorHints?.videoSize, bytes > 0 else { return false }
        return (item.quality == .p2160 || item.quality == .p1080) && bytes < unusuallySmallBytes
    }
}
