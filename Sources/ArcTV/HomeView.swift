import AppKit
import ArcTVCore
import SwiftUI

/// Home: the rotating banner of featured titles, Continue Watching, Picked for you (Plus), then the rows.
struct HomeView: View {
    @EnvironmentObject private var model: AppModel
    /// The colour of the banner picture now showing, which lights the area below it.
    @State private var wash: WashRGB?

    var body: some View {
        switch model.home {
        case .idle, .loading:
            HomeSkeleton()
        case .empty:
            ComingSoonView(title: "Nothing to show yet", note: "Home couldn't load its rows. Check your connection and your addons in Settings, then try again.")
        case .loaded:
            let rows = model.homeSections
            GeometryReader { geo in
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    let heroHeight = max(geo.size.height * 0.62, 500)
                    if !model.heroTitles.isEmpty {
                        HeroCarousel(items: model.heroTitles, height: heroHeight, onColor: { wash = $0 })
                    } else if !model.homeComplete {
                        // The banner is still being found: keep its space so the rows don't jump down when it arrives.
                        Theme.surface.opacity(0.5).frame(height: heroHeight)
                    } else {
                        Spacer().frame(height: 90)
                    }
                    // The first row rides up over the bottom of the banner (which fades into the page there), as on the web app.
                    VStack(alignment: .leading, spacing: 0) {
                        if !model.continueItems.isEmpty {
                            ContinueRowView(items: model.continueItems)
                                .padding(.bottom, 18)
                        }
                        let tiles = model.streamingTiles
                        if !tiles.isEmpty {
                            StreamingTilesRow(tiles: tiles)
                                .padding(.bottom, 18)
                        }
                        if let picked = model.picked {
                            PickedRowView(row: picked)
                                .padding(.bottom, 18)
                        }
                        LazyVStack(alignment: .leading, spacing: 26) {
                            ForEach(rows) { row in HomeRowView(row: row) }
                        }
                    }
                    .padding(.top, model.heroTitles.isEmpty && model.homeComplete ? 8 : -70)
                    .padding(.bottom, 40)
                }
                // the light sits centred on the banner's bottom edge, behind its fading picture, and scrolls away with the page
                .background(alignment: .top) {
                    HeroWashLayer(color: wash)
                        .frame(height: geo.size.height * 0.78)
                        .offset(y: max(geo.size.height * 0.62, 500) - geo.size.height * 0.39)
                }
            }
            .ignoresSafeArea(.container, edges: .top)
            }
        }
    }
}

/// The banner at the top of Home: ten featured titles that change by themselves every few seconds (stopped by the pause button, or while the pointer
/// is over it), with dots to jump to one.
struct HeroCarousel: View {
    @EnvironmentObject private var model: AppModel
    let items: [MetaPreview]
    let height: CGFloat
    /// Told the colour of each banner picture as it comes up (nil when it has none worth lighting with).
    var onColor: (WashRGB?) -> Void = { _ in }
    @State private var index = 0
    @State private var paused = false
    @State private var hovering = false
    @State private var forward = true
    private let timer = Timer.publish(every: 5, on: .main, in: .common).autoconnect()

    var body: some View {
        let current = items[min(index, items.count - 1)]
        ZStack(alignment: .bottomTrailing) {
            HeroSlide(item: current, height: height)
                .id(current.id)
                .transition(.asymmetric(
                    insertion: .move(edge: forward ? .trailing : .leading),
                    removal: .move(edge: forward ? .leading : .trailing)
                ))
            if items.count > 1 { controls }
        }
        .frame(height: height)
        .clipped()
        .onHover { hovering = $0 }
        .task(id: current.id) {
            guard let url = current.background.flatMap(URL.init(string:)) else { onColor(nil); return }
            onColor(await HeroWash.color(for: url))
        }
        .task(id: items.map(\.id)) {
            ImageCache.preload(items.flatMap { [$0.background, $0.logo] }.compactMap { $0.flatMap(URL.init(string:)) })
        }
        .onReceive(timer) { _ in
            guard items.count > 1, !paused, !hovering else { return }
            go(to: (index + 1) % items.count)
        }
    }

    private func go(to target: Int) {
        guard target != index else { return }
        forward = target > index || (index == items.count - 1 && target == 0)
        withAnimation(.easeInOut(duration: 0.65)) { index = target }
    }

    private var controls: some View {
        HStack(spacing: 4) {
            Button { paused.toggle() } label: {
                Image(systemName: paused ? "play.fill" : "pause.fill")
                    .font(.system(size: 12))
                    .foregroundStyle(.white)
                    .frame(width: 28, height: 24)
                    .shadow(color: .black.opacity(0.7), radius: 3)
            }
            .buttonStyle(.plain)
            .help(paused ? "Play the slide show" : "Pause the slide show")
            ForEach(items.indices, id: \.self) { dot in
                Button { go(to: dot) } label: {
                    Circle()
                        .fill(dot == index ? Color.white : Color.white.opacity(0.4))
                        .frame(width: dot == index ? 9 : 7, height: dot == index ? 9 : 7)
                        .frame(width: 18, height: 24)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.trailing, 36)
        .padding(.bottom, 62)
    }
}

/// One featured title: its wide picture, logo (or name), a line of facts, genres, a short description and the buttons.
private struct HeroSlide: View {
    @EnvironmentObject private var model: AppModel
    let item: MetaPreview
    let height: CGFloat
    @State private var trailer: String?

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                // The picture melts away at the bottom (rather than being painted over with the page colour) so the coloured light behind it shows through.
                ZStack {
                    Theme.surface
                    if let background = item.background, let url = URL(string: background) {
                        CachedImage(url: url)
                            .frame(width: geo.size.width, height: height)
                            .clipped()
                    }
                    // darkens the left so the text can be read; inside the faded part, or it would stop in a line at the banner's bottom edge
                    LinearGradient(colors: [Theme.background.opacity(0.85), .clear], startPoint: .leading, endPoint: .center)
                }
                // fully gone a little before the banner's bottom edge, in several steps so there is no visible start or end to the fade
                .mask(LinearGradient(stops: [
                    .init(color: .black, location: 0),
                    .init(color: .black, location: 0.45),
                    .init(color: .black.opacity(0.7), location: 0.62),
                    .init(color: .black.opacity(0.32), location: 0.76),
                    .init(color: .black.opacity(0.08), location: 0.88),
                    .init(color: .clear, location: 0.96)
                ], startPoint: .top, endPoint: .bottom))

                details
                    .padding(.horizontal, 44)
                    .padding(.top, 50)
            }
            .frame(width: geo.size.width, height: height)
        }
        .frame(height: height)
        .task(id: item.id) { trailer = await model.trailerID(for: item) }
    }

    private var details: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let logo = item.logo, let url = URL(string: logo) {
                CachedImage(url: url, contentMode: .fit) { titleText }
                    .frame(maxWidth: 380, maxHeight: 110, alignment: .leading)
            } else {
                titleText
            }

            HStack(spacing: 14) {
                if let year = item.releaseInfo { Text(year) }
                if let runtime = item.runtime { Text(runtime) }
                if let rating = item.imdbRating { Label(rating, systemImage: "star.fill") }
            }
            .font(.system(size: 14, weight: .medium))
            .foregroundStyle(.white)

            if let genres = item.genres, !genres.isEmpty {
                Text(genres.prefix(3).joined(separator: "  ·  "))
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.white.opacity(0.9))
            }

            if let description = item.description?.htmlDecoded {
                Text(description)
                    .font(.system(size: 14))
                    .foregroundStyle(.white)
                    .lineLimit(3)
                    .frame(maxWidth: 560, alignment: .leading)
            }

            HStack(spacing: 14) {
                Button { model.play(item) } label: { Label("Play", systemImage: "play.fill") }
                    .buttonStyle(LightButtonStyle())
                Button {
                    if let trailer, let url = URL(string: "https://www.youtube.com/watch?v=\(trailer)") { NSWorkspace.shared.open(url) }
                } label: { Label("Trailer", systemImage: "theatermasks") }
                    .buttonStyle(GlassButtonStyle())
                    .frame(height: 48)
                    .disabled(trailer == nil)
                    .help(trailer == nil ? "No trailer found for this title" : "Watch the trailer on YouTube")
                HeroIconButton(icon: model.isSaved(item.id) ? "checkmark" : "plus", label: "My List") { Task { await model.toggleSaved(item.asDetail) } }
                HeroIconButton(icon: "info", label: "Info") { model.openDetail(item) }
            }
            .padding(.top, 8)
        }
    }

    private var titleText: some View {
        Text(item.name)
            .font(.system(size: 44, weight: .heavy))
            .foregroundStyle(Theme.textPrimary)
            .lineLimit(2)
            .shadow(color: .black.opacity(0.6), radius: 8, y: 2)
    }
}

/// A round button with a small label under it (the banner's My List and Info).
private struct HeroIconButton: View {
    let icon: String
    let label: String
    let action: () -> Void

    var body: some View {
        VStack(spacing: 4) {
            Button(action: action) {
                Image(systemName: icon)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                    .frame(width: 44, height: 44)
                    .background(Circle().fill(Color.white.opacity(0.16)))
            }
            .buttonStyle(.plain)
            Text(label).font(.system(size: 11, weight: .medium)).foregroundStyle(.white.opacity(0.85))
        }
    }
}

struct HomeRowView: View {
    @EnvironmentObject private var model: AppModel
    let row: HomeSection

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(row.title)
                .font(.system(size: 20, weight: .bold))
                .foregroundStyle(Theme.textPrimary)
                .padding(.horizontal, 44)
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(alignment: .top, spacing: 16) {
                    ForEach(row.items) { item in
                        PosterCard(item: item, width: PosterSize.row)
                    }
                }
                .padding(.horizontal, 44)
                .padding(.vertical, 12)
            }
        }
    }
}

/// Picked for you (Arc TV Plus): titles chosen from what you like, finish and save, each with the reason under it.
struct PickedRowView: View {
    @EnvironmentObject private var model: AppModel
    let row: PickedRow

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(row.title)
                .font(.system(size: 20, weight: .bold))
                .foregroundStyle(Theme.textPrimary)
                .padding(.horizontal, 44)
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(alignment: .top, spacing: 16) {
                    ForEach(row.entries) { entry in
                        PosterCard(item: entry.item, width: PosterSize.row, reason: entry.reason, fromPicked: true)
                    }
                }
                .padding(.horizontal, 44)
                .padding(.vertical, 12)
            }
        }
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

/// Continue Watching: wide cards with how far through you are; clicking one picks up where you left off.
struct ContinueRowView: View {
    @EnvironmentObject private var model: AppModel
    let items: [ContinueItem]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Continue Watching")
                .font(.system(size: 20, weight: .bold))
                .foregroundStyle(Theme.textPrimary)
                .padding(.horizontal, 44)
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(alignment: .top, spacing: 16) {
                    ForEach(items) { item in
                        ContinueCard(item: item)
                    }
                }
                .padding(.horizontal, 44)
                .padding(.vertical, 12)
            }
        }
    }
}

struct ContinueCard: View {
    @EnvironmentObject private var model: AppModel
    let item: ContinueItem
    @State private var hovering = false

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Color.clear
                .frame(width: 270, height: 152)
                .overlay { artwork }
                .overlay(alignment: .topLeading) { CornerLogo(contentId: item.contentId) }
                .overlay(alignment: .bottom) {
                    ZStack(alignment: .leading) {
                        Rectangle().fill(Color.white.opacity(0.25))
                        GeometryReader { geo in
                            Rectangle().fill(Theme.brandGradient).frame(width: geo.size.width * item.progress)
                        }
                    }
                    .frame(height: 4)
                }
                .background(RoundedRectangle(cornerRadius: 10).fill(Theme.surface))
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.white.opacity(hovering ? 0.9 : 0), lineWidth: 2))
                .shadow(color: .black.opacity(hovering ? 0.55 : 0), radius: 14, y: 6)
                .scaleEffect(hovering ? 1.04 : 1)
                .animation(.easeOut(duration: 0.15), value: hovering)
            Text(item.title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Theme.textPrimary)
                .lineLimit(1)
            Text([item.episodeLabel, MPVPlayerModel.clock(item.positionSeconds) + " in"].compactMap { $0 }.joined(separator: " · "))
                .font(.system(size: 12))
                .foregroundStyle(Theme.textTertiary)
                .lineLimit(1)
        }
        .frame(width: 270)
        .onHover { inside in
            hovering = inside
            CardHover.update(CardMenuTarget(item: item.asPreview), hovering: inside)
        }
        .contentShape(Rectangle())
        .onTapGesture { model.openDetail(item.asPreview) }
    }

    @ViewBuilder
    private var artwork: some View {
        if let url = (item.backdropUrl ?? item.posterUrl).flatMap(URL.init(string:)) {
            AsyncImage(url: url) { phase in
                if case let .success(image) = phase { image.resizable().aspectRatio(contentMode: .fill) }
            }
        }
    }
}

/// The title's own logo in the top-left of a Continue Watching picture (from Metahub, as on the web app), over a soft shade so it reads on any
/// picture. Shown only once it has loaded; a title with no logo just has its picture.
private struct CornerLogo: View {
    let contentId: String
    @State private var logo: NSImage?

    var body: some View {
        ZStack(alignment: .topLeading) {
            if let logo {
                LinearGradient(colors: [Color.black.opacity(0.55), .clear], startPoint: .top, endPoint: .bottom)
                    .frame(height: 70)
                Image(nsImage: logo)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(maxWidth: 270 * 0.34, maxHeight: 152 * 0.18, alignment: .topLeading)
                    .padding(9)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .allowsHitTesting(false)
        .task(id: contentId) {
            let id = contentId.split(separator: ":").first.map(String.init) ?? contentId
            guard id.hasPrefix("tt"), let url = URL(string: "https://images.metahub.space/logo/medium/\(id)/img") else { logo = nil; return }
            logo = await ImageCache.load(url)
        }
    }
}
