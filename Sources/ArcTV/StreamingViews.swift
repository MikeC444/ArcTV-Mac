import AppKit
import ArcTVCore
import SwiftUI

/// Home's streaming services: one tile for each service an installed addon has titles for (Netflix, Disney+ ...). A tile opens that service's page.
/// The row has no heading (it is still labelled for screen readers), as on the web and Fire TV apps.
struct StreamingTilesRow: View {
    @EnvironmentObject private var model: AppModel
    let tiles: [StreamingService]

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            LazyHStack(spacing: 16) {
                ForEach(tiles) { service in
                    StreamingTile(service: service) { model.openStreaming(service.id) }
                }
            }
            .padding(.horizontal, 44)
            // Room above and below for each tile's coloured light, which the scroll view would cut off at its edge; the negative padding outside
            // gives the space back, so the row sits where it did.
            .padding(.vertical, 24)
        }
        .padding(.vertical, -12)
        .accessibilityLabel("Streaming services")
    }
}

/// How a service's tile looks (the web app's `BRAND` table): the colour its app icon sits on (or a gradient), whether its logo is drawn all white or all
/// black on that colour (nil shows the logo as it is), and the colour of the light beneath it at rest and under the pointer.
private struct TileBrand {
    var background: UInt32
    var gradient: [UInt32]? = nil
    var gradientStart = UnitPoint.top
    var gradientEnd = UnitPoint.bottom
    var logo: LogoTint? = nil
    var glow: UInt32
    var hover: Double
    var rest: Double

    enum LogoTint { case white, black }

    /// A service with no entry is a black tile with its name in white.
    static func of(_ id: String) -> TileBrand? {
        switch id {
        case "netflix": return TileBrand(background: 0x000000, glow: 0xE50914, hover: 0.55, rest: 0.12)
        case "disney": return TileBrand(background: 0x003F4F, gradient: [0x011828, 0x002F3D, 0x015E70, 0x0098A5, 0x2BBCC1], logo: nil, glow: 0x1EBEC8, hover: 0.55, rest: 0.14)
        case "prime": return TileBrand(background: 0x1D2547, gradient: [0x141721, 0x1D2547, 0x294071, 0x346B9F, 0x4089C0], gradientStart: UnitPoint(x: 0, y: 0.6), gradientEnd: UnitPoint(x: 1, y: 0.4), logo: .white, glow: 0x4089C0, hover: 0.6, rest: 0.24)
        case "max": return TileBrand(background: 0xFFFFFF, glow: 0x8C5AFF, hover: 0.5, rest: 0.26)
        case "apple": return TileBrand(background: 0x000000, glow: 0xBEBECD, hover: 0.4, rest: 0.16)
        case "paramount": return TileBrand(background: 0x0064FF, logo: .white, glow: 0x0064FF, hover: 0.6, rest: 0.28)
        case "hulu": return TileBrand(background: 0x1CE783, logo: .white, glow: 0x1CE783, hover: 0.5, rest: 0.12)
        case "peacock": return TileBrand(background: 0x000000, glow: 0xFFBE28, hover: 0.4, rest: 0.12)
        case "crunchyroll": return TileBrand(background: 0xF47521, logo: .white, glow: 0xF47521, hover: 0.6, rest: 0.16)
        case "skyshowtime": return TileBrand(background: 0x4A38E6, gradient: [0x6A3DF0, 0x2B2FE0], gradientStart: .topLeading, gradientEnd: .bottomTrailing, logo: nil, glow: 0x6A3DF0, hover: 0.6, rest: 0.3)
        case "britbox": return TileBrand(background: 0x0D273D, glow: 0x78BEEB, hover: 0.5, rest: 0.16)
        case "itvx": return TileBrand(background: 0xDFEB55, logo: .black, glow: 0xDFEB55, hover: 0.5, rest: 0.12)
        case "iplayer": return TileBrand(background: 0x000000, glow: 0xFF4696, hover: 0.5, rest: 0.16)
        case "sky": return TileBrand(background: 0xFFFFFF, glow: 0xA05AFF, hover: 0.5, rest: 0.24)
        case "discovery": return TileBrand(background: 0x000000, glow: 0xFF963C, hover: 0.5, rest: 0.14)
        case "shudder": return TileBrand(background: 0x000000, glow: 0xDC141E, hover: 0.55, rest: 0.12)
        case "channel4": return TileBrand(background: 0x000000, glow: 0xAAFF8C, hover: 0.45, rest: 0.1)
        default: return nil
        }
    }

    var fill: AnyShapeStyle {
        if let gradient {
            let stops = gradient.enumerated().map { index, hex in
                Gradient.Stop(color: Color(hex: hex), location: gradient.count > 1 ? Double(index) / Double(gradient.count - 1) : 0)
            }
            return AnyShapeStyle(LinearGradient(stops: stops, startPoint: gradientStart, endPoint: gradientEnd))
        }
        return AnyShapeStyle(Color(hex: background))
    }
}

/// The logo pictures, decoded once.
private enum StreamingLogos {
    private static let lock = NSLock()
    private static var cache: [String: NSImage] = [:]

    static func image(_ id: String) -> NSImage? {
        lock.lock()
        defer { lock.unlock() }
        if let known = cache[id] { return known }
        guard let text = StreamingLogoData.base64[id], let data = Data(base64Encoded: text), let image = NSImage(data: data) else { return nil }
        cache[id] = image
        return image
    }
}

/// One tile: the service's logo on its own colour (its name in white on black when it has no logo), a glass slab with a coloured light beneath it that
/// grows and lifts under the pointer, as on the web app.
private struct StreamingTile: View {
    let service: StreamingService
    let action: () -> Void
    @State private var hovering = false

    /// The tile's size (16:9, about 20% bigger than it first was).
    private static let width: CGFloat = 264
    private static let height: CGFloat = 149

    var body: some View {
        let brand = TileBrand.of(service.id)
        let glow = Color(hex: brand?.glow ?? 0xFFFFFF)
        Button(action: action) {
            ZStack {
                RoundedRectangle(cornerRadius: 14).fill(brand?.fill ?? AnyShapeStyle(Color.black))
                // the glass: a bright top edge and a darker bottom edge
                RoundedRectangle(cornerRadius: 14)
                    .fill(LinearGradient(colors: [Color.white.opacity(0.16), .clear, Color.black.opacity(0.22)], startPoint: .top, endPoint: .bottom))
                logo(brand)
            }
            .frame(width: Self.width, height: Self.height)
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.white.opacity(hovering ? 0.8 : 0.14), lineWidth: hovering ? 2 : 1))
            .shadow(color: glow.opacity(hovering ? (brand?.hover ?? 0.5) : (brand?.rest ?? 0.15)), radius: hovering ? 11 : 6, y: hovering ? 5 : 3)
            .scaleEffect(hovering ? 1.04 : 1)
            .animation(.easeOut(duration: 0.15), value: hovering)
            .contentShape(RoundedRectangle(cornerRadius: 14))
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help(service.name)
    }

    @ViewBuilder
    private func logo(_ brand: TileBrand?) -> some View {
        if let image = StreamingLogos.image(service.id) {
            switch brand?.logo {
            case .white?:
                Image(nsImage: image).renderingMode(.template).resizable().scaledToFit().foregroundStyle(.white)
                    .padding(.horizontal, Self.width * 0.18).padding(.vertical, Self.height * 0.14)
                    .shadow(color: .black.opacity(0.35), radius: 4, y: 3)
            case .black?:
                Image(nsImage: image).renderingMode(.template).resizable().scaledToFit().foregroundStyle(.black)
                    .padding(.horizontal, Self.width * 0.18).padding(.vertical, Self.height * 0.14)
                    .shadow(color: .black.opacity(0.25), radius: 4, y: 3)
            case nil:
                Image(nsImage: image).resizable().scaledToFit()
                    .padding(.horizontal, Self.width * 0.18).padding(.vertical, Self.height * 0.14)
                    .shadow(color: .black.opacity(0.35), radius: 4, y: 3)
            }
        } else {
            Text(service.name)
                .font(.system(size: 24, weight: .heavy))
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .padding(.horizontal, 14)
        }
    }
}

/// Loads one service's titles from the addons that have it, then more a page at a time as you scroll: first what the addons page through (only an addon
/// whose catalogue can skip has any), then, once they have no more, TMDB's list for the service (the Streaming Catalogs addon lists about 100 titles a
/// catalogue and has no paging), a page of movies and of series at a time, as the web and Fire TV apps do.
@MainActor
final class StreamingModel: ObservableObject {
    @Published var items: [MetaPreview] = []
    @Published var loading = true
    /// More titles may still arrive by scrolling: the grid shows grey poster shapes after the last title.
    @Published var moreComing = true
    /// Netflix's page: the Top 10 row (nothing for any other service).
    @Published var topTen: TopTenState = .none

    let service: String
    /// One page of TMDB's titles for this service ("movie" or "series", page from 1).
    private let tmdbPage: (String, Int) async -> StreamingTitlesPage
    /// A title's genres (looked up through the addons), for leaving blocked genres out of the Top 10; the genres blocked now.
    private let genresOf: @Sendable (MetaPreview) async -> [String]?
    private let blockedGenres: () -> Set<String>
    private var sources: [HomeSource] = []
    private var page = 1
    private var nextTmdbPage = 1
    private var hasMore = true
    private var fetching = false
    private var generation = 0
    private var seen = Set<String>()

    init(service: String, tmdbPage: @escaping (String, Int) async -> StreamingTitlesPage,
         genresOf: @escaping @Sendable (MetaPreview) async -> [String]?, blockedGenres: @escaping () -> Set<String>) {
        self.service = service
        self.tmdbPage = tmdbPage
        self.genresOf = genresOf
        self.blockedGenres = blockedGenres
        // Netflix's page starts with the Top 10's grey posters showing (not nothing until the load begins), so the grey cells below do not appear first
        // and the page jump down when the row arrives.
        topTen = service == TopTen.service ? .loading : .none
    }

    /// The Top 10's titles, which the list under it leaves out so nothing shows twice.
    var topTenIDs: Set<String> {
        if case let .ready(titles) = topTen { return Set(titles.map(\.id)) }
        return []
    }

    /// One answer per service, country and set of blocked genres for the session, so coming back to the page does not ask again.
    @MainActor private enum TopTenCache {
        static var store: [String: [MetaPreview]] = [:]
    }

    /// Works out the Top 10 row: TMDB's first page of movies and of series for the service, ten of them in turn, blocked genres left out (their genres are
    /// looked up, as TMDB sends none). Starts at once when the page opens, beside the titles.
    private func loadTopTen(generation current: Int) async {
        let blocked = blockedGenres()
        let key = "\(service):\(StreamingTitles.region()):\(blocked.sorted().joined(separator: ","))"
        if let hit = TopTenCache.store[key] {
            if current == generation { topTen = .ready(hit) }
            return
        }
        async let movies = tmdbPage("movie", 1)
        async let shows = tmdbPage("series", 1)
        let (foundMovies, foundShows) = await (movies, shows)
        let picked: [MetaPreview]
        if blocked.isEmpty {
            picked = TopTen.pick(movies: foundMovies.items, shows: foundShows.items)
        } else {
            let candidates = TopTen.rankedPool(movies: foundMovies.items, shows: foundShows.items, limit: TopTen.pool)
            picked = await TopTen.pickUnblocked(candidates, blocked: blocked, count: TopTen.count, genresOf: genresOf)
        }
        if !picked.isEmpty { TopTenCache.store[key] = picked }
        guard current == generation else { return }
        topTen = picked.isEmpty ? .none : .ready(picked)
    }

    func reload(sources next: [HomeSource]) async {
        let wanted = self.service
        sources = next.filter { $0.streamingServiceIDs.contains(wanted) }
        generation += 1
        fetching = false
        items = []
        seen = []
        page = 1
        nextTmdbPage = 1
        hasMore = true
        moreComing = true
        loading = true
        let current = generation
        let hasTopTen = self.service == TopTen.service
        topTen = hasTopTen ? .loading : .none
        if hasTopTen { Task { await self.loadTopTen(generation: current) } }
        guard !sources.isEmpty else {
            loading = false
            moreComing = false
            if hasTopTen, topTen == .loading { topTen = .none }
            return
        }
        let service = self.service
        let lists = await withTaskGroup(of: (Int, [MetaPreview]).self) { group -> [[MetaPreview]] in
            for (index, source) in sources.enumerated() { group.addTask { (index, await source.serviceItems(service)) } }
            var results = Array(repeating: [MetaPreview](), count: sources.count)
            for await (index, found) in group { results[index] = found }
            return results
        }
        guard current == generation else { return }
        // The titles wait for the Top 10 (up to 6 seconds), so it does not pull ten titles out of the list after the list is on screen.
        var waited = 0
        while hasTopTen, topTen == .loading, waited < 60, current == generation {
            try? await Task.sleep(nanoseconds: 100_000_000)
            waited += 1
        }
        guard current == generation else { return }
        let merged = distinctByID(HomeSections.interleaved(lists))
        seen = Set(merged.map(\.id))
        items = merged
        loading = false
    }

    func loadMore() async {
        guard hasMore, !fetching, !sources.isEmpty, !items.isEmpty else { return }
        fetching = true
        let current = generation
        let wantedPage = page
        let service = self.service
        let lists = await withTaskGroup(of: [MetaPreview].self) { group -> [[MetaPreview]] in
            for source in sources { group.addTask { await source.moreServiceItems(service, page: wantedPage) } }
            var results: [[MetaPreview]] = []
            for await found in group { results.append(found) }
            return results
        }
        guard current == generation else { return }
        var fresh = distinctByID(HomeSections.interleaved(lists)).filter { !seen.contains($0.id) }
        var exhausted = false
        if fresh.isEmpty {
            // The addons have no more: carry on with TMDB's list, a page of movies and of series at a time (up to four tries to find titles not shown yet).
            var tries = 0
            while tries < 4, fresh.isEmpty {
                tries += 1
                let at = nextTmdbPage
                async let movies = tmdbPage("movie", at)
                async let shows = tmdbPage("series", at)
                let (foundMovies, foundShows) = await (movies, shows)
                guard current == generation else { return }
                if !foundMovies.available && !foundShows.available { break }
                nextTmdbPage += 1
                fresh = distinctByID(interleave(foundMovies.items, foundShows.items)).filter { !seen.contains($0.id) }
                if at >= max(foundMovies.totalPages, foundShows.totalPages) {
                    exhausted = true
                    break
                }
            }
        }
        if fresh.isEmpty {
            hasMore = false
        } else {
            page += 1
            fresh.forEach { seen.insert($0.id) }
            items += fresh
            if exhausted { hasMore = false }
        }
        moreComing = hasMore
        fetching = false
    }
}

/// A streaming service's page, opened from its Home tile: that service's titles in a poster grid that keeps loading as you scroll. Home (or any
/// other place in the top bar) closes it.
struct StreamingServiceView: View {
    @EnvironmentObject private var model: AppModel
    let service: StreamingService
    @StateObject private var browse: StreamingModel

    init(service: StreamingService, model: AppModel) {
        self.service = service
        _browse = StateObject(wrappedValue: StreamingModel(
            service: service.id,
            tmdbPage: { type, page in await model.streamingTitles(service: service.id, type: type, page: page) },
            genresOf: { item in await model.genres(of: item) },
            blockedGenres: { model.blockedGenres }
        ))
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .center, spacing: 14) {
                    Button { model.streamingService = nil } label: {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 15, weight: .bold))
                            .foregroundStyle(Theme.textPrimary)
                            .frame(width: 38, height: 38)
                            .background(Circle().fill(Color.white.opacity(0.1)))
                            .contentShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .help("Back to Home")
                    Text(service.name)
                        .font(.system(size: 34, weight: .heavy))
                        .foregroundStyle(Theme.textPrimary)
                    Spacer()
                }
                .padding(.horizontal, 44)
                .padding(.top, 96)
                .padding(.bottom, 14)

                if service.id == TopTen.service {
                    // Netflix's page: the Top 10, then the titles as wide pictures (the Top 10's own titles left out)
                    TopTenSection(state: browse.topTen)
                    let listed = browse.items.withoutBlocked(model.blockedGenres).filter { !browse.topTenIDs.contains($0.id) }
                    if browse.loading && browse.items.isEmpty {
                        WideGridSkeleton()
                    } else if listed.isEmpty {
                        Text("Your addons didn't return any \(service.name) titles right now.")
                            .foregroundStyle(Theme.textSecondary)
                            .padding(.horizontal, 44)
                    } else {
                        WideGrid(items: listed, placeholders: browse.moreComing) { Task { await browse.loadMore() } }
                    }
                } else if browse.loading && browse.items.isEmpty {
                    GridSkeleton()
                } else if browse.items.isEmpty {
                    Text("Your addons didn't return any \(service.name) titles right now.")
                        .foregroundStyle(Theme.textSecondary)
                        .padding(.horizontal, 44)
                } else {
                    PosterGrid(items: browse.items.withoutBlocked(model.blockedGenres), onLastAppear: {
                        Task { await browse.loadMore() }
                    }, placeholders: browse.moreComing)
                }
                Spacer().frame(height: 48)
            }
        }
        .task(id: model.catalogSources.map(\.manifest.id)) {
            await browse.reload(sources: model.catalogSources)
        }
        .onChange(of: model.catalogSources.isEmpty) { _ in
            // No installed addon has the service any more: back to Home.
            if !model.availableStreamingServices.contains(service.id) { model.streamingService = nil }
        }
    }
}
