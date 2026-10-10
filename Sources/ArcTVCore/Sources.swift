import Foundation

/// A stream an addon offered (`/stream/<type>/<id>.json`).
public struct AddonStream: Codable, Equatable, Sendable {
    public var url: String?
    public var ytId: String?
    public var infoHash: String?
    public var fileIdx: Int?
    public var title: String?
    public var name: String?
    public var description: String?
    public var behaviorHints: StreamHints?
}

public struct StreamHints: Codable, Equatable, Sendable {
    public var filename: String?
    public var videoSize: Int64?
}

struct StreamResponse: Codable {
    var streams: [AddonStream]?
}

/// An addon on the account, as `/user/addons` lists it.
public struct SyncedAddon: Decodable, Equatable, Sendable {
    public var manifestUrl: String
    public var addonId: String
    public var name: String
    public var enabled: Bool
    public var sortOrder: Int
    public var manifestJson: AddonManifest?
}

struct SyncedAddonsResponse: Decodable {
    var items: [SyncedAddon]
}

extension AuthClient {
    /// The account's installed addons (the ones the other apps show under Settings > Addons).
    public func addons(accessToken: String) async throws -> [SyncedAddon] {
        guard let url = URL(string: baseURL + "/user/addons") else { throw APIError.badURL(baseURL) }
        var request = URLRequest(url: url)
        request.timeoutInterval = 60
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue(AppInfo.version, forHTTPHeaderField: "X-ArcTV-App-Version")
        let data = try await HTTP.data(for: request)
        guard let decoded = try? JSONDecoder().decode(SyncedAddonsResponse.self, from: data) else { throw APIError.unreadable }
        return decoded.items.filter(\.enabled).sorted { $0.sortOrder < $1.sortOrder }
    }
}

extension AddonClient {
    public func fetchMeta(manifestURL: String, type: String, id: String) async throws -> MetaDetail? {
        let url = "\(AddonURL.resourceBase(manifestURL))/meta/\(AddonURL.encode(type))/\(AddonURL.encodeID(id)).json"
        let data = try await HTTP.get(url)
        guard let decoded = try? JSONDecoder().decode(MetaResponse.self, from: data) else { throw APIError.unreadable }
        return decoded.meta
    }

    public func fetchStreams(manifestURL: String, type: String, id: String) async throws -> [AddonStream] {
        let url = "\(AddonURL.resourceBase(manifestURL))/stream/\(AddonURL.encode(type))/\(AddonURL.encodeID(id)).json"
        let data = try await HTTP.get(url)
        guard let decoded = try? JSONDecoder().decode(StreamResponse.self, from: data) else { throw APIError.unreadable }
        return decoded.streams ?? []
    }
}

extension AddonURL {
    /// A title id for a path: each ":"-separated part encoded on its own, so the colons in "tt123:1:2" stay (addons expect them literal).
    static func encodeID(_ id: String) -> String {
        id.split(separator: ":", omittingEmptySubsequences: false).map { encode(String($0)) }.joined(separator: ":")
    }
}

public enum Quality: Int, Comparable, Sendable {
    case unknown = 0, sd, p720, p1080, p2160

    public static func < (lhs: Quality, rhs: Quality) -> Bool { lhs.rawValue < rhs.rawValue }

    public var label: String {
        switch self {
        case .unknown: return "Auto"
        case .sd: return "SD"
        case .p720: return "720p"
        case .p1080: return "1080p"
        case .p2160: return "4K"
        }
    }

    /// Read from the words addons put in a stream's name and title ("2160p", "4K", "1080p", ...).
    public static func detect(in text: String) -> Quality {
        let lower = text.lowercased()
        if lower.contains("2160") || lower.contains("4k") || lower.contains("uhd") { return .p2160 }
        if lower.contains("1080") { return .p1080 }
        if lower.contains("720") { return .p720 }
        if lower.contains("480") || lower.contains("360") || lower.contains("dvdrip") { return .sd }
        return .unknown
    }
}

/// One row in the source list: a stream plus the addon it came from and what can be read off it.
public struct SourceItem: Identifiable, Equatable, Sendable {
    public var id: String
    public var addonName: String
    public var stream: AddonStream

    public init(addonName: String, stream: AddonStream, index: Int) {
        self.addonName = addonName
        self.stream = stream
        self.id = "\(addonName)#\(index)"
    }

    private var searchText: String {
        [stream.name, stream.title, stream.description, stream.behaviorHints?.filename].compactMap { $0 }.joined(separator: " ")
    }

    public var quality: Quality { Quality.detect(in: searchText) }

    /// The address to play, when the addon gave a direct web link (a debrid service does). Torrent-only streams have none.
    public var playURL: URL? {
        guard let text = stream.url, text.lowercased().hasPrefix("http") else { return nil }
        return URL(string: text)
    }

    public var isPlayable: Bool { playURL != nil }

    /// The first line addons use for the release name (their `title`, else the file name).
    public var headline: String {
        let first = (stream.title ?? stream.description ?? stream.behaviorHints?.filename ?? stream.name ?? "Stream")
            .split(separator: "\n", omittingEmptySubsequences: true).first.map(String.init)
        return first ?? "Stream"
    }

    /// The rest of the lines (size, seeds, language) joined on one line.
    public var details: String {
        let lines = (stream.title ?? stream.description ?? "").split(separator: "\n", omittingEmptySubsequences: true).dropFirst()
        return lines.joined(separator: "  ·  ")
    }

    public var sizeText: String? {
        if let bytes = stream.behaviorHints?.videoSize, bytes > 0 {
            return String(format: "%.1f GB", Double(bytes) / 1_073_741_824)
        }
        guard let range = searchText.range(of: #"\d+(\.\d+)?\s?(GB|MB)"#, options: [.regularExpression, .caseInsensitive]) else { return nil }
        return String(searchText[range])
    }
}

public enum SourceFinder {
    /// Every enabled addon that can stream [id] is asked at once; the playable ones come first, best quality first.
    public static func find(addons: [SyncedAddon], type: String, id: String, client: AddonClient = AddonClient()) async -> [SourceItem] {
        let askable = addons.filter { $0.manifestJson?.providesStreams(type: type, id: id) ?? false }
        let groups = await withTaskGroup(of: (Int, [SourceItem]).self) { group -> [(Int, [SourceItem])] in
            for (order, addon) in askable.enumerated() {
                group.addTask {
                    let streams = (try? await client.fetchStreams(manifestURL: addon.manifestUrl, type: type, id: id)) ?? []
                    return (order, streams.enumerated().map { SourceItem(addonName: addon.name, stream: $0.element, index: $0.offset) })
                }
            }
            var all: [(Int, [SourceItem])] = []
            for await result in group { all.append(result) }
            return all
        }
        let flat = groups.sorted { $0.0 < $1.0 }.flatMap { $0.1 }
        return flat.enumerated().sorted { left, right in
            let a = left.element, b = right.element
            if a.isPlayable != b.isPlayable { return a.isPlayable }
            if a.quality != b.quality { return a.quality > b.quality }
            return left.offset < right.offset // otherwise the addon's own order
        }.map(\.element)
    }
}
