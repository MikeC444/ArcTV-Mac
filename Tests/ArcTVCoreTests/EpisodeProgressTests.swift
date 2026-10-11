import XCTest
@testable import ArcTVCore

final class EpisodeProgressTests: XCTestCase {
    private func row(_ s: Int?, _ e: Int?, pos: Int64 = 0, dur: Int64 = 2_700_000, done: Bool = false, id: String = "tt1", type: String = "TV_SHOW") -> HistoryItem {
        HistoryItem(contentId: id, contentType: type, seasonNumber: s, episodeNumber: e, positionMs: pos, durationMs: dur, completed: done, watchedAt: "2026-10-11T10:00:00.000Z")
    }

    private func episode(_ s: Int, _ e: Int) -> EpisodeInfo {
        EpisodeInfo(id: "tt1:\(s):\(e)", title: "T\(e)", name: nil, season: s, episode: e, released: nil, thumbnail: nil, overview: nil)
    }

    func testFinishedEpisodesAreWatchedAndPartWayOnesHaveAFraction() {
        let result = EpisodeProgress.statuses(from: [row(1, 1, done: true), row(1, 2, pos: 900_000), row(1, 3, pos: 0)], contentId: "tt1")
        XCTAssertEqual(result["1:1"], EpisodeStatus(watched: true, fraction: 1))
        XCTAssertEqual(result["1:2"]?.watched, false)
        XCTAssertEqual(result["1:2"]?.fraction ?? 0, 1.0 / 3.0, accuracy: 0.001)
        XCTAssertNil(result["1:3"]) // never started (or marked not watched)
    }

    func testOtherTitlesMoviesAndRowsWithoutAnEpisodeAreIgnored() {
        let result = EpisodeProgress.statuses(
            from: [row(1, 1, done: true, id: "tt2"), row(nil, nil, done: true), row(1, 2, done: true, type: "MOVIE")], contentId: "tt1"
        )
        XCTAssertTrue(result.isEmpty)
    }

    func testTheNextEpisodeFollowsTheFurthestWatchedOne() {
        let seasons = [1: [episode(1, 1), episode(1, 2), episode(1, 3)], 2: [episode(2, 1), episode(2, 2)]]
        let watched = EpisodeStatus(watched: true, fraction: 1)
        XCTAssertNil(EpisodeProgress.nextEpisode(seasons: seasons, statuses: [:]))
        XCTAssertEqual(EpisodeProgress.nextEpisode(seasons: seasons, statuses: ["1:1": watched])?.episode, 2)
        // A gap is not filled: after E1 and E3, the next one is the one after E3.
        XCTAssertEqual(EpisodeProgress.nextEpisode(seasons: seasons, statuses: ["1:1": watched, "1:3": watched])?.id, "tt1:2:1")
        // A season caught up moves on to the next season.
        XCTAssertEqual(EpisodeProgress.nextEpisode(seasons: seasons, statuses: ["1:1": watched, "1:2": watched, "1:3": watched])?.season, 2)
        // The last episode being the furthest leaves nothing next.
        XCTAssertNil(EpisodeProgress.nextEpisode(seasons: seasons, statuses: ["2:2": watched]))
    }

    func testPartWayEpisodesDoNotMoveTheNextEpisodeOn() {
        let seasons = [1: [episode(1, 1), episode(1, 2)]]
        XCTAssertNil(EpisodeProgress.nextEpisode(seasons: seasons, statuses: ["1:1": EpisodeStatus(watched: false, fraction: 0.5)]))
    }

    func testEpisodeKeys() {
        XCTAssertEqual(EpisodeProgress.key(season: 2, episode: 5), "2:5")
        XCTAssertNil(EpisodeProgress.key(season: nil, episode: 5))
    }
}
