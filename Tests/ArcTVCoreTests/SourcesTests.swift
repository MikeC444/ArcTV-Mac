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
        XCTAssertEqual(detail.seasonNumbers, [1, 2])
        XCTAssertEqual(detail.seasons[1]?.map(\.displayTitle), ["One", "Two"])
    }

    func testAddonErrorsReadAsSentences() {
        XCTAssertEqual(describeAddonError(APIError.server(status: 403, message: nil)), "refused the request (HTTP 403)")
        XCTAssertEqual(describeAddonError(APIError.server(status: 503, message: nil)), "had a problem answering (HTTP 503)")
        XCTAssertEqual(describeAddonError(APIError.server(status: 429, message: nil)), "is limiting requests right now, try again in a moment")
        XCTAssertEqual(describeAddonError(URLError(.timedOut)), "took too long to answer")
        XCTAssertEqual(describeAddonError(URLError(.notConnectedToInternet)), "couldn't be reached")
    }

    func testSmartPickingTakesTheTorrentWithMostSeedersThenSizeThenQuality() {
        func torrent(_ hash: String, _ title: String, _ index: Int) -> SourceItem {
            SourceItem(addonName: "T", stream: AddonStream(infoHash: hash, title: title), index: index)
        }
        let few = torrent("a", "Show 2160p\n👤 2  💾 30 GB", 0)
        let many = torrent("b", "Show 720p\n👤 150  💾 1.2 GB", 1)
        XCTAssertEqual(SourceListing.bestTorrent(in: [few, many])?.stream.infoHash, "b")
        // equal seeders: the bigger file
        let small = torrent("c", "Show 1080p\n👤 40  💾 2 GB", 0)
        let big = torrent("d", "Show 1080p\n👤 40  💾 9 GB", 1)
        XCTAssertEqual(SourceListing.bestTorrent(in: [small, big])?.stream.infoHash, "d")
        // equal seeders and size: the better quality, then the addon's order
        let hd = torrent("e", "Show 720p\n👤 40  💾 4 GB", 0)
        let uhd = torrent("f", "Show 2160p\n👤 40  💾 4 GB", 1)
        XCTAssertEqual(SourceListing.bestTorrent(in: [hd, uhd])?.stream.infoHash, "f")
        // a source with a web link is not a torrent
        let link = SourceItem(addonName: "D", stream: AddonStream(url: "https://x.example/a.mkv", title: "Show 1080p"), index: 2)
        XCTAssertNil(SourceListing.bestTorrent(in: [link]))
    }
}
