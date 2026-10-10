import XCTest
@testable import ArcTVCore

final class SettingsTabsTests: XCTestCase {
    func testMoveRow() {
        let order = ["a", "b", "c"]
        XCTAssertEqual(HomeRowOrder.move(order, id: "b", delta: -1), ["b", "a", "c"])
        XCTAssertEqual(HomeRowOrder.move(order, id: "b", delta: 1), ["a", "c", "b"])
        XCTAssertEqual(HomeRowOrder.move(order, id: "a", delta: -1), order)
        XCTAssertEqual(HomeRowOrder.move(order, id: "c", delta: 1), order)
        XCTAssertEqual(HomeRowOrder.move(order, id: "x", delta: 1), order)
    }

    func testLanguageLists() {
        XCTAssertEqual(LanguageChoices.subtitles().count, 16)
        XCTAssertNil(LanguageChoices.subtitles()[0].code)
        XCTAssertEqual(LanguageChoices.audio()[0].name, "Automatic")
        XCTAssertEqual(LanguageChoices.all.first?.code, "en")
    }

    func testVersionCompare() {
        XCTAssertTrue(UpdateCheck.isNewer("0.1.3", than: "0.1.2"))
        XCTAssertTrue(UpdateCheck.isNewer("v0.2.0", than: "0.1.9"))
        XCTAssertTrue(UpdateCheck.isNewer("1.0", than: "0.9.9"))
        XCTAssertFalse(UpdateCheck.isNewer("0.1.2", than: "0.1.2"))
        XCTAssertFalse(UpdateCheck.isNewer("0.1.2", than: "0.1.10"))
        XCTAssertFalse(UpdateCheck.isNewer("1.0.0", than: "1.0"))
    }

    func testParseRelease() throws {
        let json = """
        {"tag_name":"v0.2.0","body":"- Faster Home\\n- New look\\n","html_url":"https://github.com/x/y/releases/tag/v0.2.0",
         "assets":[{"name":"ArcTV.dmg","browser_download_url":"https://github.com/x/y/releases/download/v0.2.0/ArcTV.dmg"}]}
        """
        let data = Data(json.utf8)
        let info = try UpdateCheck.parse(data)
        XCTAssertEqual(info.version, "0.2.0")
        XCTAssertEqual(info.notes, "- Faster Home\n- New look")
        XCTAssertEqual(info.downloadURL?.lastPathComponent, "ArcTV.dmg")
        XCTAssertEqual(try UpdateCheck.result(statusCode: 200, data: data, current: "0.1.0"), .available(info))
        XCTAssertEqual(try UpdateCheck.result(statusCode: 200, data: data, current: "0.2.0"), .upToDate(latest: "0.2.0"))
        XCTAssertEqual(try UpdateCheck.result(statusCode: 404, data: Data(), current: "0.1.0"), .upToDate(latest: nil))
        XCTAssertThrowsError(try UpdateCheck.result(statusCode: 500, data: Data(), current: "0.1.0"))
    }
}

final class TorrentTests: XCTestCase {
    func testMagnet() {
        var stream = AddonStream(infoHash: "ABCDEF", title: "Movie 1080p\n👤 5")
        stream.sources = ["tracker:udp://a.example:80/announce", "dht:ABCDEF", "tracker:udp://a.example:80/announce", "tracker:http://b.example/x"]
        let magnet = stream.magnetURI ?? ""
        XCTAssertTrue(magnet.hasPrefix("magnet:?xt=urn:btih:ABCDEF&dn=Movie"))
        XCTAssertEqual(magnet.components(separatedBy: "&tr=").count, 3)
        XCTAssertNil(AddonStream(title: "x").magnetURI)
    }

    func testTorrentIsNotPlayableButCanStream() {
        let torrent = SourceItem(addonName: "T", stream: AddonStream(infoHash: "abc", title: "Show"), index: 0)
        XCTAssertTrue(torrent.isTorrent)
        XCTAssertFalse(torrent.isPlayable)
        XCTAssertTrue(torrent.canStream)
        let direct = SourceItem(addonName: "D", stream: AddonStream(url: "https://x/y.mkv", infoHash: "abc"), index: 1)
        XCTAssertFalse(direct.isTorrent)
        XCTAssertTrue(direct.canStream)
    }

    func testFileChoice() {
        let files = [
            TorrentFile(index: 0, name: "Show.S01E01.mkv", size: 900),
            TorrentFile(index: 1, name: "Show.S01E02.mkv", size: 800),
            TorrentFile(index: 2, name: "sample.mp4", size: 10),
            TorrentFile(index: 3, name: "info.nfo", size: 1)
        ]
        XCTAssertEqual(TorrentFileChoice.pick(from: files, hint: 1, season: nil, episode: nil), 1)
        XCTAssertEqual(TorrentFileChoice.pick(from: files, hint: 3, season: 1, episode: 2), 1)
        XCTAssertEqual(TorrentFileChoice.pick(from: files, hint: nil, season: nil, episode: nil), 0)
        XCTAssertNil(TorrentFileChoice.pick(from: [files[3]], hint: nil, season: nil, episode: nil))
    }

    func testByteRange() {
        XCTAssertEqual(ByteRange.parse("bytes=0-99", size: 1000)?.end, 99)
        XCTAssertEqual(ByteRange.parse("bytes=500-", size: 1000)?.start, 500)
        XCTAssertEqual(ByteRange.parse("bytes=500-", size: 1000)?.end, 999)
        XCTAssertEqual(ByteRange.parse("bytes=-100", size: 1000)?.start, 900)
        XCTAssertEqual(ByteRange.parse("bytes=900-5000", size: 1000)?.end, 999)
        XCTAssertNil(ByteRange.parse("bytes=2000-", size: 1000))
        XCTAssertNil(ByteRange.parse(nil, size: 1000))
        XCTAssertNil(ByteRange.parse("bytes=5-2", size: 1000))
    }
}

final class SourceListingTests: XCTestCase {
    private func item(_ title: String, url: String? = nil, hash: String? = "h", index: Int = 0, size: Int64? = nil) -> SourceItem {
        var stream = AddonStream(url: url, infoHash: hash, title: title)
        if let size { stream.behaviorHints = StreamHints(filename: nil, videoSize: size) }
        return SourceItem(addonName: "T", stream: stream, index: index)
    }

    func testReadsTheReleaseName() {
        let source = item("Movie.2026.2160p.WEB-DL.DV.HDR10+.DDP5.1.Atmos.H265-X\n👤 42 💾 21.3 GB")
        XCTAssertEqual(source.seeders, 42)
        XCTAssertEqual(source.sourceTag, "WEB-DL")
        XCTAssertEqual(source.codecText, "HEVC  ·  HDR10+  ·  Dolby Vision")
        XCTAssertEqual(source.audioTag, "Atmos")
        XCTAssertEqual(source.sizeBytes, Int64(21.3 * 1_073_741_824))
        XCTAssertNil(item("plain name").seeders)
    }

    func testFilterAndSort() {
        let direct = item("Movie 1080p", url: "https://x/a.mkv", hash: nil, index: 0)
        let uhd = item("Movie 2160p\n👤 5", index: 1, size: 20_000_000_000)
        let hd = item("Movie 720p\n👤 90", index: 2, size: 2_000_000_000)
        let all = [direct, uhd, hd]
        XCTAssertEqual(SourceListing.recommendedID(in: all), direct.id)
        XCTAssertEqual(SourceListing.arrange(all, filter: .uhd, sort: .quality).map(\.id), [direct.id, uhd.id])
        XCTAssertEqual(SourceListing.arrange(all, filter: .all, sort: .seeders).map(\.id), [direct.id, hd.id, uhd.id])
        XCTAssertEqual(SourceListing.arrange(all, filter: .all, sort: .size).map(\.id), [direct.id, uhd.id, hd.id])
        XCTAssertEqual(SourceSort.size.next, .quality)
    }
}
