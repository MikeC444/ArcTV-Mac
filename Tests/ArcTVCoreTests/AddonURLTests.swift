import XCTest
@testable import ArcTVCore

final class AddonURLTests: XCTestCase {
    func testNormalizesStremioLinksAndBareHosts() {
        XCTAssertEqual(AddonURL.normalizeManifestURL("stremio://v3-cinemeta.strem.io"), "https://v3-cinemeta.strem.io/manifest.json")
        XCTAssertEqual(AddonURL.normalizeManifestURL("  example.com/addon/  "), "https://example.com/addon/manifest.json")
        XCTAssertEqual(AddonURL.normalizeManifestURL("https://example.com/Manifest.json"), "https://example.com/Manifest.json")
    }

    func testResourceBaseDropsTheManifest() {
        XCTAssertEqual(AddonURL.resourceBase("https://v3-cinemeta.strem.io/manifest.json"), "https://v3-cinemeta.strem.io")
        XCTAssertEqual(AddonURL.resourceBase("https://example.com/a/b/manifest.json"), "https://example.com/a/b")
    }

    func testCatalogURLWithAndWithoutExtras() {
        let manifest = "https://v3-cinemeta.strem.io/manifest.json"
        XCTAssertEqual(
            AddonURL.catalogURL(manifestURL: manifest, type: "movie", catalogId: "top"),
            "https://v3-cinemeta.strem.io/catalog/movie/top.json"
        )
        XCTAssertEqual(
            AddonURL.catalogURL(manifestURL: manifest, type: "movie", catalogId: "year", extra: ["genre": "2026"]),
            "https://v3-cinemeta.strem.io/catalog/movie/year/genre=2026.json"
        )
        XCTAssertEqual(
            AddonURL.catalogURL(manifestURL: manifest, type: "series", catalogId: "top", extra: ["genre": "Sci Fi"]),
            "https://v3-cinemeta.strem.io/catalog/series/top/genre=Sci%20Fi.json"
        )
    }
}
