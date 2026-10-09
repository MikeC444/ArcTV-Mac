import ArcTVCore
import SwiftUI

/// Home: a big banner for the first title, then the rows.
struct HomeView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        content
    }

    @ViewBuilder
    private var content: some View {
        switch model.home {
        case .idle, .loading:
            LoadingView()
        case .empty:
            ComingSoonView(title: "Nothing to show yet", note: "Home couldn't load its rows. Check your connection, then open Settings and try again.")
        case let .loaded(rows):
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    if let featured = Self.featured(in: rows) {
                        HeroBanner(item: featured)
                    } else {
                        Spacer().frame(height: 90)
                    }
                    RowsStack(rows: rows)
                        .padding(.top, 8)
                        .padding(.bottom, 40)
                }
            }
        }
    }

    /// The first title that has wide artwork.
    static func featured(in rows: [HomeRow]) -> MetaPreview? {
        for row in rows {
            if let hit = row.items.first(where: { $0.background != nil && $0.description != nil }) { return hit }
        }
        return nil
    }
}

/// Movies or TV Shows: the same rows, only that kind of title.
struct BrowseView: View {
    @EnvironmentObject private var model: AppModel
    let title: String
    let type: String

    var body: some View {
        switch model.home {
        case .idle, .loading:
            LoadingView()
        case .empty:
            ComingSoonView(title: "Nothing to show yet", note: "The rows couldn't load. Check your connection and try again.")
        case let .loaded(rows):
            let mine = rows.filter { $0.spec.type == type }
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    Text(title)
                        .font(.system(size: 34, weight: .heavy))
                        .foregroundStyle(Theme.textPrimary)
                        .padding(.horizontal, 44)
                        .padding(.top, 96)
                        .padding(.bottom, 12)
                    RowsStack(rows: mine)
                        .padding(.bottom, 40)
                }
            }
        }
    }
}

struct RowsStack: View {
    let rows: [HomeRow]

    var body: some View {
        LazyVStack(alignment: .leading, spacing: 26) {
            ForEach(rows) { row in
                HomeRowView(row: row)
            }
        }
    }
}

struct HeroBanner: View {
    let item: MetaPreview

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            Rectangle().fill(Theme.surface)
            if let background = item.background, let url = URL(string: background) {
                AsyncImage(url: url) { phase in
                    if case let .success(image) = phase {
                        image.resizable().aspectRatio(contentMode: .fill)
                    }
                }
            }
            // Fades into the page at the bottom and darkens the left so the text can be read, like the web app's hero.
            LinearGradient(colors: [.clear, Theme.background], startPoint: .center, endPoint: .bottom)
            LinearGradient(colors: [Theme.background.opacity(0.85), .clear], startPoint: .leading, endPoint: .center)

            VStack(alignment: .leading, spacing: 12) {
                if let logo = item.logo, let url = URL(string: logo) {
                    AsyncImage(url: url) { phase in
                        switch phase {
                        case let .success(image):
                            image.resizable().aspectRatio(contentMode: .fit)
                        default:
                            titleText
                        }
                    }
                    .frame(maxWidth: 360, maxHeight: 110, alignment: .leading)
                } else {
                    titleText
                }

                HStack(spacing: 12) {
                    if let year = item.releaseInfo { Text(year) }
                    if let rating = item.imdbRating { Label(rating, systemImage: "star.fill").labelStyle(.titleAndIcon) }
                    if let genres = item.genres, !genres.isEmpty { Text(genres.prefix(3).joined(separator: " · ")) }
                }
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Theme.textSecondary)

                if let description = item.description {
                    Text(description)
                        .font(.system(size: 15))
                        .foregroundStyle(Theme.textPrimary.opacity(0.9))
                        .lineLimit(3)
                        .frame(maxWidth: 520, alignment: .leading)
                }

                HStack(spacing: 12) {
                    Button { } label: { Label("Play", systemImage: "play.fill") }
                        .buttonStyle(BrandButtonStyle())
                        .disabled(true)
                    Button { } label: { Label("More info", systemImage: "info.circle") }
                        .buttonStyle(GlassButtonStyle())
                        .disabled(true)
                    Text("Playback is coming soon")
                        .font(.system(size: 13))
                        .foregroundStyle(Theme.textTertiary)
                }
                .padding(.top, 4)
            }
            .padding(.horizontal, 44)
            .padding(.bottom, 34)
        }
        .frame(height: 470)
        .frame(maxWidth: .infinity)
        .clipped()
    }

    private var titleText: some View {
        Text(item.name)
            .font(.system(size: 44, weight: .heavy))
            .foregroundStyle(Theme.textPrimary)
            .lineLimit(2)
            .shadow(color: .black.opacity(0.6), radius: 8, y: 2)
    }
}

struct HomeRowView: View {
    let row: HomeRow

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(row.spec.title)
                .font(.system(size: 20, weight: .bold))
                .foregroundStyle(Theme.textPrimary)
                .padding(.horizontal, 44)
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(alignment: .top, spacing: 16) {
                    ForEach(row.items) { item in
                        PosterCard(item: item)
                    }
                }
                .padding(.horizontal, 44)
                .padding(.vertical, 12)
            }
        }
    }
}

struct PosterCard: View {
    let item: MetaPreview
    @State private var hovering = false

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            ZStack {
                RoundedRectangle(cornerRadius: 10).fill(Theme.surface)
                if let poster = item.poster, let url = URL(string: poster) {
                    AsyncImage(url: url) { phase in
                        switch phase {
                        case let .success(image):
                            image.resizable().aspectRatio(contentMode: .fill)
                        default:
                            initial
                        }
                    }
                } else {
                    initial
                }
            }
            .frame(width: 156, height: 234)
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.white.opacity(hovering ? 0.9 : 0), lineWidth: 2))
            .shadow(color: .black.opacity(hovering ? 0.55 : 0), radius: 14, y: 6)
            .scaleEffect(hovering ? 1.05 : 1)
            .animation(.easeOut(duration: 0.15), value: hovering)

            Text(item.name)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Theme.textPrimary)
                .lineLimit(1)
                .frame(width: 156, alignment: .leading)
            if let year = item.releaseInfo {
                Text(year)
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.textTertiary)
                    .lineLimit(1)
                    .frame(width: 156, alignment: .leading)
            }
        }
        .onHover { hovering = $0 }
    }

    private var initial: some View {
        Text(String(item.name.prefix(1)))
            .font(.system(size: 44, weight: .bold))
            .foregroundStyle(Theme.textTertiary)
    }
}

struct LoadingView: View {
    var body: some View {
        VStack {
            Spacer()
            ProgressView().controlSize(.large)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }
}

struct ComingSoonView: View {
    let title: String
    let note: String

    var body: some View {
        VStack(spacing: 8) {
            Spacer()
            Text(title)
                .font(.system(size: 28, weight: .heavy))
                .foregroundStyle(Theme.textPrimary)
            Text(note)
                .foregroundStyle(Theme.textSecondary)
                .multilineTextAlignment(.center)
            Spacer()
        }
        .padding(.horizontal, 44)
        .frame(maxWidth: .infinity)
    }
}
