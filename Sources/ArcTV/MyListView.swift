import ArcTVCore
import SwiftUI

/// My List: the titles saved on the account, All or just the Watched ones, in the order you choose. Watched titles carry a green tick.
struct MyListView: View {
    @EnvironmentObject private var model: AppModel
    @State private var watchedOnly = false
    @State private var sort: ListSort = .recent

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                PageTitle(text: "My List")
                if let error = model.myListError, model.myList == nil {
                    Text(error).foregroundStyle(Theme.textSecondary).padding(.horizontal, 44)
                    Button("Try again") { Task { await model.loadMyList() } }
                        .buttonStyle(GlassButtonStyle())
                        .padding(.horizontal, 44)
                        .padding(.top, 12)
                } else if let all = model.myList {
                    controls
                    let shown = sort.apply(watchedOnly ? all.filter { $0.watched == true } : all)
                    if shown.isEmpty {
                        Text(watchedOnly
                             ? "Nothing watched yet. Titles you finish will show up here."
                             : "Your list is empty. Add titles from a title's page or Home's featured title to see them here.")
                            .foregroundStyle(Theme.textSecondary)
                            .padding(.horizontal, 44)
                    } else {
                        PosterGrid(items: shown.map(\.asPreview))
                    }
                } else {
                    ProgressView().controlSize(.large).frame(maxWidth: .infinity).padding(.top, 60)
                }
                Spacer().frame(height: 48)
            }
        }
        .task { await model.loadAccountData() }
    }

    private var controls: some View {
        HStack(spacing: 10) {
            ChoicePill(label: "All", selected: !watchedOnly) { watchedOnly = false }
            ChoicePill(label: "Watched", selected: watchedOnly) { watchedOnly = true }
            Spacer()
            Menu {
                ForEach(ListSort.allCases) { option in
                    Button(option.rawValue) { sort = option }
                }
            } label: {
                Label("Sort by: \(sort.rawValue)", systemImage: "arrow.up.arrow.down")
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
    }
}
