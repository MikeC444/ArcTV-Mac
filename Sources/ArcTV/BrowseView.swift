import ArcTVCore
import SwiftUI

/// Loads Movies or TV Shows a page at a time, as you scroll (the web app's pager).
@MainActor
final class BrowseModel: ObservableObject {
    @Published var items: [MetaPreview] = []
    @Published var loading = true
    @Published var failed = false

    let type: String
    private(set) var genre: String?
    private var hasMore = true
    private var generation = 0
    private var fetching = false
    private let client = AddonClient()

    init(type: String) {
        self.type = type
    }

    func setGenre(_ next: String?) async {
        genre = next
        await reload()
    }

    func reload() async {
        generation += 1
        items = []
        hasMore = true
        fetching = false
        failed = false
        loading = true
        await loadMore()
    }

    func loadMore() async {
        guard hasMore, !fetching else { return }
        fetching = true
        let current = generation
        defer { if current == generation { fetching = false } }
        do {
            let page = try await client.browse(manifestURL: AppInfo.cinemetaManifestURL, type: type, genre: genre, skip: items.count)
            guard current == generation else { return }
            let before = items.count
            items = distinctByID(items + page)
            if page.isEmpty || items.count == before { hasMore = false }
        } catch {
            guard current == generation else { return }
            if items.isEmpty { failed = true }
            hasMore = false
        }
        loading = false
    }
}

/// Movies or TV Shows, laid out like the web app's: a title, Featured / Highest Rated / Newest, a genre menu, then a poster grid that keeps loading.
struct BrowseView: View {
    @EnvironmentObject private var appModel: AppModel
    let title: String
    let type: String
    @StateObject private var browse: BrowseModel
    @State private var sort: BrowseSort = .featured
    @State private var genre: String? = nil

    init(title: String, type: String) {
        self.title = title
        self.type = type
        _browse = StateObject(wrappedValue: BrowseModel(type: type))
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                PageTitle(text: title)
                HStack(spacing: 10) {
                    ForEach(BrowseSort.allCases) { option in
                        ChoicePill(label: option.rawValue, selected: sort == option) { sort = option }
                    }
                    Spacer()
                    Menu {
                        Button("All genres") { genre = nil }
                        ForEach(Genres.all, id: \.self) { name in
                            Button(name) { genre = name }
                        }
                    } label: {
                        Label(genre ?? "All genres", systemImage: "line.3.horizontal.decrease")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(Theme.textPrimary)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)
                            .background(Capsule().fill(Color.white.opacity(0.1)))
                    }
                    .menuStyle(.borderlessButton)
                    .fixedSize()
                }
                .padding(.horizontal, 44)
                .padding(.bottom, 18)

                if browse.failed {
                    Text("Couldn't load titles. Check your connection, then pick another genre or tab and come back.")
                        .foregroundStyle(Theme.textSecondary)
                        .padding(.horizontal, 44)
                } else if browse.loading && browse.items.isEmpty {
                    ProgressView().controlSize(.large).frame(maxWidth: .infinity).padding(.top, 60)
                } else if browse.items.isEmpty {
                    Text("Nothing here yet.").foregroundStyle(Theme.textSecondary).padding(.horizontal, 44)
                } else {
                    PosterGrid(items: sort.apply(browse.items.withoutBlocked(appModel.blockedGenres))) {
                        Task { await browse.loadMore() }
                    }
                }
                Spacer().frame(height: 48)
            }
        }
        .task { await browse.reload() }
        .onChange(of: genre) { next in
            Task { await browse.setGenre(next) }
        }
    }
}
