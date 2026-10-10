import Foundation

public struct AccountUser: Codable, Equatable, Sendable {
    public var id: String
    public var email: String
    public var displayName: String?
}

/// A signed-in session: the token pair the backend hands out plus who it is for. Matches the backend's /auth/login answer.
public struct Session: Codable, Equatable, Sendable {
    public var accessToken: String
    public var accessTokenExpiresAt: String
    public var refreshToken: String
    public var refreshTokenExpiresAt: String
    public var user: AccountUser
}

struct LoginRequest: Encodable {
    var email: String
    var password: String
    var deviceId: String
    var deviceName: String?
    var platform: String?
}

struct RegisterRequest: Encodable {
    var email: String
    var password: String
    var displayName: String?
    var deviceId: String
    var deviceName: String?
    var platform: String?
}

struct RefreshRequest: Encodable {
    var refreshToken: String
}

struct TokenPair: Decodable {
    var accessToken: String
    var accessTokenExpiresAt: String
    var refreshToken: String
    var refreshTokenExpiresAt: String
}

/// The account backend (the same one the Android and web apps use). [baseURL] has no trailing slash.
public struct AuthClient: Sendable {
    public let baseURL: String

    public init(baseURL: String) {
        var trimmed = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        while trimmed.hasSuffix("/") { trimmed.removeLast() }
        self.baseURL = trimmed
    }

    public func login(email: String, password: String, deviceId: String, deviceName: String) async throws -> Session {
        let body = LoginRequest(email: email, password: password, deviceId: deviceId, deviceName: deviceName, platform: "macos")
        let data = try await post("/auth/login", body: body, accessToken: nil)
        do {
            return try JSONDecoder().decode(Session.self, from: data)
        } catch {
            throw APIError.unreadable
        }
    }

    /// Makes a new account and signs it in on this device.
    public func register(email: String, password: String, displayName: String?, deviceId: String, deviceName: String) async throws -> Session {
        let name = displayName?.trimmingCharacters(in: .whitespacesAndNewlines)
        let body = RegisterRequest(email: email, password: password, displayName: (name?.isEmpty ?? true) ? nil : name, deviceId: deviceId, deviceName: deviceName, platform: "macos")
        let data = try await post("/auth/register", body: body, accessToken: nil)
        do {
            return try JSONDecoder().decode(Session.self, from: data)
        } catch {
            throw APIError.unreadable
        }
    }

    /// Trades the refresh token for a new pair (the user stays the same).
    public func refresh(_ session: Session) async throws -> Session {
        let data = try await post("/auth/refresh", body: RefreshRequest(refreshToken: session.refreshToken), accessToken: nil)
        guard let pair = try? JSONDecoder().decode(TokenPair.self, from: data) else { throw APIError.unreadable }
        var next = session
        next.accessToken = pair.accessToken
        next.accessTokenExpiresAt = pair.accessTokenExpiresAt
        next.refreshToken = pair.refreshToken
        next.refreshTokenExpiresAt = pair.refreshTokenExpiresAt
        return next
    }

    /// Best effort: the app forgets the session whether or not this succeeds.
    public func logout(accessToken: String) async {
        guard let url = URL(string: baseURL + "/auth/logout") else { return }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        _ = try? await HTTP.session.data(for: request)
    }

    private func post<Body: Encodable>(_ path: String, body: Body, accessToken: String?) async throws -> Data {
        guard let url = URL(string: baseURL + path) else { throw APIError.badURL(baseURL + path) }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        // A server on a free hosting plan can take a minute to wake up on the first request after a quiet spell.
        request.timeoutInterval = 60
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let accessToken { request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization") }
        request.setValue(AppInfo.version, forHTTPHeaderField: "X-ArcTV-App-Version")
        request.httpBody = try JSONEncoder().encode(body)
        return try await HTTP.data(for: request)
    }
}

/// The same loose check the web app makes before asking the server (which stays the authority).
public enum Credentials {
    public static let minPasswordLength = 8

    public static func problem(email: String, password: String) -> String? {
        let trimmed = email.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty { return "Enter your email address." }
        if trimmed.range(of: #"^[^\s@]+@[^\s@]+\.[^\s@]+$"#, options: .regularExpression) == nil { return "Enter a valid email address." }
        if password.count < minPasswordLength { return "Password must be at least \(minPasswordLength) characters." }
        return nil
    }
}
