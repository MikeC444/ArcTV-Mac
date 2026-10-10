import AppKit
import ArcTVCore
import SwiftUI

@MainActor
final class SearchModel: ObservableObject {
    enum State: Equatable {
        case idle
        case searching
        /// `loading` while slower addons are still answering.
        case results(movies: [MetaPreview], tvShows: [MetaPreview], loading: Bool)
        case none(query: String)
        case error(String)
    }

    @Published var state: State = .idle
    @Published var recents: [String] = []
    private var generation = 0
    private var key = "ArcTVRecentSearches"

    func load(userID: String?) {
        key = "ArcTVRecentSearches-\(userID ?? "guest")"
        recents = UserDefaults.standard.stringArray(forKey: key) ?? []
    }

    func remember(_ query: String) {
        recents = RecentSearches.adding(query, to: recents)
        UserDefaults.standard.set(recents, forKey: key)
    }

    func forget(_ query: String) {
        recents.removeAll { $0 == query }
        UserDefaults.standard.set(recents, forKey: key)
    }

    func clearRecents() {
        recents = []
        UserDefaults.standard.set(recents, forKey: key)
    }

    func reset() {
        generation += 1
        state = .idle
    }

    func search(_ query: String, sources: [HomeSource]) async {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return }
        generation += 1
        let current = generation
        if sources.isEmpty {
            state = .none(query: q)
            return
        }
        // Keep the old results up until the new ones arrive.
        if case let .results(movies, shows, _) = state { state = .results(movies: movies, tvShows: shows, loading: true) } else { state = .searching }
        let total = sources.count
        let final = await CatalogSearch.search(sources: sources, query: q) { [weak self] progress in
            await self?.apply(progress, query: q, total: total, generation: current)
        }
        apply(final, query: q, total: total, generation: current)
    }

    private func apply(_ progress: SearchProgress, query: String, total: Int, generation current: Int) {
        guard current == generation else { return }
        if !progress.movies.isEmpty || !progress.tvShows.isEmpty {
            state = .results(movies: progress.movies, tvShows: progress.tvShows, loading: progress.pending > 0)
        } else if progress.pending > 0 {
            state = .searching
        } else if total > 0, progress.failed == total {
            state = .error("Couldn't reach your installed addons. Check your connection and try again.")
        } else {
            state = .none(query: query)
        }
    }
}

/// Search, laid out like the web app's: a round search box that searches as you type, suggestions under it, recent searches, then Movies and TV
/// Shows as their own grids.
struct SearchView: View {
    @EnvironmentObject private var appModel: AppModel
    @StateObject private var model = SearchModel()
    @State private var query = ""
    @State private var debounce: Task<Void, Never>?
    @State private var suggestionsOpen = false
    @State private var highlighted: Int?
    @State private var keyMonitor: Any?
    @FocusState private var focused: Bool

    private var shown: (movies: [MetaPreview], tvShows: [MetaPreview]) {
        guard case let .results(movies, shows, _) = model.state else { return ([], []) }
        return (movies.withoutBlocked(appModel.blockedGenres), shows.withoutBlocked(appModel.blockedGenres))
    }

    private var suggestions: [MetaPreview] { Array((shown.movies + shown.tvShows).prefix(5)) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                PageTitle(text: "Search")
                searchBox
                content
                Spacer().frame(height: 48)
            }
        }
        .onAppear {
            model.load(userID: appModel.scope)
            focused = true
            installKeys()
        }
        .onDisappear { removeKeys() }
        .onChange(of: query) { next in
            highlighted = nil
            typed(next)
        }
        .onChange(of: focused) { isFocused in if isFocused { suggestionsOpen = true } }
    }

    // MARK: Search box

    private var searchBox: some View {
        HStack(spacing: 12) {
            Image(systemName: "magnifyingglass").font(.system(size: 20)).foregroundStyle(Theme.textSecondary)
            TextField("Search movies and TV shows", text: $query)
                .textFieldStyle(.plain)
                .font(.system(size: 18))
                .foregroundStyle(Theme.textPrimary)
                .focused($focused)
                .onSubmit {
                    if let index = highlighted, suggestions.indices.contains(index), suggestionsOpen { pick(suggestions[index]) } else { runNow(query) }
                }
            if !query.isEmpty {
                Button {
                    query = ""
                    suggestionsOpen = false
                    focused = true
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(Theme.textSecondary)
                        .frame(width: 30, height: 30)
                        .background(Circle().fill(Theme.surfaceHigh))
                }
                .buttonStyle(.plain)
                .help("Clear search")
            }
        }
        .padding(.leading, 22)
        .padding(.trailing, 14)
        .frame(height: 56)
        .background(Capsule().fill(Theme.surface))
        .overlay(Capsule().stroke(focused ? Theme.accent : Theme.divider, lineWidth: focused ? 2 : 1))
        .frame(maxWidth: 900)
        .padding(.horizontal, 44)
        .padding(.vertical, 20)
        .zIndex(2)
        .overlay(alignment: .topLeading) {
            if suggestionsOpen, query.trimmingCharacters(in: .whitespaces).count >= 2, !suggestions.isEmpty {
                suggestionList
                    .padding(.horizontal, 44)
                    .offset(y: 86)
            }
        }
        .zIndex(2)
    }

    private var suggestionList: some View {
        VStack(spacing: 2) {
            ForEach(suggestions) { item in
                SuggestionRow(item: item, highlighted: highlighted == suggestions.firstIndex(where: { $0.id == item.id })) { pick(item) }
            }
        }
        .padding(8)
        .frame(maxWidth: 900)
        .background(RoundedRectangle(cornerRadius: 16).fill(Theme.elevated))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(Theme.divider, lineWidth: 1))
        .shadow(color: .black.opacity(0.6), radius: 24, y: 12)
    }

    // MARK: Results

    @ViewBuilder
    private var content: some View {
        switch model.state {
        case .idle:
            if !model.recents.isEmpty { recentSearches }
            Text("Search for movies and TV shows across your installed addons.")
                .font(.system(size: 14))
                .foregroundStyle(Theme.textSecondary)
                .padding(.horizontal, 44)
        case .searching:
            HStack(spacing: 10) {
                ProgressView().controlSize(.small)
                Text("Searching…").font(.system(size: 14)).foregroundStyle(Theme.textSecondary)
            }
            .padding(.horizontal, 44)
        case let .results(_, _, loading):
            let found = shown
            if found.movies.isEmpty && found.tvShows.isEmpty {
                noResults(query.trimmingCharacters(in: .whitespaces))
            } else {
                if !found.movies.isEmpty { resultGrid("Movies", found.movies) }
                if !found.tvShows.isEmpty { resultGrid("TV Shows", found.tvShows) }
                if loading {
                    HStack(spacing: 10) {
                        ProgressView().controlSize(.small)
                        Text("Still checking other addons…").font(.system(size: 13)).foregroundStyle(Theme.textSecondary)
                    }
                    .padding(.horizontal, 44)
                    .padding(.top, 16)
                }
            }
        case let .none(text):
            noResults(text)
        case let .error(message):
            Text(message).foregroundStyle(Theme.coralText).padding(.horizontal, 44)
        }
    }

    private func noResults(_ text: String) -> some View {
        VStack(spacing: 8) {
            Image(systemName: "magnifyingglass").font(.system(size: 40)).foregroundStyle(Theme.textTertiary)
            Text("No results").font(.system(size: 22, weight: .bold)).foregroundStyle(Theme.textPrimary)
            Text("Nothing found for \u{201C}\(text)\u{201D}. Try a different search.").foregroundStyle(Theme.textSecondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 50)
    }

    private func resultGrid(_ title: String, _ items: [MetaPreview]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(title).font(.system(size: 22, weight: .bold)).foregroundStyle(Theme.textPrimary)
                Text("\(items.count) \(items.count == 1 ? "result" : "results")").font(.system(size: 14)).foregroundStyle(Theme.textTertiary)
            }
            .padding(.horizontal, 44)
            PosterGrid(items: items)
        }
        .padding(.top, 20)
    }

    private var recentSearches: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text("Recent searches").font(.system(size: 17, weight: .semibold)).foregroundStyle(Theme.textPrimary)
                Spacer()
                Button("Clear") { model.clearRecents() }
                    .buttonStyle(.plain)
                    .font(.system(size: 14))
                    .foregroundStyle(Theme.textSecondary)
                    .underline()
            }
            .frame(maxWidth: 900)
            FlowRow(spacing: 10) {
                ForEach(model.recents, id: \.self) { term in
                    HStack(spacing: 0) {
                        Button { runNow(term) } label: {
                            HStack(spacing: 8) {
                                Image(systemName: "clock.arrow.circlepath").foregroundStyle(Theme.textTertiary)
                                Text(term).font(.system(size: 15, weight: .medium)).foregroundStyle(Theme.textPrimary)
                            }
                            .padding(.leading, 16)
                            .padding(.trailing, 8)
                            .frame(height: 40)
                        }
                        .buttonStyle(.plain)
                        Button { model.forget(term) } label: {
                            Image(systemName: "xmark").font(.system(size: 11, weight: .bold)).foregroundStyle(Theme.textTertiary).frame(width: 34, height: 40)
                        }
                        .buttonStyle(.plain)
                        .help("Remove from recent searches")
                    }
                    .background(RoundedRectangle(cornerRadius: 12).fill(Theme.surface))
                }
            }
        }
        .padding(.horizontal, 44)
        .padding(.bottom, 20)
    }

    // MARK: Actions

    /// Up and Down move through the suggestions while the box is focused and they are showing; Return opens the one marked, Escape closes them.
    private func installKeys() {
        guard keyMonitor == nil else { return }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            guard focused, suggestionsOpen, query.trimmingCharacters(in: .whitespaces).count >= 2, !suggestions.isEmpty else { return event }
            switch event.keyCode {
            case 125: // down
                highlighted = min(suggestions.count - 1, (highlighted ?? -1) + 1)
                return nil
            case 126: // up
                highlighted = (highlighted ?? 0) > 0 ? (highlighted ?? 0) - 1 : nil
                return nil
            case 53: // escape
                suggestionsOpen = false
                highlighted = nil
                return nil
            default:
                return event
            }
        }
    }

    private func removeKeys() {
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
        keyMonitor = nil
    }

    /// Search as you type: wait for a short pause, and never for a single letter.
    private func typed(_ text: String) {
        debounce?.cancel()
        suggestionsOpen = true
        let q = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if q.isEmpty {
            model.reset()
            return
        }
        guard q.count >= 2 else { return }
        debounce = Task {
            try? await Task.sleep(nanoseconds: 250_000_000)
            guard !Task.isCancelled else { return }
            await model.search(q, sources: appModel.catalogSources)
        }
    }

    private func runNow(_ text: String) {
        let q = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return }
        debounce?.cancel()
        query = q
        suggestionsOpen = false
        model.remember(q)
        Task { await model.search(q, sources: appModel.catalogSources) }
    }

    private func pick(_ item: MetaPreview) {
        model.remember(query)
        suggestionsOpen = false
        appModel.openDetail(item)
    }
}

private struct SuggestionRow: View {
    let item: MetaPreview
    var highlighted = false
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Color.clear
                    .frame(width: 34, height: 50)
                    .overlay {
                        if let poster = item.poster, let url = URL(string: poster) {
                            CachedImage(url: url)
                        }
                    }
                    .background(Theme.surfaceHigh)
                    .clipShape(RoundedRectangle(cornerRadius: 5))
                Text(item.name).font(.system(size: 16, weight: .bold)).foregroundStyle(Theme.textPrimary).lineLimit(1)
                Spacer(minLength: 12)
                Text((item.type == "movie" ? "Movie" : "TV Show") + (item.releaseInfo.map { " · \($0)" } ?? ""))
                    .font(.system(size: 14))
                    .foregroundStyle(Theme.textTertiary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .frame(minHeight: 44)
            .background(RoundedRectangle(cornerRadius: 10).fill(hovering || highlighted ? Theme.surfaceHigh : .clear))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}

/// Lays its children out left to right and wraps them onto new lines.
struct FlowRow: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        arrange(proposal.width ?? .infinity, subviews).size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = arrange(bounds.width, subviews)
        for (index, origin) in result.origins.enumerated() {
            subviews[index].place(at: CGPoint(x: bounds.minX + origin.x, y: bounds.minY + origin.y), proposal: .unspecified)
        }
    }

    private func arrange(_ width: CGFloat, _ subviews: Subviews) -> (size: CGSize, origins: [CGPoint]) {
        var origins: [CGPoint] = []
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        var widest: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > 0, x + size.width > width {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            origins.append(CGPoint(x: x, y: y))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
            widest = max(widest, x - spacing)
        }
        return (CGSize(width: widest, height: y + rowHeight), origins)
    }
}
