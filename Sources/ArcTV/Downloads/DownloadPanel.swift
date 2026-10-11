import ArcTVCore
import SwiftUI

/// "Download": the files the account's debrid addons offer for this title, best quality at the smallest size first, and what is being saved.
struct DownloadPanel: View {
    @EnvironmentObject private var model: AppModel
    @ObservedObject private var manager = DownloadManager.shared
    /// The season and episode shown in the pickers (a show), starting on the one the Download button opened; empty for a movie.
    let seasons: [Int: [EpisodeInfo]]
    /// Called with what was being shown when a file was chosen (the title page marks that episode's Download button as used).
    let onSaved: (PlayTarget) -> Void
    let close: () -> Void
    @State private var target: PlayTarget
    @State private var choices: [SourceItem] = []
    @State private var loading = true

    init(target: PlayTarget, seasons: [Int: [EpisodeInfo]] = [:], onSaved: @escaping (PlayTarget) -> Void = { _ in }, close: @escaping () -> Void) {
        _target = State(initialValue: target)
        self.seasons = seasons
        self.onSaved = onSaved
        self.close = close
    }

    private var seasonNumbers: [Int] { seasons.keys.filter { $0 > 0 }.sorted() }
    private var episodesInSeason: [EpisodeInfo] { seasons[target.season ?? 0] ?? [] }
    private var showsPickers: Bool { target.title.type == "series" && !seasonNumbers.isEmpty }

    private func pick(_ episode: EpisodeInfo) {
        target = PlayTarget(title: target.title, season: episode.season, episode: episode.episode, episodeTitle: DownloadChoices.episodeHeading(episode))
    }

    /// Season and Episode drop-downs: any episode's files can be found without going back to the page. Another season starts at its first episode.
    private var pickers: some View {
        HStack(spacing: 12) {
            Picker("Season", selection: Binding(
                get: { target.season ?? seasonNumbers.first ?? 1 },
                set: { number in if let first = seasons[number]?.first { pick(first) } }
            )) {
                ForEach(seasonNumbers, id: \.self) { number in
                    Text(DownloadChoices.seasonLabel(season: number, episodes: seasons[number]?.count ?? 0)).tag(number)
                }
            }
            Picker("Episode", selection: Binding(
                get: { target.episode ?? episodesInSeason.first?.episode ?? 1 },
                set: { number in if let episode = episodesInSeason.first(where: { $0.episode == number }) { pick(episode) } }
            )) {
                ForEach(episodesInSeason) { episode in
                    Text(DownloadChoices.episodeLabel(episode)).tag(episode.episode ?? 0)
                }
            }
        }
        .pickerStyle(.menu)
    }

    var body: some View {
        ZStack {
            Color.black.opacity(0.7).ignoresSafeArea().onTapGesture(perform: close)
            VStack(spacing: 0) {
                banner
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        if showsPickers { pickers }
                        sources
                        if !manager.jobs.isEmpty {
                            Divider().overlay(Theme.divider)
                            HStack {
                                Text("Downloads").font(.system(size: 15, weight: .bold)).foregroundStyle(Theme.textPrimary)
                                Spacer()
                                Button("Clear finished") { manager.clearFinished() }
                                    .buttonStyle(.plain).font(.system(size: 12)).foregroundStyle(Theme.textTertiary).underline()
                            }
                            ForEach(manager.jobs.prefix(5)) { job in jobRow(job) }
                        }
                    }
                    .padding(24)
                }
            }
            .frame(width: 720)
            .frame(maxHeight: 700)
            .background(Theme.elevated)
            .clipShape(RoundedRectangle(cornerRadius: 22))
            .overlay(RoundedRectangle(cornerRadius: 22).stroke(Theme.divider, lineWidth: 1))
            .shadow(color: .black.opacity(0.6), radius: 30, y: 12)
        }
        .task(id: target.streamID) { await load() }
    }

    /// Like the web's: the title's backdrop picture across the top, "Downloads" with Back and Close over it, and the title's logo (or its name)
    /// over the bottom with what it is (year, show or movie, and the episode).
    private var banner: some View {
        let detail = target.title
        return ZStack(alignment: .bottomLeading) {
            Theme.surfaceHigh
            if let art = detail.background ?? detail.poster, let url = URL(string: art) {
                CachedImage(url: url, contentMode: .fill).frame(width: 720, height: 230).clipped()
            }
            LinearGradient(
                colors: [Color.black.opacity(0.6), Color.clear, Theme.elevated.opacity(0.6), Theme.elevated],
                startPoint: .top, endPoint: .bottom
            )
            VStack(alignment: .leading, spacing: 6) {
                if let logo = detail.logo, let url = URL(string: logo) {
                    CachedImage(url: url, contentMode: .fit) {
                        Text(detail.name).font(.system(size: 32, weight: .heavy)).foregroundStyle(Theme.textPrimary).lineLimit(2)
                    }
                    .frame(maxWidth: 320, maxHeight: 84, alignment: .leading)
                } else {
                    Text(detail.name).font(.system(size: 32, weight: .heavy)).foregroundStyle(Theme.textPrimary).lineLimit(2)
                }
                Text(subtitle).font(.system(size: 14)).foregroundStyle(Theme.textSecondary).shadow(color: .black.opacity(0.8), radius: 4)
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 14)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(width: 720, height: 230)
        .overlay(alignment: .top) {
            HStack(spacing: 12) {
                roundButton("arrow.left", label: "Back", action: close)
                Text("Downloads").font(.system(size: 24, weight: .bold)).foregroundStyle(Theme.textPrimary).shadow(color: .black.opacity(0.8), radius: 6)
                Spacer()
                roundButton("xmark", label: "Close", action: close)
            }
            .padding(16)
        }
        .clipped()
    }

    private var subtitle: String {
        let kind = target.title.type == "series" ? "Show" : "Movie"
        let episode = target.title.type == "series" ? target.season.flatMap { s in target.episode.map { "S\(s)E\($0)" } } : nil
        return [target.title.year.map(String.init), kind, episode].compactMap { $0 }.joined(separator: " • ")
    }

    private func roundButton(_ icon: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon).font(.system(size: 14, weight: .bold)).foregroundStyle(Theme.textPrimary)
                .frame(width: 36, height: 36)
                .background(Circle().fill(Color.black.opacity(0.5)))
                .overlay(Circle().stroke(Color.white.opacity(0.18), lineWidth: 1))
        }
        .buttonStyle(.plain)
        .help(label)
    }

    @ViewBuilder
    private var sources: some View {
        if loading {
            HStack(spacing: 10) { ProgressView().controlSize(.small); Text("Asking your addons…").foregroundStyle(Theme.textSecondary) }
        } else if choices.isEmpty {
            Text("No files to download for this title. Downloads need a debrid addon that gives direct links; torrents can't be saved this way.")
                .font(.system(size: 14)).foregroundStyle(Theme.textSecondary)
        } else {
            HStack {
                Text(choices.count == 1 ? "1 source" : "\(choices.count) sources").font(.system(size: 14)).foregroundStyle(Theme.textSecondary)
                Spacer()
                Text("Best quality first, then smallest").font(.system(size: 13)).foregroundStyle(Theme.textTertiary)
            }
            VStack(spacing: 10) {
                ForEach(choices) { item in
                    Button { save(item) } label: { row(item) }.buttonStyle(.plain)
                }
            }
            Text("Choose a source to download the file.").font(.system(size: 12)).foregroundStyle(Theme.textTertiary)
        }
    }

    /// One file: a quality badge, what kind of release it is (the headline), its file name small underneath, chips for the size, codec, HDR and
    /// whether a debrid service has it cached, and a round download button.
    private func row(_ item: SourceItem) -> some View {
        let debrid = DownloadLabels.debrid(item)
        return HStack(spacing: 14) {
            Text(item.quality.label)
                .font(.system(size: 18, weight: .heavy)).foregroundStyle(Theme.accent)
                .frame(width: 70).padding(.vertical, 12)
                .background(RoundedRectangle(cornerRadius: 10).fill(Theme.background))
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(Theme.divider, lineWidth: 1))
            VStack(alignment: .leading, spacing: 3) {
                Text(DownloadLabels.kind(item)).font(.system(size: 16, weight: .bold)).foregroundStyle(Theme.textPrimary).lineLimit(1)
                Text(item.headline).font(.system(size: 12)).foregroundStyle(Theme.textTertiary).lineLimit(1).truncationMode(.middle)
                HStack(spacing: 8) {
                    if let size = item.sizeText { chip(size, color: Theme.textPrimary, bold: true) }
                    if let codec = DownloadLabels.codec(item) { chip(codec, color: Theme.textSecondary) }
                    if let hdr = DownloadLabels.hdr(item) { chip(hdr, color: Theme.accent, outlined: true) }
                    if DownloadLabels.isUnusuallySmall(item) { chip("Unusually small", color: Color(hex: 0xFFB020), outlined: true) }
                    if let debrid { chip(debrid.label, color: debrid.cached ? Theme.watched : Color(hex: 0xFFB020), icon: debrid.cached ? "checkmark.circle.fill" : "hourglass") }
                }
                .padding(.top, 2)
            }
            Spacer(minLength: 8)
            Image(systemName: "arrow.down.to.line")
                .font(.system(size: 16, weight: .semibold)).foregroundStyle(Theme.accent)
                .frame(width: 44, height: 44)
                .background(RoundedRectangle(cornerRadius: 12).fill(Theme.accent.opacity(0.08)))
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.accent.opacity(0.35), lineWidth: 1))
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(RoundedRectangle(cornerRadius: 14).fill(Theme.surface))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Theme.divider, lineWidth: 1))
        .contentShape(Rectangle())
    }

    private func chip(_ text: String, color: Color, bold: Bool = false, outlined: Bool = false, icon: String? = nil) -> some View {
        HStack(spacing: 4) {
            if let icon { Image(systemName: icon).font(.system(size: 10)) }
            Text(text).font(.system(size: 11, weight: bold ? .bold : .medium)).lineLimit(1)
        }
        .foregroundStyle(color)
        .padding(.horizontal, 7)
        .padding(.vertical, 3)
        .background(RoundedRectangle(cornerRadius: 6).fill(outlined ? Color.clear : Color.white.opacity(0.1)))
        .overlay(RoundedRectangle(cornerRadius: 6).stroke(outlined ? color.opacity(0.55) : Color.clear, lineWidth: 1))
    }

    private func jobRow(_ job: DownloadManager.Job) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(job.name).font(.system(size: 12, weight: .medium)).foregroundStyle(Theme.textPrimary).lineLimit(1)
                Spacer()
                switch job.state {
                case .running:
                    Button("Cancel") { manager.cancel(job) }.buttonStyle(.plain).font(.system(size: 12)).foregroundStyle(Theme.textTertiary)
                case .done:
                    Button("Show in Finder") { manager.reveal(job) }.buttonStyle(.plain).font(.system(size: 12)).foregroundStyle(Theme.accent)
                case .failed:
                    EmptyView()
                }
            }
            switch job.state {
            case .running:
                if let fraction = job.fraction { ProgressView(value: fraction) } else { ProgressView().controlSize(.small) }
            case .done:
                Text("Saved to your Downloads folder").font(.system(size: 11)).foregroundStyle(Theme.watched)
            case let .failed(why):
                Text(why).font(.system(size: 11)).foregroundStyle(Color(hex: 0xFFB020))
            }
        }
    }

    private func load() async {
        loading = true
        choices = []
        if model.addons.isEmpty { await model.loadAddons() }
        let result = await SourceFinder.find(addons: model.addons, type: target.title.type, id: target.streamID)
        choices = DownloadChoices.sorted(result.items)
        loading = false
    }

    private func save(_ item: SourceItem) {
        guard let url = item.playURL else { return }
        manager.start(url: url, fileName: DownloadChoices.fileName(release: item.headline, url: url))
        onSaved(target)
    }
}
