import XCTest
@testable import ArcTVCore

final class TopTenTests: XCTestCase {
    private func title(_ id: String, type: String = "movie") -> MetaPreview { MetaPreview(id: id, type: type, name: id) }
    private func movies(_ ids: String...) -> [MetaPreview] { ids.map { title($0) } }
    private func shows(_ ids: String...) -> [MetaPreview] { ids.map { title($0, type: "series") } }

    func testSeriesAndMoviesAreTakenInTurnASeriesFirstAndTenAreKept() {
        let ten = TopTen.pick(movies: movies("m1", "m2", "m3", "m4", "m5", "m6", "m7"), shows: shows("s1", "s2", "s3", "s4", "s5", "s6", "s7"))
        XCTAssertEqual(ten.map(\.id), ["s1", "m1", "s2", "m2", "s3", "m3", "s4", "m4", "s5", "m5"])
    }

    func testATitleInBothListsShowsOnceAndAShorterListIsCarriedOnByTheLongerOne() {
        XCTAssertEqual(TopTen.rankedPool(movies: movies("m1", "m2", "m3"), shows: shows("s1", "m1"), limit: 10).map(\.id), ["s1", "m1", "m2", "m3"])
        XCTAssertEqual(TopTen.rankedPool(movies: [], shows: [], limit: 10).map(\.id), [])
    }

    func testTitlesWithABlockedGenreAreLeftOutAndTheNextOnesTakeTheirPlace() async {
        let pool = (1...12).map { title("t\($0)") }
        let horror: Set<String> = ["t2", "t5"]
        let ten = await TopTen.pickUnblocked(pool, blocked: ["horror"], count: 10) { horror.contains($0.id) ? ["Horror"] : ["Drama"] }
        XCTAssertEqual(ten.map(\.id), ["t1", "t3", "t4", "t6", "t7", "t8", "t9", "t10", "t11", "t12"])
    }

    func testATitleWhoseGenresCannotBeFoundIsKept() async {
        let pool = [title("a"), title("b"), title("c")]
        let ten = await TopTen.pickUnblocked(pool, blocked: ["horror"], count: 3) { $0.id == "b" ? nil : ["Horror"] }
        XCTAssertEqual(ten.map(\.id), ["b"])
    }
}
