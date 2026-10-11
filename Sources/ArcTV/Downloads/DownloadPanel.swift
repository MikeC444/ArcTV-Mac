import ArcTVCore
import SwiftUI

/// "Download": the files the account's debrid addons offer for this title, best quality at the smallest size first, and what is being saved.
struct DownloadPanel: View {
    @EnvironmentObject private var model: AppModel
    @ObservedObject private var manager = DownloadManager.shared
    /// The season and episode shown in the pickers (a show), starting on the one the Download button opened; empty for a movie.
    let seasons: [Int: [EpisodeInfo]]
    let close: () -> Void
    @State private var target: PlayTarget
    @State private var choices: [SourceItem] = []
    @State private var loading = true

    init(target: PlayTarget, seasons: [Int: [EpisodeInfo]] = [:], close: @escaping () -> Void) {
        _target = State(initialValue: target)
        self.seasons = seasons
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
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Download").font(.system(size: 24, weight: .heavy)).foregroundStyle(Theme.textPrimary)
                        Text(target.heading).font(.system(size: 14)).foregroundStyle(Theme.textSecondary).lineLimit(1)
                    }
                    Spacer()
                    Button(action: close) {
                        Image(systemName: "xmark").font(.system(size: 12, weight: .bold)).foregroundStyle(Theme.textSecondary)
                            .frame(width: 28, height: 28).background(Circle().fill(Theme.surfaceHigh))
                    }
                    .buttonStyle(.plain)
                }
                if showsPickers { pickers }
                if loading {
                    HStack(spacing: 10) { ProgressView().controlSize(.small); Text("Asking your addons…").foregroundStyle(Theme.textSecondary) }
                } else if choices.isEmpty {
                    Text("No files to download for this title. Downloads need a debrid addon that gives direct links; torrents can't be saved this way.")
                        .font(.system(size: 14)).foregroundStyle(Theme.textSecondary)
                } else {
                    Text("Best quality at the smallest size first.").font(.system(size: 13)).foregroundStyle(Theme.textTertiary)
                    ScrollView {
                        VStack(spacing: 8) {
                            ForEach(choices) { item in
                                Button { save(item) } label: { row(item) }.buttonStyle(.plain)
                            }
                        }
                    }
                    .frame(maxHeight: 280)
                }
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
            .frame(width: 620)
            .background(RoundedRectangle(cornerRadius: 20).fill(Theme.elevated))
            .overlay(RoundedRectangle(cornerRadius: 20).stroke(Theme.divider, lineWidth: 1))
            .shadow(color: .black.opacity(0.6), radius: 30, y: 12)
        }
        .task(id: target.streamID) { await load() }
    }

    private func row(_ item: SourceItem) -> some View {
        HStack(spacing: 12) {
            Text(item.quality.label).font(.system(size: 12, weight: .bold)).foregroundStyle(Color(hex: 0x04161A))
                .frame(width: 52).padding(.vertical, 5).background(Capsule().fill(Theme.brandGradient))
            Text(item.headline).font(.system(size: 13, weight: .semibold)).foregroundStyle(Theme.textPrimary).lineLimit(1)
            Spacer(minLength: 8)
            if let size = item.sizeText { Text(size).font(.system(size: 12)).foregroundStyle(Theme.textSecondary) }
            Image(systemName: "arrow.down.circle.fill").foregroundStyle(Theme.accent)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(RoundedRectangle(cornerRadius: 10).fill(Theme.surface))
        .contentShape(Rectangle())
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
    }
}
