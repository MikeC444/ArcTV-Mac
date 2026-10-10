import Foundation

/// A sign-in the person finishes on their phone: this Mac shows `activationUrl` as a QR code and asks the server until it is done.
public struct QRSession: Decodable, Equatable, Sendable {
    public var token: String
    public var activationUrl: String
    public var expiresAt: String
}

/// What asking about a QR sign-in found.
public enum QRPoll: Equatable, Sendable {
    case waiting
    case expired
    case signedIn(Session)
}

struct QRCreateRequest: Encodable {
    var deviceId: String
    var deviceName: String?
    var platform: String?
}

struct QRStatusAnswer: Decodable {
    var status: String
}

public extension AuthClient {
    func createQRSession(deviceId: String, deviceName: String) async throws -> QRSession {
        guard let url = URL(string: baseURL + "/auth/qr/create") else { throw APIError.badURL(baseURL + "/auth/qr/create") }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 60
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(QRCreateRequest(deviceId: deviceId, deviceName: deviceName, platform: "macos"))
        let data = try await HTTP.data(for: request)
        guard let session = try? JSONDecoder().decode(QRSession.self, from: data) else { throw APIError.unreadable }
        return session
    }

    func pollQRSession(token: String) async throws -> QRPoll {
        var components = URLComponents(string: baseURL + "/auth/qr/status")
        components?.queryItems = [URLQueryItem(name: "token", value: token)]
        guard let url = components?.url else { throw APIError.badURL(baseURL) }
        let data = try await HTTP.data(for: URLRequest(url: url))
        return try QRPoll.read(data)
    }
}

extension QRPoll {
    /// Reads the server's answer: pending, expired, or completed with the tokens (handed out once).
    static func read(_ data: Data) throws -> QRPoll {
        guard let answer = try? JSONDecoder().decode(QRStatusAnswer.self, from: data) else { throw APIError.unreadable }
        switch answer.status {
        case "completed":
            guard let session = try? JSONDecoder().decode(Session.self, from: data) else { throw APIError.unreadable }
            return .signedIn(session)
        case "expired", "not_found", "consumed":
            return .expired
        default:
            return .waiting
        }
    }
}
