import ArcTVCore
import SwiftUI

/// "Download": the files the account's debrid addons offer for this title, best quality at the smallest size first, and what is being saved.
struct DownloadPanel: View {
    @EnvironmentObject private var model: AppModel
    @ObservedObject private var manager = DownloadManager.shared
    let target: PlayTarget
    let close: () -> Void
    @State private var choices: [SourceItem] = []
    @State private var loading = true

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
        .task { await load() }
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
