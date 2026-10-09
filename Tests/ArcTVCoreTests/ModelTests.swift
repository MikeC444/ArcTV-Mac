import XCTest
@testable import ArcTVCore

final class ModelTests: XCTestCase {
    func testDecodesACatalogueAndToleratesMissingFields() throws {
        let json = """
        {"metas":[
          {"id":"tt0816692","type":"movie","name":"Interstellar","poster":"https://example.com/p.jpg","imdbRating":"8.7","genres":["Sci-Fi"]},
          {"id":"tt1","type":"series","name":"No Poster"}
        ]}
        """
        let metas = try JSONDecoder().decode(CatalogResponse.self, from: Data(json.utf8)).metas ?? []
        XCTAssertEqual(metas.count, 2)
        XCTAssertEqual(metas[0].name, "Interstellar")
        XCTAssertEqual(metas[0].genres, ["Sci-Fi"])
        XCTAssertNil(metas[1].poster)
    }

    func testManifestKnowsWhichCataloguesItOffers() throws {
        let json = """
        {"id":"com.linvo.cinemeta","name":"Cinemeta","version":"3.0.0",
         "catalogs":[{"type":"movie","id":"top"},{"type":"movie","id":"year"},{"type":"series","id":"top"}]}
        """
        let manifest = try JSONDecoder().decode(AddonManifest.self, from: Data(json.utf8))
        XCTAssertTrue(manifest.offersCatalog(type: "movie", id: "year"))
        XCTAssertFalse(manifest.offersCatalog(type: "series", id: "year"))
        XCTAssertFalse(AddonManifest(id: "x", name: "No catalogues").offersCatalog(type: "movie", id: "top"))
    }

    func testDecodesTheBackendsLoginAnswer() throws {
        let json = """
        {"accessToken":"a","accessTokenExpiresAt":"2026-10-10T00:00:00.000Z","refreshToken":"r","refreshTokenExpiresAt":"2026-11-10T00:00:00.000Z",
         "user":{"id":"u1","email":"me@example.com","displayName":"Mike"}}
        """
        let session = try JSONDecoder().decode(Session.self, from: Data(json.utf8))
        XCTAssertEqual(session.user.email, "me@example.com")
        XCTAssertEqual(session.refreshToken, "r")
    }

    func testBackendErrorsReadAsTheirMessage() {
        let data = Data(#"{"error":"Invalid email or password","requestId":"x"}"#.utf8)
        XCTAssertEqual(HTTP.errorMessage(from: data), "Invalid email or password")
        XCTAssertEqual(APIError.server(status: 401, message: nil).errorDescription, "Wrong email or password.")
    }

    func testAuthClientTrimsTheServerAddress() {
        XCTAssertEqual(AuthClient(baseURL: " https://api.example.com// ").baseURL, "https://api.example.com")
    }
}
