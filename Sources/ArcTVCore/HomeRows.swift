import Foundation

/// One row on Home: which catalogue of which addon it is made from.
public struct HomeRowSpec: Equatable, Identifiable, Sendable {
    public var id: String
    public var title: String
    public var type: String
    public var catalogId: String
    public var extra: [String: String]

    public init(id: String, title: String, type: String, catalogId: String, extra: [String: String] = [:]) {
        self.id = id
        self.title = title
        self.type = type
        self.catalogId = catalogId
        self.extra = extra
    }
}

public struct HomeRow: Equatable, Identifiable, Sendable {
    public var spec: HomeRowSpec
    public var items: [MetaPreview]
    public var id: String { spec.id }
}

public enum HomeRows {
    /// Cinemeta's shape, as on the other apps: Popular ("top"), New ("year", filtered to this year) and Top rated ("imdbRating").
    /// Stage 1 shows these for movies and shows; genre rows, the daily mix and "hide what you've seen" come with the account sync.
    public static func defaultRows(year: Int) -> [HomeRowSpec] {
        [
            HomeRowSpec(id: "popular-movie", title: "Popular movies", type: "movie", catalogId: "top"),
            HomeRowSpec(id: "popular-series", title: "Popular shows", type: "series", catalogId: "top"),
            HomeRowSpec(id: "new-movie", title: "New movies", type: "movie", catalogId: "year", extra: ["genre": String(year)]),
            HomeRowSpec(id: "toprated-movie", title: "Top rated movies", type: "movie", catalogId: "imdbRating"),
            HomeRowSpec(id: "toprated-series", title: "Top rated shows", type: "series", catalogId: "imdbRating")
        ]
    }

    /// Loads every row at once; a row that fails or comes back empty is left out rather than failing Home.
    public static func load(specs: [HomeRowSpec], manifestURL: String, client: AddonClient = AddonClient()) async -> [HomeRow] {
        await withTaskGroup(of: (Int, HomeRow?).self) { group in
            for (index, spec) in specs.enumerated() {
                group.addTask {
                    let items = try? await client.fetchCatalog(manifestURL: manifestURL, type: spec.type, catalogId: spec.catalogId, extra: spec.extra)
                    guard let items, !items.isEmpty else { return (index, nil) }
                    return (index, HomeRow(spec: spec, items: items))
                }
            }
            var found: [(Int, HomeRow)] = []
            for await (index, row) in group {
                if let row { found.append((index, row)) }
            }
            return found.sorted { $0.0 < $1.0 }.map { $0.1 }
        }
    }
}
