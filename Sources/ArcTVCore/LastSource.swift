import Foundation

/// What a title (or episode) was last watched on, kept on this Mac only (not part of the synced account data), so "Play" and "Resume" carry on
/// with the same release instead of going back to the source list. It keeps what the source was (addon, release name, torrent hash) because an
/// addon can hand out new links between two requests.
public struct LastSource: Codable, Equatable, Sendable {
    public var addonName: String
    public var releaseTitle: String
    public var infoHash: String?

    public init(addonName: String, releaseTitle: String, infoHash: String? = nil) {
        self.addonName = addonName
        self.releaseTitle = releaseTitle
        self.infoHash = infoHash
    }

    public init(_ item: SourceItem) {
        self.init(addonName: item.addonName, releaseTitle: item.headline, infoHash: item.stream.infoHash)
    }

    /// Finds the source in a fresh list: the same torrent (info hash), else the same release from the same addon, else the same release name. Only
    /// a source that can play here counts. Nothing is guessed beyond that.
    public func match(in items: [SourceItem]) -> SourceItem? {
        let playable = items.filter(\.canStream)
        if let hash = infoHash?.lowercased(), !hash.isEmpty, let found = playable.first(where: { $0.stream.infoHash?.lowercased() == hash }) { return found }
        return playable.first { $0.headline == releaseTitle && $0.addonName == addonName } ?? playable.first { $0.headline == releaseTitle }
    }
}

public struct LastSourceStore {
    private let defaults: UserDefaults
    private let userID: String

    public init(defaults: UserDefaults = .standard, userID: String) {
        self.defaults = defaults
        self.userID = userID
    }

    private var storageKey: String { "ArcTVLastSources-\(userID)" }

    public static func key(titleID: String, season: Int?, episode: Int?) -> String { "\(titleID)|\(season ?? -1)|\(episode ?? -1)" }

    private func all() -> [String: LastSource] {
        guard let data = defaults.data(forKey: storageKey), let map = try? JSONDecoder().decode([String: LastSource].self, from: data) else { return [:] }
        return map
    }

    public func get(titleID: String, season: Int?, episode: Int?) -> LastSource? {
        all()[Self.key(titleID: titleID, season: season, episode: episode)]
    }

    public func set(_ source: LastSource, titleID: String, season: Int?, episode: Int?) {
        var map = all()
        map[Self.key(titleID: titleID, season: season, episode: episode)] = source
        if let data = try? JSONEncoder().encode(map) { defaults.set(data, forKey: storageKey) }
    }
}
