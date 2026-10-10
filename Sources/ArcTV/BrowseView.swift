import ArcTVCore
import SwiftUI

/// What a Movies / TV Shows page has loaded so far, kept until the app closes: coming back from a title finds the same titles in the same order.
@MainActor
private enum PagerCache {
    struct Snapshot {
        var items: [MetaPreview]
        var page: Int
        var hasMore: Bool
    }

    static var store: [String: Snapshot] = [:]
}

/// Loads Movies or TV Shows a page at a time, as you scroll, from every addon the account has (the web app's pager).
@MainActor
final class BrowseModel: ObservableObject {
    @Published var items: [MetaPreview] = []
    @Published var loading = true

    let type: String
    private var genre: String?
    private var sources: [HomeSource] = []
    private var page = 1
    private var hasMore = true
    private var generation = 0
    private var fetching = false
    private var seen = Set<String>()

    init(type: String) {
        self.type = type
    }

    private var cacheKey: String { "\(type)|\(genre ?? "")|\(sources.map(\.manifest.id).joined(separator: ","))" }

    /// First page of whatever is chosen now (or what was already loaded for it).
    func reload(sources next: [HomeSource], genre nextGenre: String?) async {
        sources = next
        genre = nextGenre
        generation += 1
        fetching = false
        if let hit = PagerCache.store[cacheKey] {
            items = hit.items
            page = hit.page
            hasMore = hit.hasMore
            seen = Set(hit.items.map(\.id))
            loading = false
            return
        }
        items = []
        seen = []
        page = 1
        hasMore = true
        loading = true
        guard !next.isEmpty else {
            loading = false
            return
        }
        let current = generation
        let type = self.type
        let genre = nextGenre
        let lists = await withTaskGroup(of: (Int, [MetaPreview]).self) { group -> [[MetaPreview]] in
            for (index, source) in next.enumerated() { group.addTask { (index, await source.browsePage(type: type, genre: genre, page: 0)) } }
            var results = Array(repeating: [MetaPreview](), count: next.count)
            for await (index, found) in group { results[index] = found }
            return results
        }
        guard current == generation else { return }
        // Movies and shows are a shuffled browse page, so the same titles are not first every time.
        let merged = distinctByID(lists.flatMap { $0 }.shuffled())
        seen = Set(merged.map(\.id))
        items = merged
        if !merged.isEmpty { PagerCache.store[cacheKey] = .init(items: merged, page: page, hasMore: hasMore) }
        loading = false
    }

    func loadMore() async {
        guard hasMore, !fetching, !sources.isEmpty, !items.isEmpty else { return }
        fetching = true
        let current = generation
        let wantedPage = page
        let type = self.type
        let genre = self.genre
        let lists = await withTaskGroup(of: [MetaPreview].self) { group -> [[MetaPreview]] in
            for source in sources { group.addTask { await source.browsePage(type: type, genre: genre, page: wantedPage) } }
            var results: [[MetaPreview]] = []
            for await found in group { results.append(found) }
            return results
        }
        guard current == generation else { return }
        let fresh = distinctByID(lists.flatMap { $0 }.shuffled()).filter { !seen.contains($0.id) }
        if fresh.isEmpty {
            hasMore = false
        } else {
            page += 1
            fresh.forEach { seen.insert($0.id) }
            items += fresh
        }
        PagerCache.store[cacheKey] = .init(items: items, page: page, hasMore: hasMore)
        fetching = false
    }
}

/// The "All genres" pill beside the page title: it opens a two-column list of genres with a tick on the chosen one.
struct GenrePicker: View {
    let genres: [String]
    @Binding var selection: String?
    @State private var open = false

    var body: some View {
        Button { open.toggle() } label: {
            HStack(spacing: 8) {
                Text(selection ?? "All genres").font(.system(size: 15, weight: .medium))
                Image(systemName: open ? "chevron.up" : "chevron.down").font(.system(size: 12, weight: .semibold))
            }
            .foregroundStyle(Theme.textPrimary)
            .padding(.horizontal, 18)
            .frame(height: 38)
            .background(Capsule().fill(open ? Color.white.opacity(0.1) : Color(hex: 0x08080A).opacity(0.35)))
            .overlay(Capsule().stroke(Color.white.opacity(open ? 1 : 0.55), lineWidth: 1))
        }
        .buttonStyle(.plain)
        .popover(isPresented: $open, arrowEdge: .bottom) {
            VStack(alignment: .leading, spacing: 8) {
                row("All genres", selected: selection == nil, bold: true) { pick(nil) }
                Divider().overlay(Theme.divider)
                LazyVGrid(columns: [GridItem(.fixed(170), spacing: 20), GridItem(.fixed(170))], alignment: .leading, spacing: 2) {
                    ForEach(genres, id: \.self) { genre in row(genre, selected: selection == genre, bold: false) { pick(genre) } }
                }
            }
            .padding(16)
            .frame(width: 410)
            .background(Color(hex: 0x17171A))
        }
    }

    private func pick(_ genre: String?) {
        open = false
        selection = genre
    }

    private func row(_ title: String, selected: Bool, bold: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                Text(title).font(.system(size: bold ? 16 : 14, weight: bold || selected ? .bold : .regular)).foregroundStyle(Theme.textPrimary)
                Spacer(minLength: 8)
                if selected { Image(systemName: "checkmark").font(.system(size: 12, weight: .bold)).foregroundStyle(Theme.accent) }
            }
            .padding(.horizontal, 10)
            .frame(height: 34)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

/// Movies or TV Shows, laid out like the web app's: the title with a genre picker beside it, Featured / Highest Rated / Newest, then a poster grid
/// that keeps loading as you scroll.
struct BrowseView: View {
    @EnvironmentObject private var appModel: AppModel
    let title: String
    let type: String
    @StateObject private var browse: BrowseModel
    @State private var sort: BrowseSort = .featured
    @State private var genre: String?

    init(title: String, type: String) {
        self.title = title
        self.type = type
        _browse = StateObject(wrappedValue: BrowseModel(type: type))
    }

    private var options: [String] {
        let blocked = Set(appModel.blockedGenres.map { $0.lowercased() })
        return (type == "movie" ? Genres.movies : Genres.shows).filter { !blocked.contains($0.lowercased()) }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .center, spacing: 18) {
                    Text(title)
                        .font(.system(size: 34, weight: .heavy))
                        .foregroundStyle(Theme.textPrimary)
                    GenrePicker(genres: options, selection: $genre)
                    Spacer()
                }
                .padding(.horizontal, 44)
                .padding(.top, 96)
                .padding(.bottom, 12)

                if browse.loading && browse.items.isEmpty {
                    skeletonPills
                    GridSkeleton()
                } else if appModel.catalogSources.isEmpty && browse.items.isEmpty {
                    Text("No addons installed. Add an addon in Settings to bring movies and TV shows into Arc TV.")
                        .foregroundStyle(Theme.textSecondary)
                        .padding(.horizontal, 44)
                } else {
                    if !browse.items.isEmpty {
                        HStack(spacing: 10) {
                            ForEach(BrowseSort.allCases) { option in
                                ChoicePill(label: option.rawValue, selected: sort == option) { sort = option }
                            }
                        }
                        .padding(.horizontal, 44)
                        .padding(.bottom, 18)
                    }
                    if browse.items.isEmpty {
                        Text(genre.map { "No \($0) \(title.lowercased()) found right now." } ?? "Nothing to show here right now.")
                            .foregroundStyle(Theme.textSecondary)
                            .padding(.horizontal, 44)
                    } else {
                        PosterGrid(items: sort.apply(browse.items.withoutBlocked(appModel.blockedGenres))) {
                            Task { await browse.loadMore() }
                        }
                    }
                }
                Spacer().frame(height: 48)
            }
        }
        .task(id: "\(appModel.catalogSources.map(\.manifest.id))|\(genre ?? "")") {
            await browse.reload(sources: appModel.catalogSources, genre: genre)
        }
    }

    private var skeletonPills: some View {
        HStack(spacing: 8) {
            ForEach([78.0, 118.0, 76.0], id: \.self) { width in Shimmer(cornerRadius: 15).frame(width: width, height: 30) }
        }
        .padding(.horizontal, 44)
        .padding(.bottom, 12)
    }
}
