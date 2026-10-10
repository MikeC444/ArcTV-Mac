import AppKit
import ArcTVCore
import SwiftUI

/// A title's page, laid out like the web app's: the artwork behind it, the logo, release date and length, genres, a short description, Play and
/// Trailer with a "more" button that opens Watched, My List, Like and Not for me, the IMDb rating in the corner, then (for a show) its seasons and
/// episodes, the cast and, for a movie, "You May Also Like".
struct DetailView: View {
    @EnvironmentObject private var model: AppModel
    let preview: MetaPreview
    @State private var detail: MetaDetail
    @State private var season: Int?
    @State private var expanded = false
    @State private var trailer: String?
    /// nil while the lookup runs, "" when there is none, else "yyyy-MM-dd".
    @State private var releaseDate: String?
    @State private var cast: [CastMember]

    init(preview: MetaPreview) {
        self.preview = preview
        _detail = State(initialValue: preview.asDetail)
        _cast = State(initialValue: [])
    }

    private var isShow: Bool { detail.type == "series" }

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .topLeading) {
                backdrop(size: geo.size)
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        hero
                        if isShow { below } else { movieBottom(width: geo.size.width) }
                    }
                    .frame(width: geo.size.width, alignment: .leading)
                    .frame(height: isShow ? nil : max(geo.size.height, 640), alignment: .top)
                    .frame(minHeight: geo.size.height, alignment: .top)
                }
                BackButton { model.goBack() }
                    .padding(.leading, 28)
                    .padding(.top, 22)
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
        .background(Theme.background.ignoresSafeArea())
        .task { await load() }
    }

    // MARK: Artwork

    /// The picture is cropped to the window, never the other way round: an uncropped picture would make the whole page wider than the window.
    private func backdrop(size: CGSize) -> some View {
        ZStack {
            Theme.surfaceHigh
            if let background = detail.background, let url = URL(string: background) {
                CachedImage(url: url)
                    .frame(width: size.width, height: size.height)
                    .clipped()
            }
            LinearGradient(colors: [Theme.background.opacity(0.55), Theme.background.opacity(0.2), .clear], startPoint: .leading, endPoint: .trailing)
            LinearGradient(stops: [.init(color: .clear, location: 0), .init(color: .clear, location: 0.45),
                                   .init(color: Theme.background.opacity(0.55), location: 0.8), .init(color: Theme.background.opacity(0.92), location: 1)],
                           startPoint: .top, endPoint: .bottom)
        }
        .frame(width: size.width, height: size.height)
        .clipped()
        .ignoresSafeArea()
    }

    // MARK: Hero

    /// The text starts below the top bar, the buttons come next with the IMDb rating at the far end of the same row, and the seasons (or the cast)
    /// follow straight after them.
    private var hero: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 0) {
                logoOrTitle
                if !facts.isEmpty {
                    Text(facts)
                        .font(.system(size: 16, weight: isShow ? .bold : .medium))
                        .foregroundStyle(.white)
                        .shadow(color: .black.opacity(0.6), radius: 4)
                        .padding(.top, 14)
                }
                if let genres = detail.genres, !genres.isEmpty {
                    Text(genres.joined(separator: "  ·  "))
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.white)
                        .shadow(color: .black.opacity(0.6), radius: 4)
                        .padding(.top, 6)
                }
                if let description = detail.description?.htmlDecoded {
                    Text(description)
                        .font(.system(size: isShow ? 16 : 15))
                        .foregroundStyle(.white)
                        .shadow(color: .black.opacity(0.6), radius: 4)
                        .lineLimit(isShow ? 4 : 2)
                        .frame(maxWidth: 640, alignment: .leading)
                        .padding(.top, 14)
                }
            }
            .frame(maxWidth: 800, alignment: .leading)

            HStack(alignment: .center) {
                actions
                Spacer(minLength: 24)
                if isShow, let rating = detail.imdbRating, !rating.isEmpty { ratingBox(rating) }
            }
            .padding(.top, 24)
        }
        .padding(.horizontal, 44)
        .padding(.top, 110)
        .padding(.bottom, 34)
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    private func ratingBox(_ rating: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "star.fill").foregroundStyle(Theme.accent).font(.system(size: 20))
            VStack(alignment: .leading, spacing: 0) {
                Text(rating).font(.system(size: 18, weight: .bold)).foregroundStyle(Theme.textPrimary)
                Text("IMDb Rating").font(.system(size: 11, weight: .medium)).foregroundStyle(Theme.textSecondary)
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 8)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color.black.opacity(0.45)))
    }

    @ViewBuilder
    private var logoOrTitle: some View {
        if let logo = detail.logo, let url = URL(string: logo) {
            CachedImage(url: url, contentMode: .fit) { titleText }
                .frame(maxWidth: 400, maxHeight: 110, alignment: .leading)
            .shadow(color: .black.opacity(0.6), radius: 8, y: 2)
        } else {
            titleText
        }
    }

    private var titleText: some View {
        Text(detail.name)
            .font(.system(size: 44, weight: .heavy))
            .foregroundStyle(Theme.textPrimary)
            .lineLimit(2)
            .shadow(color: .black.opacity(0.6), radius: 8, y: 2)
    }

    /// "Mar 5, 2024   2h 17m": the release date (or just the year while it is unknown) and how long it is.
    private var facts: String {
        let year = detail.year.map(String.init)
        let when: String?
        switch releaseDate {
        case nil: when = isShow ? year : nil
        case .some(""): when = year
        case let date?: when = Format.releaseDate(date) ?? year
        }
        let length = Format.runtimeMinutes(detail.runtime).map(Format.runtime(minutes:))
        return [when, length].compactMap { $0 }.joined(separator: "   ")
    }

    private var actions: some View {
        HStack(spacing: 14) {
            Button(action: playMain) { Label(playLabel, systemImage: "play.fill") }
                .buttonStyle(LightButtonStyle())
            Button {
                if let trailer, let url = URL(string: "https://www.youtube.com/watch?v=\(trailer)") { NSWorkspace.shared.open(url) }
            } label: { Label("Trailer", systemImage: "theatermasks") }
                .buttonStyle(GlassButtonStyle())
                .frame(height: 48)
                .disabled(trailer == nil)
                .help(trailer == nil ? "No trailer found for this title" : "Watch the trailer on YouTube")
            if expanded {
                HStack(spacing: 14) {
                    RoundIconButton(icon: model.isWatched(detail.id) ? "checkmark.circle.fill" : "checkmark.circle", on: model.isWatched(detail.id),
                                    help: model.isWatched(detail.id) ? "Remove from Watched" : "Mark as watched") { Task { await model.toggleWatched(detail) } }
                    RoundIconButton(icon: model.isSaved(detail.id) ? "checkmark" : "plus", on: model.isSaved(detail.id),
                                    help: model.isSaved(detail.id) ? "Remove from My List" : "Add to My List") { Task { await model.toggleSaved(detail) } }
                    if model.plus.active {
                        RoundIconButton(icon: model.rating(of: detail.id) == .like ? "hand.thumbsup.fill" : "hand.thumbsup", on: model.rating(of: detail.id) == .like,
                                        help: model.rating(of: detail.id) == .like ? "Remove like" : "Like") { Task { await model.rate(detail.preview, .like) } }
                        RoundIconButton(icon: model.rating(of: detail.id) == .dislike ? "hand.thumbsdown.fill" : "hand.thumbsdown", on: model.rating(of: detail.id) == .dislike,
                                        help: model.rating(of: detail.id) == .dislike ? "Remove Not for me" : "Not for me") { Task { await model.rate(detail.preview, .dislike) } }
                    }
                }
                .transition(.opacity.combined(with: .move(edge: .leading)))
            }
            RoundIconButton(icon: "ellipsis", on: expanded, help: "More options") {
                withAnimation(.easeOut(duration: 0.2)) { expanded.toggle() }
            }
        }
    }

    // MARK: Below the hero

    @ViewBuilder
    private var below: some View {
        VStack(alignment: .leading, spacing: 26) {
            if isShow, !detail.seasonNumbers.isEmpty { seasonsSection }
            if !cast.isEmpty { castSection() }
            
        }
        .padding(.bottom, 48)
    }

    /// A movie's bottom area: the cast on the left with the IMDb rating at the far right, and "You May Also Like" under them across the whole window.
    private func movieBottom(width: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 22) {
            HStack(alignment: .top) {
                if !cast.isEmpty { castSection(inset: 0) }
                Spacer(minLength: 24)
                if let rating = detail.imdbRating, !rating.isEmpty { ratingBox(rating) }
            }
            .padding(.horizontal, 44)
            if !similar.isEmpty { similarSection(inset: 44) }
        }
        .frame(maxHeight: .infinity, alignment: .bottom)
        .padding(.top, 20)
        .padding(.bottom, 36)
    }

    private var currentSeason: Int { season ?? resume?.seasonNumber.flatMap { detail.seasonNumbers.contains($0) ? $0 : nil } ?? detail.seasonNumbers.first ?? 1 }

    private var seasonsSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Seasons").font(.system(size: 22, weight: .bold)).foregroundStyle(Theme.textPrimary).padding(.horizontal, 44)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(detail.seasonNumbers, id: \.self) { number in
                        Button { season = number } label: {
                            Text("\(number)")
                                .font(.system(size: 16, weight: .bold))
                                .foregroundStyle(number == currentSeason ? Color.black : Theme.textSecondary)
                                .frame(width: 52, height: 52)
                                .background(Circle().fill(number == currentSeason ? Color.white : Color.white.opacity(0.12)))
                        }
                        .buttonStyle(.plain)
                        .help("Season \(number)")
                    }
                }
                .padding(.horizontal, 44)
            }
            let episodes = detail.seasons[currentSeason] ?? []
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text("Season \(currentSeason)").font(.system(size: 18, weight: .semibold)).foregroundStyle(Theme.textPrimary)
                Text("\(episodes.count) Episodes").font(.system(size: 14)).foregroundStyle(Theme.textTertiary)
            }
            .padding(.horizontal, 44)
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(alignment: .top, spacing: 16) {
                    ForEach(episodes) { episode in
                        EpisodeCard(episode: episode) { playEpisode(episode) }
                    }
                }
                .padding(.horizontal, 44)
                .padding(.vertical, 6)
            }
        }
    }

    private func castSection(inset: CGFloat = 44) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Cast").font(.system(size: 22, weight: .bold)).foregroundStyle(Theme.textPrimary).padding(.horizontal, inset)
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(alignment: .top, spacing: 20) {
                    ForEach(cast) { member in CastCard(member: member) }
                }
                .padding(.horizontal, inset)
            }
        }
    }

    /// Other titles from Home's rows, preferring ones that share a genre.
    private var similar: [MetaPreview] {
        let pool = distinctByID(model.homeRaw.flatMap(\.items)).filter { $0.id != detail.id }.withoutBlocked(model.blockedGenres)
        let mine = Set((detail.genres ?? []).map { $0.lowercased() })
        let matches = mine.isEmpty ? [] : pool.filter { item in (item.genres ?? []).contains { mine.contains($0.lowercased()) } }
        return Array((matches.isEmpty ? pool : matches).prefix(15))
    }

    private func similarSection(inset: CGFloat = 44) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("You May Also Like").font(.system(size: 22, weight: .bold)).foregroundStyle(Theme.textPrimary).padding(.horizontal, inset)
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(alignment: .top, spacing: 14) {
                    ForEach(similar) { item in SimilarCard(item: item) }
                }
                .padding(.leading, inset)
                .padding(.vertical, 6)
            }
        }
    }

    // MARK: Playing

    /// Where this title was left, from Continue Watching (a movie, or whichever episode of a show).
    private var resume: ContinueItem? { model.resumeItem(titleID: detail.id, season: nil, episode: nil) }

    private var playLabel: String {
        let verb = resume != nil ? "Resume" : "Play"
        if isShow, let episode = resumeEpisode ?? firstEpisode { return "\(verb) S\(episode.season ?? 1)E\(episode.episode ?? 1)" }
        return verb
    }

    private var resumeEpisode: EpisodeInfo? {
        guard let resume, let s = resume.seasonNumber, let e = resume.episodeNumber else { return nil }
        return detail.seasons[s]?.first { $0.episode == e }
    }

    private var firstEpisode: EpisodeInfo? {
        guard let number = detail.seasonNumbers.first else { return nil }
        return detail.seasons[number]?.first
    }

    private func playMain() {
        if let resume {
            let episode = resumeEpisode
            model.openSources(PlayTarget(
                title: detail, season: resume.seasonNumber, episode: resume.episodeNumber,
                episodeTitle: episode.map { "S\($0.season ?? 0) E\($0.episode ?? 0) \($0.displayTitle)" } ?? resume.episodeTitle,
                startAt: resume.positionSeconds
            ))
        } else if isShow {
            if let first = firstEpisode { playEpisode(first) }
        } else {
            model.openSources(PlayTarget(title: detail))
        }
    }

    private func playEpisode(_ episode: EpisodeInfo) {
        let start = model.resumeItem(titleID: detail.id, season: episode.season, episode: episode.episode)?.positionSeconds ?? 0
        model.openSources(PlayTarget(
            title: detail, season: episode.season, episode: episode.episode,
            episodeTitle: "S\(episode.season ?? 0) E\(episode.episode ?? 0) \(episode.displayTitle)", startAt: start
        ))
    }

    // MARK: Loading

    /// The card only has the basics: the full answer adds the cast and (for a show) the episodes. The trailer, release date and cast photos come
    /// from the account's server and are quiet when they are not there.
    private func load() async {
        trailer = await model.trailerID(for: preview)
        if let full = try? await AddonClient().fetchMeta(manifestURL: AppInfo.cinemetaManifestURL, type: preview.type, id: preview.id) {
            var merged = full
            merged.poster = full.poster ?? preview.poster
            merged.background = full.background ?? preview.background
            merged.logo = full.logo ?? preview.logo
            merged.description = full.description ?? preview.description
            merged.imdbRating = full.imdbRating ?? preview.imdbRating
            merged.genres = full.genres ?? preview.genres
            detail = merged
        }
        cast = detail.castMembers
        async let date: Void = loadReleaseDate()
        async let photos: Void = loadCastPhotos()
        _ = await (date, photos)
    }

    private func loadReleaseDate() async {
        guard !isShow else {
            releaseDate = ""
            return
        }
        let found = try? await model.authorized { client, token in try await client.releaseDate(accessToken: token, title: detail.name, year: detail.year) }
        releaseDate = found.flatMap { $0 } ?? ""
    }

    private func loadCastPhotos() async {
        guard detail.id.range(of: #"^tt\d+$"#, options: .regularExpression) != nil, cast.isEmpty || cast.contains(where: { $0.photoURL == nil }) else { return }
        guard let extra = try? await model.authorized({ client, token in try await client.castPhotos(accessToken: token, imdbID: detail.id, type: detail.type) }),
              !extra.isEmpty else { return }
        cast = CastMerge.merge(cast, extra)
    }
}

private struct EpisodeCard: View {
    let episode: EpisodeInfo
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 8) {
                Color.clear
                    .frame(width: 270, height: 152)
                    .overlay {
                        if let thumb = episode.thumbnail, let url = URL(string: thumb) {
                            AsyncImage(url: url) { phase in
                                if case let .success(image) = phase { image.resizable().aspectRatio(contentMode: .fill) }
                            }
                        }
                    }
                    .overlay {
                        Image(systemName: "play.fill")
                            .font(.system(size: 16))
                            .foregroundStyle(Theme.textPrimary)
                            .frame(width: 44, height: 44)
                            .background(Circle().fill(Color.black.opacity(0.55)))
                    }
                    .background(Theme.surfaceHigh)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.white.opacity(hovering ? 0.9 : 0), lineWidth: 2))
                    .scaleEffect(hovering ? 1.03 : 1)
                    .animation(.easeOut(duration: 0.15), value: hovering)
                Text("\(episode.episode ?? 0). \(episode.displayTitle)")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(1)
                    .frame(width: 270, alignment: .leading)
                if let overview = episode.overview, !overview.isEmpty {
                    Text(overview)
                        .font(.system(size: 13))
                        .foregroundStyle(Theme.textSecondary)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                        .frame(width: 270, alignment: .leading)
                }
            }
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}

private struct CastCard: View {
    let member: CastMember

    var body: some View {
        VStack(spacing: 4) {
            Color.clear
                .frame(width: 84, height: 84)
                .overlay {
                    if let photo = member.photoURL, let url = URL(string: photo) {
                        AsyncImage(url: url) { phase in
                            if case let .success(image) = phase {
                                image.resizable().aspectRatio(contentMode: .fill)
                            } else {
                                placeholder
                            }
                        }
                    } else {
                        placeholder
                    }
                }
                .background(Theme.surfaceHigh)
                .clipShape(Circle())
                .padding(.bottom, 4)
            Text(member.name)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Theme.textPrimary)
                .lineLimit(1)
            if let role = member.role {
                Text(role).font(.system(size: 11)).foregroundStyle(Theme.textSecondary).lineLimit(1)
            }
        }
        .frame(width: 100)
    }

    private var placeholder: some View {
        Image(systemName: "person.fill").font(.system(size: 30)).foregroundStyle(Theme.textTertiary)
    }
}

private struct SimilarCard: View {
    @EnvironmentObject private var model: AppModel
    let item: MetaPreview
    @State private var hovering = false

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            Theme.surface
            if let url = (item.background ?? item.poster).flatMap(URL.init(string:)) {
                AsyncImage(url: url) { phase in
                    if case let .success(image) = phase { image.resizable().aspectRatio(contentMode: .fill) }
                }
                .frame(width: 250, height: 150)
                .clipped()
            }
            LinearGradient(colors: [.clear, .black.opacity(0.85)], startPoint: .top, endPoint: .bottom)
            VStack(alignment: .leading, spacing: 1) {
                Text(item.name).font(.system(size: 15, weight: .semibold)).foregroundStyle(.white).lineLimit(2)
                if let year = item.releaseInfo { Text(year).font(.system(size: 12)).foregroundStyle(Theme.textTertiary) }
            }
            .padding(8)
        }
        .frame(width: 250, height: 150)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.white.opacity(hovering ? 0.9 : 0), lineWidth: 2))
        .scaleEffect(hovering ? 1.04 : 1)
        .animation(.easeOut(duration: 0.15), value: hovering)
        .onHover { inside in
            hovering = inside
            CardHover.update(CardMenuTarget(item: item), hovering: inside)
        }
        .contentShape(Rectangle())
        .onTapGesture { model.openDetail(item) }
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
