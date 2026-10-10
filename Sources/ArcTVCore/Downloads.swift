import Foundation

/// Choosing and naming what to save from a title's page (an Arc TV Plus feature).
public enum DownloadChoices {
    /// The sources that are a plain web file (what a debrid service gives), best quality first and, within a quality, the smallest file first.
    public static func sorted(_ items: [SourceItem]) -> [SourceItem] {
        items.filter(\.isPlayable).enumerated().sorted { left, right in
            let a = left.element, b = right.element
            if a.quality != b.quality { return a.quality > b.quality }
            let sizeA = a.sizeBytes ?? Int64.max, sizeB = b.sizeBytes ?? Int64.max
            if sizeA != sizeB { return sizeA < sizeB }
            return left.offset < right.offset
        }.map(\.element)
    }

    static let extensions: Set<String> = ["mkv", "mp4", "m4v", "mov", "avi", "webm", "ts", "wmv"]

    /// A file name that is safe on disk: the release name without characters a file name can't hold, with the link's own extension (mkv if none).
    public static func fileName(release: String, url: URL) -> String {
        var base = release.components(separatedBy: CharacterSet(charactersIn: "/\\:?*\"<>|\n\r")).joined(separator: " ")
        base = base.split(separator: " ", omittingEmptySubsequences: true).joined(separator: " ").trimmingCharacters(in: CharacterSet(charactersIn: ". "))
        if base.isEmpty { base = "Arc TV download" }
        if base.count > 150 { base = String(base.prefix(150)).trimmingCharacters(in: .whitespaces) }
        let dotted = (base as NSString).pathExtension.lowercased()
        if extensions.contains(dotted) { return base }
        let fromLink = url.pathExtension.lowercased()
        return base + "." + (extensions.contains(fromLink) ? fromLink : "mkv")
    }
}
