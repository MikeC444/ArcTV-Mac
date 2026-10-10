import Foundation

private struct TrailerResponse: Decodable {
    var youtubeVideoId: String?
}

extension AuthClient {
    /// The YouTube id of a title's trailer (`GET /user/trailer`), nil when there is none. `type` is "movie" or "series".
    public func trailerID(accessToken: String, title: String, type: String, year: Int?) async throws -> String? {
        var query = ["title": title, "type": type == "movie" ? "MOVIE" : "TV_SHOW"]
        if let year { query["year"] = String(year) }
        let data = try await sendJSON("GET", "/user/trailer", query: query, body: nil, accessToken: accessToken)
        guard let decoded = try? JSONDecoder().decode(TrailerResponse.self, from: data) else { throw APIError.unreadable }
        return decoded.youtubeVideoId
    }
}
