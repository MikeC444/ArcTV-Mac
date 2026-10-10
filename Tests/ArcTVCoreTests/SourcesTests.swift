import XCTest
@testable import ArcTVCore

final class SourcesTests: XCTestCase {
    func testManifestResourcesAcceptNamesAndObjects() throws {
        let json = """
        {"id":"org.torrentio","name":"Torrentio","types":["movie","series"],
         "resources":["catalog",{"name":"stream","types":["movie","series"],"idPrefixes":["tt"]}]}
        """
        let manifest = try JSONDecoder().decode(AddonManifest.self, from: Data(json.utf8))
        XCTAssertTrue(manifest.providesStreams(type: "movie", id: "tt0816692"))
        XCTAssertTrue(manifest.providesStreams(type: "series", id: "tt1:1:2"))
        XCTAssertFalse(manifest.providesStreams(type: "movie", id: "kitsu:1"))
        XCTAssertFalse(manifest.providesStreams(type: "tv", id: "tt1"))
    }

    func testPlainStreamResourceUsesTheManifestsTypes() throws {
        let json = #"{"id":"a","name":"A","types":["movie"],"resources":["stream"]}"#
        let manifest = try JSONDecoder().decode(AddonManifest.self, from: Data(json.utf8))
        XCTAssertTrue(manifest.providesStreams(type: "movie", id: "tt1"))
        XCTAssertFalse(manifest.providesStreams(type: "series", id: "tt1"))
        let catalogOnly = try JSONDecoder().decode(AddonManifest.self, from: Data(#"{"id":"c","name":"C","resources":["catalog"]}"#.utf8))
        XCTAssertFalse(catalogOnly.providesStreams(type: "movie", id: "tt1"))
    }

    func testStreamAddressesKeepTheirColons() {
        XCTAssertEqual(AddonURL.encodeID("tt123:1:2"), "tt123:1:2")
        XCTAssertEqual(streamID(titleID: "tt123", season: 1, episode: 2), "tt123:1:2")
        XCTAssertEqual(streamID(titleID: "tt123", season: nil, episode: nil), "tt123")
    }

    func testReadsQualitySizeAndPlayability() throws {
        let json = """
        {"name":"TorBox 2160p","title":"Movie.2025.2160p.WEB-DL.mkv\\n👤 12  💾 14.2 GB  ⚙️ Site","url":"https://cdn.example/x.mkv"}
        """
        let stream = try JSONDecoder().decode(AddonStream.self, from: Data(json.utf8))
        let item = SourceItem(addonName: "Torrentio", stream: stream, index: 0)
        XCTAssertEqual(item.quality, .p2160)
        XCTAssertEqual(item.sizeText, "14.2 GB")
        XCTAssertTrue(item.isPlayable)
        XCTAssertEqual(item.headline, "Movie.2025.2160p.WEB-DL.mkv")

        let torrent = SourceItem(addonName: "T", stream: AddonStream(infoHash: "abc", title: "Show 720p"), index: 1)
        XCTAssertFalse(torrent.isPlayable)
        XCTAssertEqual(torrent.quality, .p720)
    }

    func testSeasonsAreGroupedAndSpecialsComeLast() throws {
        let json = """
        {"id":"tt1","type":"series","name":"S","videos":[
          {"id":"tt1:1:2","season":1,"episode":2,"title":"Two"},{"id":"tt1:1:1","season":1,"episode":1,"title":"One"},
          {"id":"tt1:0:1","season":0,"episode":1,"title":"Special"},{"id":"tt1:2:1","season":2,"episode":1,"name":"Next"}]}
        """
        let detail = try JSONDecoder().decode(MetaDetail.self, from: Data(json.utf8))
        XCTAssertEqual(detail.seasonNumbers, [1, 2, 0])
        XCTAssertEqual(detail.seasons[1]?.map(\.displayTitle), ["One", "Two"])
    }
}
