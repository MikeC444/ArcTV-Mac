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
            .padding(.vertical, 12)
        }
        .accessibilityLabel("Streaming services")
    }
}

/// One tile: the service's name on a glass card tinted with its colour, lifting a little under the pointer.
private struct StreamingTile: View {
    let service: StreamingService
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            ZStack {
                RoundedRectangle(cornerRadius: 14)
                    .fill(LinearGradient(colors: [service.tint.opacity(0.55), Color(hex: 0x101014)], startPoint: .topLeading, endPoint: .bottomTrailing))
                Text(service.name)
                    .font(.system(size: 24, weight: .heavy))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    .padding(.horizontal, 14)
                    .shadow(color: .black.opacity(0.5), radius: 6, y: 2)
            }
            .frame(width: 220, height: 124)
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.white.opacity(hovering ? 0.9 : 0.14), lineWidth: hovering ? 2 : 1))
            .shadow(color: service.tint.opacity(hovering ? 0.45 : 0.2), radius: hovering ? 16 : 8, y: 6)
            .scaleEffect(hovering ? 1.04 : 1)
            .animation(.easeOut(duration: 0.15), value: hovering)
            .contentShape(RoundedRectangle(cornerRadius: 14))
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help(service.name)
    }
}

private extension StreamingService {
    /// The colour a tile leans towards (the well-known services have their own; the rest share the app's blue).
    var tint: Color {
        switch id {
        case "netflix": return Color(hex: 0xE50914)
        case "prime": return Color(hex: 0x00A8E1)
        case "apple": return Color(hex: 0x8E8E93)
        case "max": return Color(hex: 0x5B2EFF)
        case "disney": return Color(hex: 0x113CCF)
        case "paramount": return Color(hex: 0x0064FF)
        case "hulu": return Color(hex: 0x1CE783)
        case "peacock": return Color(hex: 0xF5C400)
        case "iplayer": return Color(hex: 0xFF4E98)
        case "shudder": return Color(hex: 0xD6001C)
        default: return Color(hex: 0x4A5BFF)
        }
    }
}

/// Loads one service's titles from the addons that have it, then more a page at a time as you scroll (only an addon whose catalogue can skip has any).
@MainActor
final class StreamingModel: ObservableObject {
    @Published var items: [MetaPreview] = []
    @Published var loading = true

    let service: String
    private var sources: [HomeSource] = []
    private var page = 1
    private var hasMore = true
    private var fetching = false
    private var generation = 0
    private var seen = Set<String>()

    init(service: String) {
        self.service = service
    }

    func reload(sources next: [HomeSource]) async {
        sources = next.filter { $0.streamingServiceIDs.contains(service) }
        generation += 1
        fetching = false
        items = []
        seen = []
        page = 1
        hasMore = true
        loading = true
        guard !sources.isEmpty else {
            loading = false
            return
        }
        let current = generation
        let service = self.service
        let lists = await withTaskGroup(of: (Int, [MetaPreview]).self) { group -> [[MetaPreview]] in
            for (index, source) in sources.enumerated() { group.addTask { (index, await source.serviceItems(service)) } }
            var results = Array(repeating: [MetaPreview](), count: sources.count)
            for await (index, found) in group { results[index] = found }
            return results
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
        let fresh = distinctByID(HomeSections.interleaved(lists)).filter { !seen.contains($0.id) }
        if fresh.isEmpty {
            hasMore = false
        } else {
            page += 1
            fresh.forEach { seen.insert($0.id) }
            items += fresh
        }
        fetching = false
    }
}

/// A streaming service's page, opened from its Home tile: that service's titles in a poster grid that keeps loading as you scroll. Home (or any
/// other place in the top bar) closes it.
struct StreamingServiceView: View {
    @EnvironmentObject private var model: AppModel
    let service: StreamingService
    @StateObject private var browse: StreamingModel

    init(service: StreamingService) {
        self.service = service
        _browse = StateObject(wrappedValue: StreamingModel(service: service.id))
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

                if browse.loading && browse.items.isEmpty {
                    GridSkeleton()
                } else if browse.items.isEmpty {
                    Text("Your addons didn't return any \(service.name) titles right now.")
                        .foregroundStyle(Theme.textSecondary)
                        .padding(.horizontal, 44)
                } else {
                    PosterGrid(items: browse.items.withoutBlocked(model.blockedGenres)) {
                        Task { await browse.loadMore() }
                    }
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
