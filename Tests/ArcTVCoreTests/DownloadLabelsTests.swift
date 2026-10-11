import XCTest
@testable import ArcTVCore

final class DownloadLabelsTests: XCTestCase {
    private func item(name: String? = nil, title: String? = nil, size: Int64? = nil) -> SourceItem {
        SourceItem(
            addonName: "A",
            stream: AddonStream(url: "https://cdn.example.com/x.mkv", ytId: nil, infoHash: nil, fileIdx: nil, title: title, name: name, description: nil,
                                behaviorHints: StreamHints(filename: nil, videoSize: size), sources: nil),
            index: 0
        )
    }

    func testReleaseKindIsNamedInPlainWords() {
        XCTAssertEqual(DownloadLabels.kind(item(title: "Movie.2160p.UHD.BluRay.REMUX")), "UHD Blu-ray REMUX")
        XCTAssertEqual(DownloadLabels.kind(item(title: "Movie.1080p.BluRay.x264")), "Blu-ray")
        XCTAssertEqual(DownloadLabels.kind(item(title: "Movie.2160p.WEB-DL.H265")), "4K WEB-DL")
        XCTAssertEqual(DownloadLabels.kind(item(title: "Movie.1080p.WEBRip")), "WEB-DL")
        XCTAssertEqual(DownloadLabels.kind(item(title: "Movie 1080p HDTV")), "HDTV")
        XCTAssertEqual(DownloadLabels.kind(item(title: "Movie.2024.HDCAM")), "Camera recording")
        XCTAssertEqual(DownloadLabels.kind(item(title: "Movie 720p")), "720p")
    }

    func testHdrAndCodecAreReadFromTheName() {
        XCTAssertEqual(DownloadLabels.hdr(item(title: "Movie.2160p.DV.HDR10")), "Dolby Vision")
        XCTAssertEqual(DownloadLabels.hdr(item(title: "Movie.2160p.HDR10.HEVC")), "HDR")
        XCTAssertNil(DownloadLabels.hdr(item(title: "Movie.1080p.x264")))
        XCTAssertEqual(DownloadLabels.codec(item(title: "Movie.2160p.AV1")), "AV1")
        XCTAssertEqual(DownloadLabels.codec(item(title: "Movie.2160p.H.265")), "HEVC")
        XCTAssertEqual(DownloadLabels.codec(item(title: "Movie.1080p.x264")), "H.264")
        XCTAssertNil(DownloadLabels.codec(item(title: "Movie")))
    }

    func testTheDebridTagSaysWhetherTheFileIsStored() {
        XCTAssertEqual(DownloadLabels.debrid(item(name: "[TB+] Torrentio 4K")), DebridTag(service: "TB", cached: true))
        XCTAssertEqual(DownloadLabels.debrid(item(name: "[rd download] Torrentio")), DebridTag(service: "RD", cached: false))
        XCTAssertNil(DownloadLabels.debrid(item(name: "Torrentio 4K")))
        XCTAssertEqual(DownloadLabels.debrid(item(name: "[TB+] x"))?.label, "Cached on TorBox")
        XCTAssertEqual(DownloadLabels.debrid(item(name: "[RD download] x"))?.label, "Not cached: may take a while to start")
    }

    func testATiny1080pOr4KFileIsCalledUnusuallySmall() {
        XCTAssertTrue(DownloadLabels.isUnusuallySmall(item(title: "Movie.2160p", size: 12_000_000)))
        XCTAssertTrue(DownloadLabels.isUnusuallySmall(item(title: "Movie.1080p", size: 100_000_000)))
        XCTAssertFalse(DownloadLabels.isUnusuallySmall(item(title: "Movie.1080p", size: 1_470_000_000)))
        XCTAssertFalse(DownloadLabels.isUnusuallySmall(item(title: "Movie.720p", size: 50_000_000)))
        XCTAssertFalse(DownloadLabels.isUnusuallySmall(item(title: "Movie.2160p", size: nil)))
    }
}
