import XCTest
@testable import ArcTVCore

final class StreamingServicesTests: XCTestCase {
    private func catalog(_ id: String, type: String = "movie", name: String? = nil, extra: [CatalogExtra]? = nil) -> CatalogDefinition {
        CatalogDefinition(type: type, id: id, name: name ?? id, extra: extra)
    }

    private func source(_ catalogs: [CatalogDefinition]) -> HomeSource {
        HomeSource(manifestURL: "https://a/manifest.json", manifest: AddonManifest(id: "a", name: "Addon", catalogs: catalogs))
    }

    // These follow the Fire TV app's StreamingServicesTest (and so the web app's streamingServices.ts).

    func testACatalogueIsMatchedToItsServiceByNameThenIdAndTheLongestWordWins() {
        XCTAssertEqual(StreamingServices.serviceOfCatalog(name: "Netflix", id: "nfx"), "netflix")
        XCTAssertEqual(StreamingServices.serviceOfCatalog(name: nil, id: "dnp"), "disney")
        XCTAssertEqual(StreamingServices.serviceOfCatalog(name: "Netflix Kids", id: "nfk"), "netflixkids")
        XCTAssertEqual(StreamingServices.serviceOfCatalog(name: "Sky Showtime", id: "sst"), "skyshowtime")
        XCTAssertNil(StreamingServices.serviceOfCatalog(name: "Popular", id: "top"))
    }

    func testTheDefaultTilesAreTheTenBestKnownInOrderAndEveryOtherServiceIsOffUntilTurnedOn() {
        let on = StreamingServices.all.filter { !$0.off }.map(\.id)
        XCTAssertEqual(on, ["netflix", "prime", "apple", "max", "disney", "paramount", "hulu", "peacock", "iplayer", "shudder"])
        XCTAssertEqual(StreamingServices.all.count, 36)
        XCTAssertEqual(StreamingServices.service("prime")?.name, "Prime Video")
        XCTAssertNil(StreamingServices.service("nope"))
    }

    func testAServiceAddonIsOneWithThreeOrMoreServicesAndOneMentionIsNot() {
        let two = [catalog("nfx", name: "Netflix"), catalog("dnp", name: "Disney+")]
        XCTAssertEqual(StreamingServices.serviceCatalogs(in: two).count, 0)
        let three = two + [catalog("hlu", name: "Hulu")]
        XCTAssertEqual(StreamingServices.serviceCatalogs(in: three).count, 3)
        // a catalogue that needs something from the caller is not used
        let needing = two + [catalog("hlu", name: "Hulu", extra: [CatalogExtra(name: "genre", isRequired: true)])]
        XCTAssertEqual(StreamingServices.serviceCatalogs(in: needing).count, 0)
    }

    func testAServiceAddonGivesNoHomeRowsButHasTheServices() {
        let streaming = source([catalog("nfx", name: "Netflix"), catalog("dnp", name: "Disney+"), catalog("hlu", name: "Hulu")])
        XCTAssertTrue(streaming.catalogs.isEmpty)
        // a catalogue of a service the app does not know is left out too, not turned into a row
        let withUnknown = source([catalog("nfx", name: "Netflix"), catalog("dnp", name: "Disney+"), catalog("hlu", name: "Hulu"), catalog("shahid", name: "Shahid VIP")])
        XCTAssertTrue(withUnknown.catalogs.isEmpty)
        // ...and gets a tile of its own, off until turned on, named as the addon names it
        XCTAssertEqual(withUnknown.streamingServiceIDs, ["netflix", "disney", "hulu", "x-shahid"])
        StreamingServices.learn(from: [withUnknown])
        XCTAssertEqual(StreamingServices.service("x-shahid")?.name, "Shahid VIP")
        XCTAssertFalse(StreamingServices.isBuiltIn("x-shahid"))
        XCTAssertFalse(StreamingServices.isVisible("x-shahid", hidden: []))
        XCTAssertTrue(StreamingServices.isVisible("x-shahid", hidden: [StreamingServices.onID("x-shahid")]))
        StreamingServices.learn(from: [])
        XCTAssertEqual(streaming.streamingServiceIDs, ["netflix", "disney", "hulu"])
        // one catalogue that merely mentions a service keeps its row
        let ordinary = source([catalog("top", name: "Popular"), catalog("nfx", name: "Netflix Originals")])
        XCTAssertEqual(ordinary.catalogs.count, 2)
        XCTAssertTrue(ordinary.streamingServiceIDs.isEmpty)
    }

    func testADefaultOnServiceShowsUntilHiddenAndADefaultOffOneOnlyOnceTurnedOn() {
        XCTAssertTrue(StreamingServices.isVisible("netflix", hidden: []))
        XCTAssertFalse(StreamingServices.isVisible("netflix", hidden: ["streaming:netflix"]))
        XCTAssertFalse(StreamingServices.isVisible("crunchyroll", hidden: []))
        XCTAssertTrue(StreamingServices.isVisible("crunchyroll", hidden: ["streaming-on:crunchyroll"]))
        XCTAssertFalse(StreamingServices.isVisible("crunchyroll", hidden: ["streaming-on:crunchyroll", "streaming:crunchyroll"]))
    }

    func testTurningAServiceOnOrOffWritesTheIdsTheWebAppWritesAndKeepsTheOthers() {
        XCTAssertEqual(StreamingServices.withVisible(["x"], service: "netflix", visible: false), ["x", "streaming:netflix"])
        XCTAssertEqual(StreamingServices.withVisible(["x", "streaming:netflix"], service: "netflix", visible: true), ["x"])
        XCTAssertEqual(StreamingServices.withVisible(["x"], service: "crunchyroll", visible: true), ["x", "streaming-on:crunchyroll"])
        XCTAssertEqual(StreamingServices.withVisible(["streaming-on:crunchyroll"], service: "crunchyroll", visible: false), ["streaming:crunchyroll"])
    }

    func testThePersonsOwnOrderWinsAndANewServiceJoinsTheEnd() {
        let services = ["netflix", "disney", "hulu"]
        XCTAssertEqual(StreamingServices.inUserOrder(services, order: ["Popular_base", "streaming:hulu", "streaming:netflix"]), ["hulu", "netflix", "disney"])
        XCTAssertEqual(StreamingServices.inUserOrder(services, order: []), services)
        XCTAssertEqual(StreamingServices.inUserOrder(["netflix"], order: ["streaming:gone", "streaming:netflix"]), ["netflix"])
    }
}

final class StreamingTitlesTests: XCTestCase {
    func testTheServersAnswerBecomesTitlesAnAddonWouldGive() {
        let json = """
        {"available": true, "page": 2, "totalPages": 5, "items": [
          {"imdbId": "tt1", "type": "MOVIE", "title": "Alpha", "year": 2020, "rating": 7.46, "overview": "A", "poster": "https://p/a.jpg", "backdrop": null},
          {"imdbId": "tt2", "type": "TV_SHOW", "title": "Beta", "year": null, "rating": null, "overview": "B", "poster": null, "backdrop": "https://b/b.jpg"},
          {"imdbId": "tt3", "type": "OTHER", "title": "Gamma", "overview": "C"}
        ]}
        """
        let page = StreamingTitles.decode(Data(json.utf8))
        XCTAssertEqual(page?.available, true)
        XCTAssertEqual(page?.totalPages, 5)
        XCTAssertEqual(page?.items.map(\.id), ["tt1", "tt2"])
        XCTAssertEqual(page?.items.map(\.type), ["movie", "series"])
        XCTAssertEqual(page?.items.first?.releaseInfo, "2020")
        XCTAssertEqual(page?.items.first?.imdbRating, "7.5")
        XCTAssertEqual(page?.items.last?.background, "https://b/b.jpg")
    }

    func testNoSourceForAServiceIsNotAvailable() {
        let page = StreamingTitles.decode(Data(#"{"available": false, "items": [], "page": 1, "totalPages": 0}"#.utf8))
        XCTAssertEqual(page, StreamingTitlesPage(available: false, items: [], totalPages: 0))
        XCTAssertNil(StreamingTitles.decode(Data("nope".utf8)))
    }

    func testTheRegionIsTheMacsCountryElseTheUS() {
        XCTAssertEqual(StreamingTitles.region(Locale(identifier: "en_AU")), "AU")
        XCTAssertEqual(StreamingTitles.region(Locale(identifier: "pt_BR")), "BR")
        XCTAssertEqual(StreamingTitles.region(Locale(identifier: "en")), "US")
    }
}

final class WashColorTests: XCTestCase {
    private func pixels(_ count: Int, _ r: UInt8, _ g: UInt8, _ b: UInt8, alpha: UInt8 = 255) -> [UInt8] {
        Array((0..<count).map { _ in [r, g, b, alpha] }.joined())
    }

    func testAMostlyRedPictureGivesARedLightWithItsBrightestChannelAt200() {
        let color = WashColor.compute(rgba: pixels(100, 200, 40, 30))
        XCTAssertNotNil(color)
        XCTAssertEqual(color?.r ?? 0, 200, accuracy: 0.5)
        XCTAssertLessThan(color?.g ?? 255, 80)
    }

    func testBlackWhiteAndGreyPicturesGiveNoColour() {
        XCTAssertNil(WashColor.compute(rgba: pixels(100, 10, 10, 10)))
        XCTAssertNil(WashColor.compute(rgba: pixels(100, 240, 240, 240)))
        XCTAssertNil(WashColor.compute(rgba: pixels(100, 120, 120, 120)))
        XCTAssertNil(WashColor.compute(rgba: []))
    }

    func testSeeThroughPixelsAreIgnored() {
        XCTAssertNil(WashColor.compute(rgba: pixels(100, 200, 40, 30, alpha: 50)))
        let mixed = pixels(50, 30, 30, 200) + pixels(50, 200, 40, 30, alpha: 0)
        XCTAssertGreaterThan(WashColor.compute(rgba: mixed)?.b ?? 0, 150)
    }
}


final class NextToWatchTests: XCTestCase {
    private func episode(_ season: Int, _ number: Int, released: String? = nil) -> EpisodeInfo {
        EpisodeInfo(id: "tt1:\(season):\(number)", title: nil, name: nil, season: season, episode: number, released: released, thumbnail: nil, overview: nil)
    }

    private let seasons: [Int: [EpisodeInfo]] = [
        0: [EpisodeInfo(id: "sp", title: nil, name: nil, season: 0, episode: 1, released: nil, thumbnail: nil, overview: nil)],
        1: [EpisodeInfo(id: "a", title: nil, name: nil, season: 1, episode: 1, released: nil, thumbnail: nil, overview: nil),
            EpisodeInfo(id: "b", title: nil, name: nil, season: 1, episode: 2, released: nil, thumbnail: nil, overview: nil)],
        2: [EpisodeInfo(id: "c", title: nil, name: nil, season: 2, episode: 1, released: nil, thumbnail: nil, overview: nil)]
    ]
    private func watched(_ keys: String...) -> [String: EpisodeStatus] {
        Dictionary(uniqueKeysWithValues: keys.map { ($0, EpisodeStatus(watched: true, fraction: 1)) })
    }

    func testFinishingAnEpisodePointsAtTheNextOne() {
        XCTAssertEqual(EpisodeProgress.nextToWatch(seasons: seasons, statuses: [:], finished: (1, 1))?.id, "b")
        // the next season once one is done
        XCTAssertEqual(EpisodeProgress.nextToWatch(seasons: seasons, statuses: watched("1:1"), finished: (1, 2))?.id, "c")
    }

    func testAnEarlierEpisodeNotWatchedIsPickedUpWhenNothingIsLeftAfter() {
        XCTAssertEqual(EpisodeProgress.nextToWatch(seasons: seasons, statuses: watched("1:2"), finished: (2, 1))?.id, "a")
    }

    func testEverythingWatchedMeansTheShowCanLeave() {
        XCTAssertNil(EpisodeProgress.nextToWatch(seasons: seasons, statuses: watched("1:1", "1:2"), finished: (2, 1)))
        // specials do not hold a show in Continue Watching
        XCTAssertNil(EpisodeProgress.nextToWatch(seasons: seasons, statuses: watched("1:1", "2:1"), finished: (1, 2)))
    }

    func testAnEpisodeNotOutYetDoesNotHoldTheShow() {
        let future = ISO8601DateFormatter().string(from: Date().addingTimeInterval(86_400 * 30))
        var airing = seasons
        airing[2] = [episode(2, 1, released: future)]
        XCTAssertNil(EpisodeProgress.nextToWatch(seasons: airing, statuses: watched("1:1"), finished: (1, 2)))
    }
}
