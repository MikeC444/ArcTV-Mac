import ArcTVCore
import SwiftUI

/// My List: the titles saved on the account (read-only for now; saving from a title's page comes with details).
struct MyListView: View {
    @EnvironmentObject private var model: AppModel

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
                } else if let items = model.myList {
                    if items.isEmpty {
                        Text("Nothing saved yet. Titles you add to My List on any of your devices show up here.")
                            .foregroundStyle(Theme.textSecondary)
                            .padding(.horizontal, 44)
                    } else {
                        PosterGrid(items: items)
                    }
                } else {
                    ProgressView().controlSize(.large).frame(maxWidth: .infinity).padding(.top, 60)
                }
                Spacer().frame(height: 48)
            }
        }
        .task { await model.loadMyList() }
    }
}
