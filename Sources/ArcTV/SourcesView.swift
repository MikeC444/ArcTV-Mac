import ArcTVCore
import SwiftUI

/// "Select a source": every stream the account's addons offer for this title, the ones that can play here first, best quality first.
struct SourcesView: View {
    @EnvironmentObject private var model: AppModel
    let target: PlayTarget
    @State private var result = SourceResult()
    @State private var loading = true
    /// A source was picked without asking and is starting (a torrent takes a while to get going): the list stays covered until it plays or fails.
    @State private var autoStarted = false
    @State private var filter: SourceFilter = .all
    @State private var sort: SourceSort = .quality
    @ObservedObject private var torrents = TorrentEngine.shared

    private var arranged: [SourceItem] { SourceListing.arrange(result.items, filter: filter, sort: sort) }
    private var recommendedIDs: [String] { SourceListing.recommendedIDs(in: result.items) }

    /// Is a source going to be picked without asking (the next episode of a binge, a source used before, or Smart source picking)? Then the list
    /// is not shown while the addons answer: the player's own loading picture is, so there is no flash of "Select a source" on the way in.
    private var willAutoPick: Bool { model.picksSourceWithoutAsking(target) }

    var body: some View {
        ZStack(alignment: .topLeading) {
            Theme.background.ignoresSafeArea()
            Backdrop(detail: target.title)
            GeometryReader { geo in
            HStack(alignment: .top, spacing: 0) {
                infoPanel
                    .frame(width: geo.size.width * 0.37)
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Select a source")
                                .font(.system(size: 30, weight: .heavy))
                                .foregroundStyle(Theme.textPrimary)
                            Text("Choose the best quality and server for your stream.")
                                .font(.system(size: 15))
                                .foregroundStyle(Theme.textSecondary)
                        }
                        .padding(.top, 36)

                        if let failure = torrents.failure {
                            Text(failure)
                                .font(.system(size: 14))
                                .foregroundStyle(Color(hex: 0xFFB020))
                                .padding(12)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(RoundedRectangle(cornerRadius: 10).fill(Color(hex: 0xFFB020).opacity(0.12)))
                        }

                        if loading {
                            SourcesSkeleton()
                        } else {
                            if result.items.isEmpty {
                                noSources
                            } else {
                                filterBar
                                // worked out once for the whole list, not for each row
                                let rows = arranged
                                let recommended = recommendedIDs
                                VStack(spacing: 10) {
                                    ForEach(rows) { item in
                                        SourceRow(item: item, recommended: recommended.contains(item.id), kindLabel: recommended.count > 1) { choose(item) }
                                    }
                                }
                                if rows.count <= 1 && filter != .all {
                                    Button("No other sources in this quality. Show all sources") { filter = .all }
                                        .buttonStyle(.plain)
                                        .font(.system(size: 13, weight: .semibold))
                                        .foregroundStyle(Theme.accent)
                                }
                                statusLines
                            }
                        }
                    }
                    .padding(.trailing, 22)
                    .padding(.bottom, 48)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            }
            if (loading && willAutoPick) || (autoStarted && torrents.failure == nil) {
                ZStack {
                    PlayerLoadingCover(title: target.title)
                    ProgressView().controlSize(.large)
                }
                .transition(.opacity)
            }
            if let progress = torrents.progress {
                TorrentLoadingView(detail: target.title, progress: progress) { model.cancelTorrent() }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task { await load() }
        .onChange(of: torrents.progress == nil) { gone in
            // the torrent was cancelled (not played): show the list again
            if gone, model.playing == nil, torrents.failure == nil { autoStarted = false }
        }
    }

    /// Quality pills and the sort choice, as on the web app.
    private var filterBar: some View {
        HStack(spacing: 8) {
            ForEach(SourceFilter.allCases) { option in
                ChoicePill(label: option.rawValue, selected: filter == option) { filter = option }
            }
            Spacer(minLength: 12)
            Button { sort = sort.next } label: {
                HStack(spacing: 6) {
                    Text("Sort by: \(sort.rawValue)")
                    Image(systemName: "chevron.down").font(.system(size: 11, weight: .bold))
                }
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(Theme.textPrimary)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(Capsule().fill(Theme.surfaceHigh))
            }
            .buttonStyle(.plain)
        }
    }

    /// The title on the left: poster, year, logo, genres and length, description.
    private var infoPanel: some View {
        let detail = target.title
        let runtime = Format.runtimeMinutes(detail.runtime).map { Format.runtime(minutes: $0) } ?? ""
        let facts = [(detail.genres ?? []).prefix(3).joined(separator: "  •  "), runtime].filter { !$0.isEmpty }.joined(separator: "   ")
        return VStack(alignment: .leading, spacing: 10) {
            BackButton { model.goBack() }
            if let poster = detail.poster, let url = URL(string: poster) {
                CachedImage(url: url) { Color.white.opacity(0.06) }
                    .frame(width: 132, height: 198)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    .padding(.top, 8)
            }
            if let year = detail.year { Text(String(year)).font(.system(size: 15)).foregroundStyle(Theme.textSecondary) }
            if let logo = detail.logo, let url = URL(string: logo) {
                CachedImage(url: url, contentMode: .fit) { titleText(detail) }
                    .frame(maxWidth: 240, maxHeight: 80, alignment: .leading)
            } else {
                titleText(detail)
            }
            if !facts.isEmpty { Text(facts).font(.system(size: 14)).foregroundStyle(Theme.textSecondary) }
            if let about = detail.description {
                Text(about).font(.system(size: 14)).foregroundStyle(Theme.textSecondary).lineLimit(5)
            }
            Spacer(minLength: 12)
            VStack(alignment: .leading, spacing: 4) {
                Label("What are sources?", systemImage: "info.circle").font(.system(size: 13, weight: .semibold)).foregroundStyle(Theme.textPrimary)
                Text("Sources are different streams or files available online. Choose the one that works best for you.")
                    .font(.system(size: 12)).foregroundStyle(Theme.textSecondary)
            }
            .padding(12)
            .background(RoundedRectangle(cornerRadius: 12).fill(Color.black.opacity(0.5)))
            .padding(.bottom, 24)
        }
        .padding(.leading, 28)
        .padding(.trailing, 16)
        .padding(.top, 22)
        .frame(maxHeight: .infinity, alignment: .topLeading)
    }

    private func titleText(_ detail: MetaDetail) -> some View {
        Text(detail.name).font(.system(size: 24, weight: .heavy)).foregroundStyle(Theme.textPrimary).lineLimit(2)
    }

    /// Nothing came back: why, what to do next, and the beginner's guide for someone who has not set up sources yet.
    private var noSources: some View {
        VStack(spacing: 10) {
            Image(systemName: "magnifyingglass").font(.system(size: 36)).foregroundStyle(Theme.textTertiary)
            Text("No sources found").font(.system(size: 22, weight: .bold)).foregroundStyle(Theme.textPrimary)
            Text(emptyMessage).foregroundStyle(Theme.textSecondary).multilineTextAlignment(.center).frame(maxWidth: 560)
            statusLines
            HStack(spacing: 10) {
                if !result.failures.isEmpty {
                    Button { Task { await retry() } } label: { Label("Try Again", systemImage: "arrow.clockwise") }.buttonStyle(GlassButtonStyle())
                }
                Button { model.openSettings(.addons) } label: { Label("Manage Addons", systemImage: "puzzlepiece.extension") }.buttonStyle(GlassButtonStyle())
            }
            .padding(.top, 8)
            Text("New to this?").font(.system(size: 16, weight: .semibold)).foregroundStyle(Theme.textPrimary).padding(.top, 20)
            Button { model.guideOpen = true } label: { Label("Step-by-step guide to setting up your sources", systemImage: "book") }
                .buttonStyle(BrandButtonStyle())
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 30)
    }

    private var emptyMessage: String {
        if model.addons.isEmpty {
            return "Your account has no addons yet. Add one (such as Torrentio) in Settings > Addons on another device, then come back."
        }
        if result.failures.count + result.items.count == 0 && !result.skipped.isEmpty {
            return "None of your addons give streams for this title. Add one that does (such as Torrentio) in Settings > Addons on another device."
        }
        if !result.failures.isEmpty && result.failures.count >= model.addons.count - result.skipped.count {
            return "No addon answered. The reasons are below."
        }
        return "Your addons had no streams for this title. A very new or very obscure title may not have any yet; try another."
    }

    /// Which addons did not answer and which do not give streams, so a missing source is never a mystery.
    private var statusLines: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(result.skipped, id: \.self) { name in
                Text("\(name): doesn't provide streams")
                    .foregroundStyle(Theme.textTertiary)
            }
            ForEach(result.failures) { failure in
                Text("\(failure.addonName) \(failure.reason)")
                    .foregroundStyle(Color(hex: 0xFFB020))
            }
        }
        .font(.system(size: 13))
        .padding(.top, 14)
    }

    private func load() async {
        if model.addons.isEmpty { await model.loadAddons() }
        result = await SourceFinder.find(addons: model.addons, type: target.title.type, id: target.streamID)
        // The next episode of a binge: the best source that plays at once, without asking; the list is shown only when there is none.
        // (a source with a web link first; with none, the torrent with the most seeders, so a person who watches torrents is not sent to the list)
        if target.autoPick, let best = result.items.first(where: \.isPlayable) ?? SourceListing.bestTorrent(in: result.items) {
            autoStarted = true
            choose(best)
        } else if !target.chooseSource, let user = model.scope,
           let last = LastSourceStore(userID: user).get(titleID: target.title.id, season: target.season, episode: target.episode),
           let match = last.match(in: result.items) {
            autoStarted = true
            choose(match)
        } else if !target.chooseSource, model.plus.active, model.smartPicking,
                  let best = result.items.first(where: \.isPlayable) ?? SourceListing.bestTorrent(in: result.items) {
            // Smart source picking (Plus): the best source that plays here, without asking: one with a web link first, else the best torrent the
            // app can stream.
            autoStarted = true
            choose(best)
        }
        loading = false
    }

    private func retry() async {
        loading = true
        result = await SourceFinder.find(addons: model.addons, type: target.title.type, id: target.streamID)
        loading = false
    }

    private func choose(_ item: SourceItem) {
        guard item.canStream else { return }
        torrents.failure = nil
        if let user = model.scope {
            LastSourceStore(userID: user).set(LastSource(item), titleID: target.title.id, season: target.season, episode: target.episode)
        }
        if let url = item.playURL {
            model.play(PlayingItem(url: url, heading: target.heading, sourceName: item.addonName, target: target, filename: item.stream.behaviorHints?.filename))
        } else {
            model.startTorrent(item, target: target)
        }
    }
}

/// The title's artwork behind the page, darkened so the text on it reads.
private struct Backdrop: View {
    let detail: MetaDetail

    var body: some View {
        ZStack {
            if let url = (detail.background ?? detail.poster).flatMap(URL.init(string:)) {
                GeometryReader { geo in
                    CachedImage(url: url) { Color.clear }
                        .frame(width: geo.size.width, height: geo.size.height)
                        .clipped()
                }
            }
            LinearGradient(colors: [Theme.background.opacity(0.72), Theme.background.opacity(0.32), Theme.background.opacity(0.42)],
                           startPoint: .leading, endPoint: .trailing)
        }
        .ignoresSafeArea()
    }
}

/// What shows while a torrent gets ready: the title's artwork, its logo, and how the torrent is getting on, centred, where the player will appear.
struct TorrentLoadingView: View {
    let detail: MetaDetail
    let progress: TorrentProgress
    let cancel: () -> Void

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            if let url = (detail.background ?? detail.poster).flatMap(URL.init(string:)) {
                GeometryReader { geo in
                    CachedImage(url: url) { Color.clear }
                        .frame(width: geo.size.width, height: geo.size.height)
                        .clipped()
                }
                .ignoresSafeArea()
            }
            Color.black.opacity(0.62).ignoresSafeArea()
            VStack(spacing: 18) {
                if let logo = detail.logo, let url = URL(string: logo) {
                    CachedImage(url: url, contentMode: .fit) { name }
                        .frame(maxWidth: 460, maxHeight: 150)
                        .shadow(color: .black.opacity(0.6), radius: 8, y: 2)
                } else {
                    name
                }
                ProgressView().controlSize(.large).padding(.top, 10)
                Text(progress.message).font(.system(size: 20, weight: .bold)).foregroundStyle(Theme.textPrimary)
                if let extra = progress.detail { Text(extra).font(.system(size: 14)).foregroundStyle(Theme.textSecondary) }
                Text("Torrents take a little longer to start than other sources.").font(.system(size: 12)).foregroundStyle(Theme.textTertiary)
                Button(action: cancel) { Label("Cancel", systemImage: "xmark") }
                    .buttonStyle(GlassButtonStyle())
                    .padding(.top, 6)
            }
            .padding(40)
        }
    }

    private var name: some View {
        Text(detail.name).font(.system(size: 40, weight: .heavy)).foregroundStyle(Theme.textPrimary).multilineTextAlignment(.center)
    }
}

private struct SourceRow: View {
    let item: SourceItem
    let recommended: Bool
    /// Two sources are recommended (a direct link and a torrent): the badge says which is which.
    var kindLabel = false
    let action: () -> Void
    @State private var hovering = false

    private var tierColor: Color {
        switch item.quality {
        case .p2160: return Theme.accent
        case .p1080: return Theme.blue
        case .p720: return Color(hex: 0x1DB8A6)
        default: return Theme.textTertiary
        }
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 16) {
                VStack(spacing: 2) {
                    Text(item.quality.label).font(.system(size: 15, weight: .bold))
                    if let tag = item.sourceTag { Text(tag).font(.system(size: 10, weight: .semibold)) }
                }
                .foregroundStyle(tierColor)
                .frame(width: 70, height: 46)
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(tierColor, lineWidth: 1.5))
                VStack(alignment: .leading, spacing: 4) {
                    Text(item.headline)
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(item.canStream ? Theme.textPrimary : Theme.textTertiary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                    if let codec = item.codecText {
                        Text(codec).font(.system(size: 12)).foregroundStyle(Theme.textSecondary)
                    }
                    HStack(spacing: 12) {
                        if let seeders = item.seeders { Label("\(seeders) seeders", systemImage: "person.fill") }
                        if let audio = item.audioTag { Label(audio, systemImage: "speaker.wave.2.fill") }
                        if item.isTorrent { Label("Torrent", systemImage: "arrow.down.circle") }
                    }
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.textTertiary)
                }
                Spacer(minLength: 8)
                VStack(alignment: .trailing, spacing: 3) {
                    if let size = item.sizeText { Text(size).font(.system(size: 13, weight: .medium)).foregroundStyle(Theme.textSecondary) }
                    Label(item.addonName, systemImage: "wifi").font(.system(size: 11)).foregroundStyle(Theme.textTertiary)
                }
                if item.canStream {
                    Image(systemName: "play.fill")
                        .font(.system(size: 12))
                        .foregroundStyle(Color(hex: 0x04161A))
                        .frame(width: 30, height: 30)
                        .background(Circle().fill(hovering ? AnyShapeStyle(Theme.brandGradient) : AnyShapeStyle(Theme.accent.opacity(0.85))))
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(RoundedRectangle(cornerRadius: 14).fill(hovering && item.canStream ? Theme.surface : Theme.surfaceHigh.opacity(0.85)))
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(recommended ? Theme.accent : Color.clear, lineWidth: 1.5))
            .overlay(alignment: .topTrailing) {
                if recommended {
                    Label(kindLabel ? (item.isTorrent ? "Recommended \u{00B7} Torrent" : "Recommended \u{00B7} Debrid") : "Recommended", systemImage: "star.fill")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(Color(hex: 0x04161A))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 3)
                        .background(Capsule().fill(Theme.accent))
                        .offset(x: -14, y: -10)
                }
            }
            .contentShape(RoundedRectangle(cornerRadius: 14))
        }
        .buttonStyle(.plain)
        .disabled(!item.canStream)
        .onHover { hovering = $0 }
    }
}
