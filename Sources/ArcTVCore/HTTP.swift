import Foundation

/// What went wrong talking to a server, in words a person can read.
public enum APIError: Error, Equatable, LocalizedError {
    case server(status: Int, message: String?)
    case badURL(String)
    case unreadable

    public var errorDescription: String? {
        switch self {
        case let .server(status, message):
            if let message, !message.isEmpty { return message }
            return status == 401 ? "Wrong email or password." : "The server answered with an error (HTTP \(status))."
        case let .badURL(text): return "That address doesn't look right: \(text)"
        case .unreadable: return "The server's answer couldn't be read."
        }
    }
}

enum HTTP {
    static let session: URLSession = {
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = 15
        configuration.waitsForConnectivity = false
        return URLSession(configuration: configuration)
    }()

    static func data(for request: URLRequest) async throws -> Data {
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw APIError.unreadable }
        guard (200..<300).contains(http.statusCode) else {
            throw APIError.server(status: http.statusCode, message: errorMessage(from: data))
        }
        return data
    }

    static func get(_ urlString: String) async throws -> Data {
        guard let url = URL(string: urlString) else { throw APIError.badURL(urlString) }
        return try await data(for: URLRequest(url: url))
    }

    /// The backend answers errors as {"error": "..."}.
    static func errorMessage(from data: Data) -> String? {
        struct Body: Decodable { var error: String? }
        return (try? JSONDecoder().decode(Body.self, from: data))?.error
    }
}
