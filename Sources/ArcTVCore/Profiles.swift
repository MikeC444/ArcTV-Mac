import Foundation

/// A viewing profile on an account (Arc TV Plus): its own My List, Continue Watching, settings, addons and Likes. The account's own profile is
/// "main" and is always there.
public struct Profile: Codable, Equatable, Identifiable, Sendable {
    public var id: String
    public var name: String
    /// One of `Avatars.ids` (older colour-tile ids are shown as the nearest picture).
    public var avatar: String
    /// "adult" or "kids".
    public var kind: String
    /// The PIN itself never leaves the server; this only says a PIN is needed to open, change or remove the profile.
    public var hasPin: Bool
    /// The account's own profile: never removed, never a kids profile.
    public var isDefault: Bool

    public static let mainID = "main"
    public static let limit = 5
    public static let nameMax = 24
    public static let pinLength = 4

    public var isKids: Bool { kind == "kids" }

    public init(id: String, name: String, avatar: String, kind: String = "adult", hasPin: Bool = false, isDefault: Bool = false) {
        self.id = id
        self.name = name
        self.avatar = avatar
        self.kind = kind
        self.hasPin = hasPin
        self.isDefault = isDefault
    }

    public static func isValidPin(_ pin: String) -> Bool { pin.count == pinLength && pin.allSatisfy(\.isASCII) && pin.allSatisfy(\.isNumber) }

    /// Calls that are about the account, not a profile's library: they are sent without the profile header.
    public static func isAccountLevel(_ path: String) -> Bool {
        ["/user/me", "/user/plus", "/user/profiles", "/user/trailer", "/user/release-date", "/user/cast"].contains { path == $0 || path.hasPrefix($0 + "/") }
    }

    /// Genres a kids profile never shows (Home, Movies, TV Shows, Search, "You May Also Like"), on top of whatever the profile blocks itself.
    public static let kidsBlockedGenres = ["Horror", "Thriller", "Crime", "War", "Mystery", "Film-Noir", "Adult"]
}

public enum Avatars {
    /// The preset pictures, in the order they are offered.
    public static let ids = ["fox", "cat", "dog", "panda", "frog", "owl", "ghost", "robot", "alien", "astronaut", "raccoon", "penguin", "octopus", "dragon", "retro-tv", "lion"]

    static let legacy = ["astro": "astronaut", "monster": "alien", "sunrise": "fox", "ocean": "octopus", "forest": "frog", "violet": "ghost", "ember": "dragon", "mint": "owl", "wave": "penguin", "bolt": "robot"]

    /// The picture a stored id stands for (an old colour-tile id becomes the nearest new picture; anything unknown becomes the first).
    public static func resolve(_ id: String) -> String {
        let mapped = legacy[id] ?? id
        return ids.contains(mapped) ? mapped : ids[0]
    }
}

private struct ProfilesResponse: Decodable {
    var profiles: [Profile]
}

private struct CreateBody: Encodable {
    var name: String
    var avatar: String
    var kind: String
    var pin: String?
}

struct UpdateBody: Encodable {
    var name: String?
    var avatar: String?
    var kind: String?
    /// nil leaves the PIN alone; `.some(nil)` (sent as null) removes it.
    var pin: String??

    private enum Keys: String, CodingKey { case name, avatar, kind, pin }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: Keys.self)
        try c.encodeIfPresent(name, forKey: .name)
        try c.encodeIfPresent(avatar, forKey: .avatar)
        try c.encodeIfPresent(kind, forKey: .kind)
        if let pin { if let value = pin { try c.encode(value, forKey: .pin) } else { try c.encodeNil(forKey: .pin) } }
    }
}

private struct PinBody: Encodable {
    var pin: String
}

/// What a PIN check said.
public enum PinResult: Equatable, Sendable {
    case ok
    case wrong
    /// Too many wrong tries: guessing is refused for this many seconds.
    case locked(seconds: Int)
}

extension AuthClient {
    public func profiles(accessToken: String) async throws -> [Profile] {
        let data = try await sendJSON("GET", "/user/profiles", body: nil, accessToken: accessToken)
        guard let decoded = try? JSONDecoder().decode(ProfilesResponse.self, from: data) else { throw APIError.unreadable }
        return decoded.profiles
    }

    public func createProfile(accessToken: String, name: String, avatar: String, kind: String, pin: String?) async throws -> Profile {
        let body = try JSONEncoder().encode(CreateBody(name: name, avatar: avatar, kind: kind, pin: pin))
        let data = try await sendJSON("POST", "/user/profiles", body: body, accessToken: accessToken)
        guard let profile = try? JSONDecoder().decode(Profile.self, from: data) else { throw APIError.unreadable }
        return profile
    }

    /// Changes a profile. `pin`: nil leaves it, `.some(nil)` removes it, `.some("1234")` sets it. A locked profile needs `currentPin`.
    public func updateProfile(accessToken: String, id: String, name: String?, avatar: String?, kind: String?, pin: String??, currentPin: String?) async throws -> Profile {
        let body = try JSONEncoder().encode(UpdateBody(name: name, avatar: avatar, kind: kind, pin: pin))
        let data = try await sendJSON("PUT", "/user/profiles/\(id)", body: body, accessToken: accessToken, headers: currentPin.map { ["X-ArcTV-Pin": $0] } ?? [:])
        guard let profile = try? JSONDecoder().decode(Profile.self, from: data) else { throw APIError.unreadable }
        return profile
    }

    public func deleteProfile(accessToken: String, id: String, currentPin: String?) async throws {
        _ = try await sendJSON("DELETE", "/user/profiles/\(id)", body: nil, accessToken: accessToken, headers: currentPin.map { ["X-ArcTV-Pin": $0] } ?? [:])
    }

    public func verifyPin(accessToken: String, id: String, pin: String) async throws -> PinResult {
        do {
            _ = try await sendJSON("POST", "/user/profiles/\(id)/verify-pin", body: try JSONEncoder().encode(PinBody(pin: pin)), accessToken: accessToken)
            return .ok
        } catch let APIError.server(status, _) where status == 403 {
            return .wrong
        } catch let APIError.server(status, _) where status == 429 {
            return .locked(seconds: 300)
        }
    }
}
