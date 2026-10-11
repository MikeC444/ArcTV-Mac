import XCTest
@testable import ArcTVCore

final class DownloadEpisodeLabelsTests: XCTestCase {
    private func episode(_ season: Int?, _ number: Int?, title: String? = nil) -> EpisodeInfo {
        EpisodeInfo(id: "tt1:\(season ?? 0):\(number ?? 0)", title: title, name: nil, season: season, episode: number, released: nil, thumbnail: nil, overview: nil)
    }

    func testSeasonLabelCountsEpisodes() {
        XCTAssertEqual(DownloadChoices.seasonLabel(season: 2, episodes: 8), "Season 2 · 8 episodes")
        XCTAssertEqual(DownloadChoices.seasonLabel(season: 1, episodes: 1), "Season 1 · 1 episode")
    }

    func testEpisodeLabelAndHeading() {
        let e = episode(1, 3, title: "Think About the Bubbles")
        XCTAssertEqual(DownloadChoices.episodeLabel(e), "3. Think About the Bubbles")
        XCTAssertEqual(DownloadChoices.episodeHeading(e), "S1 E3 Think About the Bubbles")
    }

    func testAnEpisodeWithNoTitleIsNamedByItsNumber() {
        XCTAssertEqual(DownloadChoices.episodeLabel(episode(2, 4)), "4. Episode 4")
    }
}
