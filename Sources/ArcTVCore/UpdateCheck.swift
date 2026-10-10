import Foundation

/// A published version of the app on GitHub.
public struct ReleaseInfo: Equatable, Sendable {
    public var version: String
    public var notes: String
    public var pageURL: URL?
    public var downloadURL: URL?

    public init(version: String, notes: String, pageURL: URL?, downloadURL: URL?) {
        self.version = version
        self.notes = notes
        self.pageURL = pageURL
        self.downloadURL = downloadURL
    }
}

/// What a check for updates found.
public enum UpdateResult: Equatable, Sendable {
    case upToDate(latest: String?)
    case available(ReleaseInfo)
}

public enum UpdateCheck {
    public static let latestReleaseURL = URL(string: "https://api.github.com/repos/MikeC444/ArcTV-Mac/releases/latest")!

    /// True when `candidate` is a higher version than `current`. Accepts a leading "v" and ignores anything after a "-" (like "-beta").
    public static func isNewer(_ candidate: String, than current: String) -> Bool {
        let a = parts(candidate), b = parts(current)
        for i in 0..<max(a.count, b.count) {
            let x = i < a.count ? a[i] : 0, y = i < b.count ? b[i] : 0
            if x != y { return x > y }
        }
        return false
    }

    private static func parts(_ version: String) -> [Int] {
        var text = version.trimmingCharacters(in: .whitespaces)
        if text.hasPrefix("v") || text.hasPrefix("V") { text.removeFirst() }
        if let dash = text.firstIndex(of: "-") { text = String(text[..<dash]) }
        return text.split(separator: ".").map { Int($0) ?? 0 }
    }

    private struct Release: Decodable {
        struct Asset: Decodable {
            var name: String
            var browserDownloadUrl: String
            enum CodingKeys: String, CodingKey { case name; case browserDownloadUrl = "browser_download_url" }
        }
        var tagName: String
        var body: String?
        var htmlUrl: String?
        var assets: [Asset]?
        enum CodingKeys: String, CodingKey { case tagName = "tag_name"; case body; case htmlUrl = "html_url"; case assets }
    }

    /// Reads GitHub's "latest release" reply.
    public static func parse(_ data: Data) throws -> ReleaseInfo {
        let release = try JSONDecoder().decode(Release.self, from: data)
        var version = release.tagName
        if version.hasPrefix("v") || version.hasPrefix("V") { version.removeFirst() }
        let dmg = release.assets?.first { $0.name.lowercased().hasSuffix(".dmg") }
        return ReleaseInfo(
            version: version,
            notes: (release.body ?? "").trimmingCharacters(in: .whitespacesAndNewlines),
            pageURL: release.htmlUrl.flatMap(URL.init(string:)),
            downloadURL: dmg.flatMap { URL(string: $0.browserDownloadUrl) }
        )
    }

    /// Compares a GitHub reply with the running version. No release published yet (404) counts as up to date.
    public static func result(statusCode: Int, data: Data, current: String) throws -> UpdateResult {
        if statusCode == 404 { return .upToDate(latest: nil) }
        guard (200..<300).contains(statusCode) else { throw URLError(.badServerResponse) }
        let info = try parse(data)
        return isNewer(info.version, than: current) ? .available(info) : .upToDate(latest: info.version)
    }

    public static func check(current: String, session: URLSession = .shared) async throws -> UpdateResult {
        var request = URLRequest(url: latestReleaseURL)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 15
        let (data, response) = try await session.data(for: request)
        return try result(statusCode: (response as? HTTPURLResponse)?.statusCode ?? 0, data: data, current: current)
    }
}
