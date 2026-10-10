import Foundation

/// The account's settings (`/user/settings`), one row shared by every app. Changing one thing means sending all of it back, so the whole
/// thing is kept and only the changed field is edited.
public struct AccountSettings: Codable, Equatable, Sendable {
    public var homeRowOrder: [String]
    public var hiddenRowIds: [String]
    public var autoplayNextEpisode: Bool
    public var skipIntroEnabled: Bool
    public var subtitlesEnabled: Bool
    public var defaultSubtitleLanguage: String?
    public var defaultAudioLanguage: String?
    public var blockedGenres: [String]?
    public var updatedAt: String?

    public init(homeRowOrder: [String] = [], hiddenRowIds: [String] = [], autoplayNextEpisode: Bool = true, skipIntroEnabled: Bool = true,
                subtitlesEnabled: Bool = false, defaultSubtitleLanguage: String? = nil, defaultAudioLanguage: String? = nil,
                blockedGenres: [String]? = nil, updatedAt: String? = nil) {
        self.homeRowOrder = homeRowOrder
        self.hiddenRowIds = hiddenRowIds
        self.autoplayNextEpisode = autoplayNextEpisode
        self.skipIntroEnabled = skipIntroEnabled
        self.subtitlesEnabled = subtitlesEnabled
        self.defaultSubtitleLanguage = defaultSubtitleLanguage
        self.defaultAudioLanguage = defaultAudioLanguage
        self.blockedGenres = blockedGenres
        self.updatedAt = updatedAt
    }

    private enum Keys: String, CodingKey {
        case homeRowOrder, hiddenRowIds, autoplayNextEpisode, skipIntroEnabled, subtitlesEnabled
        case defaultSubtitleLanguage, defaultAudioLanguage, blockedGenres, updatedAt
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: Keys.self)
        homeRowOrder = try c.decodeIfPresent([String].self, forKey: .homeRowOrder) ?? []
        hiddenRowIds = try c.decodeIfPresent([String].self, forKey: .hiddenRowIds) ?? []
        autoplayNextEpisode = try c.decodeIfPresent(Bool.self, forKey: .autoplayNextEpisode) ?? true
        skipIntroEnabled = try c.decodeIfPresent(Bool.self, forKey: .skipIntroEnabled) ?? true
        subtitlesEnabled = try c.decodeIfPresent(Bool.self, forKey: .subtitlesEnabled) ?? false
        defaultSubtitleLanguage = try c.decodeIfPresent(String.self, forKey: .defaultSubtitleLanguage)
        defaultAudioLanguage = try c.decodeIfPresent(String.self, forKey: .defaultAudioLanguage)
        blockedGenres = try c.decodeIfPresent([String].self, forKey: .blockedGenres)
        updatedAt = try c.decodeIfPresent(String.self, forKey: .updatedAt)
    }

    /// Sends a null for an empty language (that clears the account's choice, as the backend expects) instead of leaving the key out.
    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: Keys.self)
        try c.encode(homeRowOrder, forKey: .homeRowOrder)
        try c.encode(hiddenRowIds, forKey: .hiddenRowIds)
        try c.encode(autoplayNextEpisode, forKey: .autoplayNextEpisode)
        try c.encode(skipIntroEnabled, forKey: .skipIntroEnabled)
        try c.encode(subtitlesEnabled, forKey: .subtitlesEnabled)
        try c.encode(defaultSubtitleLanguage, forKey: .defaultSubtitleLanguage)
        try c.encode(defaultAudioLanguage, forKey: .defaultAudioLanguage)
        try c.encode(blockedGenres ?? [], forKey: .blockedGenres)
        try c.encode(updatedAt ?? ISODate.now(), forKey: .updatedAt)
    }
}

public extension Array where Element == MetaPreview {
    /// Titles with none of the blocked genres (the other apps hide them everywhere).
    func withoutBlocked(_ blocked: Set<String>) -> [MetaPreview] {
        guard !blocked.isEmpty else { return self }
        let lowered = Set(blocked.map { $0.lowercased() })
        return filter { item in !(item.genres ?? []).contains { lowered.contains($0.lowercased()) } }
    }
}

public extension MetaDetail {
    /// True when one of the title's genres is blocked (Blocked Genres, or a kids profile's own list).
    func isBlocked(by blocked: Set<String>) -> Bool {
        guard !blocked.isEmpty else { return false }
        let lowered = Set(blocked.map { $0.lowercased() })
        return (genres ?? []).contains { lowered.contains($0.lowercased()) }
    }
}

extension AuthClient {
    public func settings(accessToken: String) async throws -> AccountSettings {
        let data = try await sendJSON("GET", "/user/settings", body: nil, accessToken: accessToken)
        guard let decoded = try? JSONDecoder().decode(AccountSettings.self, from: data) else { throw APIError.unreadable }
        return decoded
    }

    /// Saves the whole settings row (last write wins, stamped now) and returns what the backend kept.
    public func saveSettings(accessToken: String, _ settings: AccountSettings) async throws -> AccountSettings {
        var next = settings
        next.updatedAt = ISODate.now()
        let data = try await sendJSON("PUT", "/user/settings", body: try JSONEncoder().encode(next), accessToken: accessToken)
        return (try? JSONDecoder().decode(AccountSettings.self, from: data)) ?? next
    }
}
