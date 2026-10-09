import ArcTVCore
import SwiftUI

@MainActor
final class SearchModel: ObservableObject {
    enum State: Equatable {
        case idle
        case searching
        case results([MetaPreview])
        case none
    }

    @Published var state: State = .idle
    private var task: Task<Void, Never>?
    private let client = AddonClient()

    /// Search as you type: waits for a short pause, and never searches a single letter.
    func queryChanged(_ text: String) {
        task?.cancel()
        let query = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard query.count >= 2 else {
            state = .idle
            return
        }
        state = .searching
        task = Task {
            try? await Task.sleep(nanoseconds: 350_000_000)
            guard !Task.isCancelled else { return }
            let found = await client.search(manifestURL: AppInfo.cinemetaManifestURL, query: query)
            guard !Task.isCancelled else { return }
            state = found.isEmpty ? .none : .results(found)
        }
    }
}

/// Search: a box at the top and the matching movies and shows as a grid.
struct SearchView: View {
    @StateObject private var model = SearchModel()
    @State private var query = ""

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                PageTitle(text: "Search")
                HStack(spacing: 10) {
                    Image(systemName: "magnifyingglass").foregroundStyle(Theme.textTertiary)
                    TextField("Search movies and TV shows", text: $query)
                        .textFieldStyle(.plain)
                        .font(.system(size: 17))
                        .foregroundStyle(Theme.textPrimary)
                    if !query.isEmpty {
                        Button { query = "" } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(Theme.textTertiary) }
                            .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(RoundedRectangle(cornerRadius: 12).fill(Theme.surface))
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.divider, lineWidth: 1))
                .frame(maxWidth: 640)
                .padding(.horizontal, 44)
                .padding(.bottom, 20)

                switch model.state {
                case .idle:
                    Text("Type at least two letters to search.")
                        .foregroundStyle(Theme.textSecondary)
                        .padding(.horizontal, 44)
                case .searching:
                    ProgressView().controlSize(.large).frame(maxWidth: .infinity).padding(.top, 60)
                case .none:
                    Text("Nothing found for \u{201C}\(query)\u{201D}.")
                        .foregroundStyle(Theme.textSecondary)
                        .padding(.horizontal, 44)
                case let .results(items):
                    PosterGrid(items: items)
                }
                Spacer().frame(height: 48)
            }
        }
        .onChange(of: query) { next in model.queryChanged(next) }
    }
}
