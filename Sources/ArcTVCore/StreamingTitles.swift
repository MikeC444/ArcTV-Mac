import Foundation

/// One page of a streaming service's titles beyond what its addon lists: TMDB's popularity list for the service in the viewer's country, read through
/// the account's server (`GET /user/streaming-titles`), as the web and Fire TV apps do.
public struct StreamingTitlesPage: Equatable, Sendable {
    /// False when there is no TMDB source for the service (or the server has no TMDB key, or the ask failed): the page keeps to the addon's own titles.
    public var available: Bool
    public var items: [MetaPreview]
    public var totalPages: Int

    public init(available: Bool, items: [MetaPreview] = [], totalPages: Int = 0) {
        self.available = available
        self.items = items
        self.totalPages = totalPages
    }

    public static let notAvailable = StreamingTitlesPage(available: false)
}

struct StreamingTitleDTO: Decodable {
    var imdbId: String
    var type: String
    var title: String
    var year: Int?
    var rating: Double?
    var overview: String?
    var poster: String?
    var backdrop: String?

    /// The same title as an addon would give it. The server says "MOVIE" or "TV_SHOW"; a title of any other kind is left out.
    var preview: MetaPreview? {
        let kind: String
        switch type {
        case "MOVIE": kind = "movie"
        case "TV_SHOW": kind = "series"
        default: return nil
        }
        return MetaPreview(id: imdbId, type: kind, name: title, poster: poster, background: backdrop, description: overview,
                           releaseInfo: year.map(String.init), imdbRating: rating.map { String(format: "%.1f", $0) })
    }
}

struct StreamingTitlesAnswer: Decodable {
    var available: Bool?
    var items: [StreamingTitleDTO]?
    var totalPages: Int?
}

public enum StreamingTitles {
    /// The viewer's country as TMDB wants it (what a service carries differs by country): the Mac's region, else the US (as the web app).
    public static func region(_ locale: Locale = .current) -> String {
        if let code = locale.region?.identifier, code.count == 2 { return code.uppercased() }
        return "US"
    }

    /// Reads the server's answer; nil when it cannot be read.
    static func decode(_ data: Data) -> StreamingTitlesPage? {
        guard let answer = try? JSONDecoder().decode(StreamingTitlesAnswer.self, from: data) else { return nil }
        return StreamingTitlesPage(available: answer.available ?? false, items: (answer.items ?? []).compactMap(\.preview), totalPages: answer.totalPages ?? 0)
    }
}

extension AuthClient {
    /// One page (about 20) of a service's movies or series, most popular first. `type` is "movie" or "series". Never throws: a failed ask is "not available".
    public func streamingTitles(accessToken: String, service: String, type: String, page: Int, region: String) async -> StreamingTitlesPage {
        let query = ["service": service, "type": type == "movie" ? "MOVIE" : "TV_SHOW", "page": String(page), "region": region]
        guard let data = try? await sendJSON("GET", "/user/streaming-titles", query: query, body: nil, accessToken: accessToken) else { return .notAvailable }
        return StreamingTitles.decode(data) ?? .notAvailable
    }
}
