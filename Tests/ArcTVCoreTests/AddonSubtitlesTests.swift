import XCTest
@testable import ArcTVCore

final class AddonSubtitlesTests: XCTestCase {
    private func manifest(_ resources: [AddonResource], types: [String]? = nil, idPrefixes: [String]? = nil) -> AddonManifest {
        AddonManifest(id: "a", name: "Subs", types: types, idPrefixes: idPrefixes, resources: resources)
    }

    func testOnlyAddonsListingSubtitlesAreAsked() {
        XCTAssertFalse(manifest([AddonResource(name: "catalog"), AddonResource(name: "meta")]).offersSubtitles(type: "movie", id: "tt1"))
        XCTAssertTrue(manifest([AddonResource(name: "stream"), AddonResource(name: "subtitles")]).offersSubtitles(type: "movie", id: "tt1"))
    }

    func testResourceTypesAndPrefixesNarrowThenTheManifestsApply() {
        XCTAssertFalse(manifest([AddonResource(name: "subtitles", types: ["series"], idPrefixes: ["tt"])]).offersSubtitles(type: "movie", id: "tt1"))
        XCTAssertFalse(manifest([AddonResource(name: "subtitles", types: ["movie"], idPrefixes: ["kitsu"])]).offersSubtitles(type: "movie", id: "tt1"))
        XCTAssertTrue(manifest([AddonResource(name: "subtitles")], types: ["movie"], idPrefixes: ["tt"]).offersSubtitles(type: "movie", id: "tt1"))
        XCTAssertFalse(manifest([AddonResource(name: "subtitles")], types: ["series"]).offersSubtitles(type: "movie", id: "tt1"))
    }

    func testLanguageKeysAndNames() {
        for raw in ["eng", "en", "en-US", "English", "ENG"] { XCTAssertEqual(SubtitleLanguage.key(raw), "en", raw) }
        XCTAssertEqual(SubtitleLanguage.key("fre"), "fr")
        XCTAssertEqual(SubtitleLanguage.key("pt-BR"), "pt")
        XCTAssertNil(SubtitleLanguage.key("zzz"))
        XCTAssertEqual(SubtitleLanguage.displayName("spa"), "Spanish")
        XCTAssertEqual(SubtitleLanguage.displayName("zzz"), "ZZZ")
        XCTAssertEqual(SubtitleLanguage.displayName(nil), "Unknown")
    }

    func testEntriesKeepOnlyWebAddressesOnceEach() {
        let raw = [
            RawSubtitle(url: "https://a/1.srt", lang: "fre"), RawSubtitle(url: "ftp://a/2.srt", lang: "eng"), RawSubtitle(url: "https://a/1.srt", lang: "fre"),
            RawSubtitle(url: "https://a/3.srt", lang: "eng"), RawSubtitle(url: nil, lang: "eng")
        ]
        XCTAssertEqual(AddonSubtitles.entries(from: raw, addonName: "Subs").map(\.url), ["https://a/1.srt", "https://a/3.srt"])
    }

    func testRankingPutsThePreferredLanguageFirstAndCapsEachLanguage() {
        let files = AddonSubtitles.entries(
            from: [RawSubtitle(url: "https://a/1", lang: "fre"), RawSubtitle(url: "https://a/3", lang: "eng"), RawSubtitle(url: "https://a/4", lang: "eng")],
            addonName: "Subs"
        )
        XCTAssertEqual(AddonSubtitles.rank(files, preferredLanguage: "en").map(\.languageName), ["English", "English", "French"])
        XCTAssertEqual(AddonSubtitles.rank(files, preferredLanguage: "fr").map(\.languageName), ["French", "English", "English"])
        XCTAssertEqual(AddonSubtitles.rank(files, preferredLanguage: "en", perLanguage: 1).map(\.url), ["https://a/3", "https://a/1"])
    }

    func testAnswerWithOddEntriesStillDecodes() throws {
        let json = #"{"subtitles":[{"id":"1","url":"https://a/1.srt","lang":"eng"},{"url":5},{}]}"#.data(using: .utf8)!
        let decoded = try JSONDecoder().decode(SubtitlesResponse.self, from: json)
        XCTAssertEqual(AddonSubtitles.entries(from: decoded.subtitles ?? [], addonName: "Subs").count, 1)
    }
}
