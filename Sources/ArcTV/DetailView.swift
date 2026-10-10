import ArcTVCore
import SwiftUI

/// A title's page: its artwork, what it is about, Play, and for a show the seasons and episodes.
struct DetailView: View {
    @EnvironmentObject private var model: AppModel
    let preview: MetaPreview
    @State private var detail: MetaDetail
    @State private var season: Int?

    private let height: CGFloat = 440

    init(preview: MetaPreview) {
        self.preview = preview
        _detail = State(initialValue: preview.asDetail)
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            Theme.background.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    hero
                    lower
                }
            }
            BackButton { model.goBack() }
                .padding(.leading, 28)
                .padding(.top, 22)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task { await loadFullDetails() }
    }

    private var isShow: Bool { detail.type == "series" }

    private var hero: some View {
        GeometryReader { geo in
            ZStack(alignment: .bottomLeading) {
                Theme.surface
                if let background = detail.background, let url = URL(string: background) {
                    AsyncImage(url: url) { phase in
                        if case let .success(image) = phase {
                            image.resizable().aspectRatio(contentMode: .fill)
                        }
                    }
                    .frame(width: geo.size.width, height: height)
                    .clipped()
                }
                LinearGradient(colors: [.clear, Theme.background], startPoint: .center, endPoint: .bottom)
                LinearGradient(colors: [Theme.background.opacity(0.85), .clear], startPoint: .leading, endPoint: .center)

                VStack(alignment: .leading, spacing: 12) {
                    if let logo = detail.logo, let url = URL(string: logo) {
                        AsyncImage(url: url) { phase in
                            switch phase {
                            case let .success(image): image.resizable().aspectRatio(contentMode: .fit)
                            default: titleText
                            }
                        }
                        .frame(maxWidth: 380, maxHeight: 120, alignment: .leading)
                    } else {
                        titleText
                    }
                    HStack(spacing: 12) {
                        if let year = detail.releaseInfo { Text(year) }
                        if let runtime = detail.runtime { Text(runtime) }
                        if let rating = detail.imdbRating { Label(rating, systemImage: "star.fill") }
                        if let genres = detail.genres, !genres.isEmpty { Text(genres.prefix(3).joined(separator: " · ")) }
                    }
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Theme.textSecondary)

                    if let description = detail.description {
                        Text(description)
                            .font(.system(size: 15))
                            .foregroundStyle(Theme.textPrimary.opacity(0.9))
                            .lineLimit(4)
                            .frame(maxWidth: 620, alignment: .leading)
                    }
                    Button(action: playMain) {
                        Label(playLabel, systemImage: "play.fill")
                    }
                    .buttonStyle(BrandButtonStyle())
                    .padding(.top, 4)
                }
                .padding(.horizontal, 44)
                .padding(.bottom, 28)
            }
            .frame(width: geo.size.width, height: height)
        }
        .frame(height: height)
    }

    private var titleText: some View {
        Text(detail.name)
            .font(.system(size: 42, weight: .heavy))
            .foregroundStyle(Theme.textPrimary)
            .lineLimit(2)
            .shadow(color: .black.opacity(0.6), radius: 8, y: 2)
    }

    @ViewBuilder
    private var lower: some View {
        VStack(alignment: .leading, spacing: 22) {
            if let director = detail.director, !director.isEmpty {
                fact("Director", director.joined(separator: ", "))
            }
            if let cast = detail.cast, !cast.isEmpty {
                fact("Cast", cast.prefix(10).joined(separator: ", "))
            }
            if isShow, !detail.seasonNumbers.isEmpty {
                episodes
            }
        }
        .padding(.horizontal, 44)
        .padding(.top, 8)
        .padding(.bottom, 48)
    }

    private func fact(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).font(.system(size: 13, weight: .bold)).foregroundStyle(Theme.textTertiary)
            Text(value).font(.system(size: 14)).foregroundStyle(Theme.textSecondary).frame(maxWidth: 760, alignment: .leading)
        }
    }

    private var currentSeason: Int { season ?? detail.seasonNumbers.first ?? 1 }

    private var episodes: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Episodes").font(.system(size: 22, weight: .bold)).foregroundStyle(Theme.textPrimary)
                Spacer()
                Menu {
                    ForEach(detail.seasonNumbers, id: \.self) { number in
                        Button(seasonName(number)) { season = number }
                    }
                } label: {
                    Label(seasonName(currentSeason), systemImage: "chevron.up.chevron.down")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Theme.textPrimary)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(Capsule().fill(Color.white.opacity(0.1)))
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
            }
            VStack(spacing: 8) {
                ForEach(detail.seasons[currentSeason] ?? []) { episode in
                    EpisodeRow(episode: episode) { playEpisode(episode) }
                }
            }
        }
    }

    private func seasonName(_ number: Int) -> String { number == 0 ? "Specials" : "Season \(number)" }

    private var playLabel: String {
        if isShow, let first = firstEpisode { return "Play S\(first.season ?? 1) E\(first.episode ?? 1)" }
        return "Play"
    }

    private var firstEpisode: EpisodeInfo? {
        guard let number = detail.seasonNumbers.first else { return nil }
        return detail.seasons[number]?.first
    }

    private func playMain() {
        if isShow {
            if let first = firstEpisode { playEpisode(first) }
        } else {
            model.openSources(PlayTarget(title: detail))
        }
    }

    private func playEpisode(_ episode: EpisodeInfo) {
        model.openSources(PlayTarget(title: detail, season: episode.season, episode: episode.episode, episodeTitle: "S\(episode.season ?? 0) E\(episode.episode ?? 0) \(episode.displayTitle)"))
    }

    /// The card only has the basics: the full answer adds cast, director and (for a show) the episodes.
    private func loadFullDetails() async {
        guard let full = try? await AddonClient().fetchMeta(manifestURL: AppInfo.cinemetaManifestURL, type: preview.type, id: preview.id) else { return }
        var merged = full
        merged.poster = full.poster ?? preview.poster
        merged.background = full.background ?? preview.background
        merged.logo = full.logo ?? preview.logo
        merged.description = full.description ?? preview.description
        detail = merged
    }
}

private struct EpisodeRow: View {
    let episode: EpisodeInfo
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(alignment: .top, spacing: 14) {
                Color.clear
                    .frame(width: 160, height: 90)
                    .overlay {
                        if let thumb = episode.thumbnail, let url = URL(string: thumb) {
                            AsyncImage(url: url) { phase in
                                if case let .success(image) = phase { image.resizable().aspectRatio(contentMode: .fill) }
                            }
                        }
                    }
                    .background(Theme.surface)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                VStack(alignment: .leading, spacing: 4) {
                    Text("\(episode.episode ?? 0). \(episode.displayTitle)")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Theme.textPrimary)
                        .lineLimit(1)
                    if let released = episode.released, released.count >= 10 {
                        Text(String(released.prefix(10))).font(.system(size: 12)).foregroundStyle(Theme.textTertiary)
                    }
                    if let overview = episode.overview {
                        Text(overview).font(.system(size: 13)).foregroundStyle(Theme.textSecondary).lineLimit(2)
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(8)
            .frame(maxWidth: 900, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 12).fill(hovering ? Color.white.opacity(0.08) : Theme.elevated))
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}

/// A "Back" pill; Esc does the same.
struct BackButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label("Back", systemImage: "chevron.left")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Theme.textPrimary)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(Capsule().fill(Color.black.opacity(0.55)))
                .overlay(Capsule().stroke(Color.white.opacity(0.15), lineWidth: 1))
        }
        .buttonStyle(.plain)
        .keyboardShortcut(.cancelAction)
    }
}
