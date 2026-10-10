import Foundation

/// One row on Home.
public struct HomeSection: Equatable, Identifiable, Sendable {
    public var id: String
    public var title: String
    public var items: [MetaPreview]

    public init(id: String, title: String, items: [MetaPreview]) {
        self.id = id
        self.title = title
        self.items = items
    }
}

/// What the person chose in Settings > Home Rows: the order of rows and the ones switched off (kept on the account's settings row).
public struct HomeRowPreferences: Equatable, Sendable {
    public var order: [String]
    public var hiddenRowIds: [String]

    public init(order: [String] = [], hiddenRowIds: [String] = []) {
        self.order = order
        self.hiddenRowIds = hiddenRowIds
    }
}

/// An addon that can fill Home: where it is and what its manifest declares.
public struct HomeSource: Sendable {
    public var manifestURL: String
    public var manifest: AddonManifest

    public init(manifestURL: String, manifest: AddonManifest) {
        self.manifestURL = manifestURL
        self.manifest = manifest
    }

    public var catalogs: [CatalogDefinition] { (manifest.catalogs ?? []).filter { $0.type == "movie" || $0.type == "series" } }
}

/// Home's rows, built from the account's addons the way the web and Fire TV apps build them. A port of `StremioAddonProvider.getHomeSections`:
/// an addon shaped like Cinemeta (catalogues "top", "year" and "imdbRating") gets Popular, New, Top rated (movies and shows together, each drawn
/// from a different page each day, gently reshuffled) and then only the genres with wide appeal; any other addon gets its base catalogue and a row
/// for every genre it declares.
public enum HomeSections {
    /// Chance of reading page 1, 2 or 3 (100 titles each) of a ranking today: mostly the top, sometimes deeper. New releases go stale faster.
    static let pageWeights: [Double] = [5, 3, 2]
    static let newPageWeights: [Double] = [6, 4]
    static let pageSize = 100
    static let maxGenreRows = 30
    /// Rows are fetched in small batches so the first rows appear fast and shared free addon servers aren't hammered.
    static let batchSize = 4

    /// Whether an addon is shaped like Cinemeta.
    static func isRanked(_ catalogs: [CatalogDefinition]) -> Bool {
        let ids = Set(catalogs.map(\.id))
        return ids.contains("top") && ids.contains("year") && ids.contains("imdbRating")
    }

    static func isYear(_ text: String) -> Bool {
        guard text.allSatisfy(\.isNumber), let value = Int(text) else { return false }
        return value >= 1900 && value <= 2100
    }

    /// The rows an addon would show, in the order they are fetched. `fetch` answers one catalogue request.
    public static func load(source: HomeSource, seed: String, now: Date = Date(), client: AddonClient = AddonClient(),
                            onBatch: @escaping @Sendable ([HomeSection]) async -> Void) async {
        let fetcher = Fetcher(source: source, seed: seed, client: client)
        var jobs: [@Sendable () async -> HomeSection?] = []
        let catalogs = source.catalogs
        if catalogs.isEmpty { return }

        if isRanked(catalogs) {
            let top = catalogs.filter { $0.id == "top" }
            let title = top.compactMap(\.name).first ?? "Popular"
            jobs.append { await fetcher.varied(top, title: title, extra: [:], rowKey: "base", weights: pageWeights) }

            let yearCatalogs = catalogs.filter { $0.id == "year" }
            let years = Array(NSOrderedSet(array: yearCatalogs.flatMap(\.genreOptions).filter(isYear))).compactMap { $0 as? String }
            let thisYear = String(Calendar.current.component(.year, from: now))
            if let year = years.contains(thisYear) ? thisYear : years.first {
                jobs.append { await fetcher.varied(yearCatalogs, title: "New", extra: ["genre": year], rowKey: "new", weights: newPageWeights) }
            }
            let rated = catalogs.filter { $0.id == "imdbRating" }
            jobs.append { await fetcher.varied(rated, title: "Top rated", extra: [:], rowKey: "toprated", weights: pageWeights) }

            for genre in HomeVariety.homeGenres(declared: declaredGenres(catalogs).filter { !isYear($0) }) {
                let matching = catalogs.filter { $0.genreOptions.contains(genre) }
                jobs.append { await fetcher.varied(matching, title: genre, extra: ["genre": genre], rowKey: genre, weights: pageWeights) }
            }
        } else {
            let base = catalogs.filter(\.isBase)
            if !base.isEmpty {
                let title = base.compactMap(\.name).first ?? source.manifest.name
                jobs.append { await fetcher.merged(base, title: title, extra: [:], rowKey: "base") }
            }
            for genre in declaredGenres(catalogs) {
                let matching = catalogs.filter { $0.genreOptions.contains(genre) }
                jobs.append { await fetcher.merged(matching, title: genre, extra: ["genre": genre], rowKey: genre) }
            }
        }

        var index = 0
        while index < jobs.count {
            let slice = Array(jobs[index..<min(index + batchSize, jobs.count)])
            let ready = await withTaskGroup(of: (Int, HomeSection?).self) { group -> [HomeSection] in
                for (offset, job) in slice.enumerated() { group.addTask { (offset, await job()) } }
                var found: [(Int, HomeSection)] = []
                for await (offset, section) in group { if let section { found.append((offset, section)) } }
                return found.sorted { $0.0 < $1.0 }.map(\.1)
            }
            if !ready.isEmpty { await onBatch(ready) }
            index += batchSize
        }
    }

    static func declaredGenres(_ catalogs: [CatalogDefinition]) -> [String] {
        let all = catalogs.flatMap(\.genreOptions)
        return Array(Array(NSOrderedSet(array: all)).compactMap { $0 as? String }.prefix(maxGenreRows))
    }

    /// movie[0], series[0], movie[1], ... so a merged row reads as mixed content.
    static func interleaved(_ lists: [[MetaPreview]]) -> [MetaPreview] {
        if lists.count == 1 { return lists[0] }
        var out: [MetaPreview] = []
        for index in 0..<(lists.map(\.count).max() ?? 0) {
            for list in lists where index < list.count { out.append(list[index]) }
        }
        return out
    }

    private struct Fetcher: Sendable {
        let source: HomeSource
        let seed: String
        let client: AddonClient

        func safe(_ catalog: CatalogDefinition, _ extra: [String: String]) async -> [MetaPreview] {
            (try? await client.fetchCatalog(manifestURL: source.manifestURL, type: catalog.type, catalogId: catalog.id, extra: extra)) ?? []
        }

        func rowID(_ rowKey: String) -> String { "\(source.manifest.id)_\(rowKey)" }

        /// A row that reads today's page of its ranking (not always the first) and shuffles gently within it. Falls back to the first page if the
        /// chosen one is empty. Pages are only asked of catalogues that declare "skip".
        func varied(_ catalogs: [CatalogDefinition], title: String, extra: [String: String], rowKey: String, weights: [Double]) async -> HomeSection? {
            if catalogs.isEmpty { return nil }
            func read(_ page: Int) async -> [MetaPreview] {
                let lists = await withTaskGroup(of: (Int, [MetaPreview]).self) { group -> [[MetaPreview]] in
                    for (index, catalog) in catalogs.enumerated() {
                        let request = (page > 0 && catalog.supportsSkip) ? extra.merging(["skip": String(page * HomeSections.pageSize)]) { _, new in new } : extra
                        group.addTask { (index, await safe(catalog, request)) }
                    }
                    var results = Array(repeating: [MetaPreview](), count: catalogs.count)
                    for await (index, items) in group { results[index] = items }
                    return results
                }
                return distinctByID(HomeSections.interleaved(lists))
            }
            let id = rowID(rowKey)
            let page = HomeVariety.pickPage(seed: seed, rowKey: id, weights: weights)
            var items = await read(page)
            if items.isEmpty, page > 0 { items = await read(0) }
            if items.isEmpty { return nil }
            return HomeSection(id: id, title: title, items: HomeVariety.varyOrder(items, seed: seed, rowKey: id))
        }

        /// Every matched catalogue in parallel, interleaved.
        func merged(_ catalogs: [CatalogDefinition], title: String, extra: [String: String], rowKey: String) async -> HomeSection? {
            if catalogs.isEmpty { return nil }
            let lists = await withTaskGroup(of: (Int, [MetaPreview]).self) { group -> [[MetaPreview]] in
                for (index, catalog) in catalogs.enumerated() { group.addTask { (index, await safe(catalog, extra)) } }
                var results = Array(repeating: [MetaPreview](), count: catalogs.count)
                for await (index, items) in group { results[index] = items }
                return results
            }
            let items = distinctByID(HomeSections.interleaved(lists))
            return items.isEmpty ? nil : HomeSection(id: rowID(rowKey), title: title, items: items)
        }
    }
}

/// Rows keep the addon's order unless the person has reordered them; unranked rows sink below these well-known names.
private let defaultRowPriority = [
    "popular", "new", "top rated", "featured", "trending", "trending now", "new releases", "top 10 movies", "top 10 tv shows", "recently added",
    "action", "comedy", "horror", "romance", "thriller", "drama", "sci-fi", "science fiction", "fantasy", "mystery", "crime",
    "family", "kids", "children", "anime", "animation", "documentary", "music", "musical", "adventure"
]

private func defaultRank(_ section: HomeSection) -> Int {
    if section.id.hasSuffix("_base") { return -1 }
    return defaultRowPriority.firstIndex(of: section.title.trimmingCharacters(in: .whitespaces).lowercased()) ?? defaultRowPriority.count
}

/// The rows Home leads with by default: Popular, New and Top rated.
private func isLeadRow(_ section: HomeSection) -> Bool { ["_base", "_new", "_toprated"].contains { section.id.hasSuffix($0) } }
/// The two that arrived later, after people had chosen their rows: they go above those rows unless the person has placed them.
private func isNewLeadRow(_ section: HomeSection) -> Bool { ["_new", "_toprated"].contains { section.id.hasSuffix($0) } }

public extension Array where Element == HomeSection {
    /// The person's explicit order first, then everything else by default rank (stable). One exception: New or Top rated when the person has not
    /// placed it goes at the top, right after any lead rows they did place, instead of below everything they chose.
    func ordered(by preferences: HomeRowPreferences) -> [HomeSection] {
        let byID = Dictionary(map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let placed = preferences.order.compactMap { byID[$0] }
        let explicit = Set(preferences.order)
        let remaining = enumerated()
            .filter { !explicit.contains($0.element.id) }
            .map { (section: $0.element, index: $0.offset, rank: defaultRank($0.element)) }
            .sorted { $0.rank != $1.rank ? $0.rank < $1.rank : $0.index < $1.index }
            .map(\.section)
        let leadRows = remaining.filter(isNewLeadRow)
        if leadRows.isEmpty || placed.isEmpty { return placed + remaining }
        var at = 0
        while at < placed.count, isLeadRow(placed[at]) { at += 1 }
        let rest = remaining.filter { !isNewLeadRow($0) }
        return Array(placed[..<at]) + leadRows + Array(placed[at...]) + rest
    }

    /// A title appears in only one row: the first one (in the order shown) that holds it. A row left with nothing is dropped.
    func deduped() -> [HomeSection] {
        var seen = Set<String>()
        var out: [HomeSection] = []
        for section in self {
            let items = section.items.filter { seen.insert($0.id).inserted }
            if !items.isEmpty { out.append(HomeSection(id: section.id, title: section.title, items: items)) }
        }
        return out
    }
}

/// The titles the Home hero rotates through. The hero is a full-width picture, so a title whose only image is a portrait poster is mostly cropped
/// away: prefer titles with a real landscape background, and only fill up with the others when there aren't enough.
public enum HeroPool {
    public static func hasWideBackdrop(_ item: MetaPreview) -> Bool {
        guard let background = item.background, !background.isEmpty else { return false }
        return background != item.poster
    }

    public static func pickPool<G: RandomNumberGenerator>(_ pool: [MetaPreview], size: Int, using generator: inout G) -> [MetaPreview] {
        let wide = pool.filter(hasWideBackdrop).shuffled(using: &generator)
        if wide.count >= size { return Array(wide.prefix(size)) }
        let rest = pool.filter { !hasWideBackdrop($0) }
        let withImage = rest.filter { $0.background != nil || $0.poster != nil }.shuffled(using: &generator)
        let blank = rest.filter { $0.background == nil && $0.poster == nil }.shuffled(using: &generator)
        return Array((wide + withImage + blank).prefix(size))
    }

    /// `size` random titles from the rows the person has enabled; only when those hold fewer is the rest made up from `backup`.
    public static func pickTitles<G: RandomNumberGenerator>(enabled: [MetaPreview], backup: [MetaPreview], size: Int, using generator: inout G) -> [MetaPreview] {
        let own = pickPool(enabled, size: size, using: &generator)
        if own.count >= size { return own }
        let taken = Set(own.map(\.id))
        let extra = pickPool(backup.filter { !taken.contains($0.id) }, size: size - own.count, using: &generator)
        return (own + extra).shuffled(using: &generator)
    }
}
