import ArcTVCore
import SwiftUI

struct HomeView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        VStack(spacing: 0) {
            header
            content
        }
        .task { await model.loadHome() }
    }

    private var header: some View {
        HStack {
            Text("Arc TV")
                .font(.title2.weight(.heavy))
                .foregroundStyle(Theme.accent)
            Spacer()
            if let name = model.session?.user.displayName ?? model.session?.user.email {
                Text(name).foregroundStyle(Theme.textSecondary)
            }
            Button("Refresh") { Task { await model.reloadHome() } }
            Button("Sign out") { Task { await model.signOut() } }
        }
        .padding(.horizontal, 28)
        .padding(.vertical, 14)
        .background(Theme.elevated)
    }

    @ViewBuilder
    private var content: some View {
        switch model.home {
        case .idle, .loading:
            VStack { Spacer(); ProgressView().controlSize(.large); Spacer() }
                .frame(maxWidth: .infinity)
        case .empty:
            VStack(spacing: 8) {
                Spacer()
                Text("Nothing to show yet").font(.title3).foregroundStyle(Theme.textPrimary)
                Text("Home couldn't load its rows. Check your connection and press Refresh.").foregroundStyle(Theme.textSecondary)
                Spacer()
            }
            .frame(maxWidth: .infinity)
        case let .loaded(rows):
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 26) {
                    ForEach(rows) { row in
                        HomeRowView(row: row)
                    }
                }
                .padding(.vertical, 24)
            }
        }
    }
}

struct HomeRowView: View {
    let row: HomeRow

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(row.spec.title)
                .font(.title3.weight(.bold))
                .foregroundStyle(Theme.textPrimary)
                .padding(.horizontal, 28)
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 14) {
                    ForEach(row.items) { item in
                        PosterCard(item: item)
                    }
                }
                .padding(.horizontal, 28)
            }
        }
    }
}

struct PosterCard: View {
    let item: MetaPreview

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ZStack {
                RoundedRectangle(cornerRadius: 10).fill(Theme.surface)
                if let poster = item.poster, let url = URL(string: poster) {
                    AsyncImage(url: url) { phase in
                        switch phase {
                        case let .success(image):
                            image.resizable().aspectRatio(contentMode: .fill)
                        default:
                            Text(String(item.name.prefix(1)))
                                .font(.largeTitle)
                                .foregroundStyle(Theme.textTertiary)
                        }
                    }
                } else {
                    Text(String(item.name.prefix(1)))
                        .font(.largeTitle)
                        .foregroundStyle(Theme.textTertiary)
                }
            }
            .frame(width: 150, height: 225)
            .clipShape(RoundedRectangle(cornerRadius: 10))
            Text(item.name)
                .font(.callout)
                .foregroundStyle(Theme.textPrimary)
                .lineLimit(1)
                .frame(width: 150, alignment: .leading)
        }
    }
}
