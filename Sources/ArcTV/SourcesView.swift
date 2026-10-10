import ArcTVCore
import SwiftUI

/// "Select a source": every stream the account's addons offer for this title, the ones that can play here first, best quality first.
struct SourcesView: View {
    @EnvironmentObject private var model: AppModel
    let target: PlayTarget
    @State private var result = SourceResult()
    @State private var loading = true

    var body: some View {
        ZStack(alignment: .topLeading) {
            Theme.background.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Select a source")
                            .font(.system(size: 30, weight: .heavy))
                            .foregroundStyle(Theme.textPrimary)
                        Text(target.heading)
                            .font(.system(size: 15))
                            .foregroundStyle(Theme.textSecondary)
                    }
                    .padding(.top, 70)

                    if loading {
                        HStack(spacing: 12) {
                            ProgressView()
                            Text("Asking your addons…").foregroundStyle(Theme.textSecondary)
                        }
                        .padding(.top, 20)
                    } else {
                        if result.items.isEmpty {
                            noSources
                        } else {
                            VStack(spacing: 8) {
                                ForEach(result.items) { item in
                                    SourceRow(item: item) { choose(item) }
                                }
                            }
                        }
                        if !result.items.isEmpty { statusLines }
                    }
                }
                .frame(maxWidth: 900, alignment: .leading)
                .padding(.horizontal, 44)
                .padding(.bottom, 48)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            BackButton { model.goBack() }
                .padding(.leading, 28)
                .padding(.top, 22)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task { await load() }
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
        // Watched before: carry on with the same source instead of asking (unless "Choose source" was used).
        if !target.chooseSource, let user = model.scope,
           let last = LastSourceStore(userID: user).get(titleID: target.title.id, season: target.season, episode: target.episode),
           let match = last.match(in: result.items) {
            choose(match)
        }
        loading = false
    }

    private func retry() async {
        loading = true
        result = await SourceFinder.find(addons: model.addons, type: target.title.type, id: target.streamID)
        loading = false
    }

    private func choose(_ item: SourceItem) {
        guard let url = item.playURL else { return }
        if let user = model.scope {
            LastSourceStore(userID: user).set(LastSource(item), titleID: target.title.id, season: target.season, episode: target.episode)
        }
        model.play(PlayingItem(url: url, heading: target.heading, sourceName: item.addonName, target: target))
    }
}

private struct SourceRow: View {
    let item: SourceItem
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Text(item.quality.label)
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(item.isPlayable ? Color(hex: 0x04161A) : Theme.textTertiary)
                    .frame(width: 54)
                    .padding(.vertical, 6)
                    .background(Capsule().fill(item.isPlayable ? AnyShapeStyle(Theme.brandGradient) : AnyShapeStyle(Color.white.opacity(0.08))))
                VStack(alignment: .leading, spacing: 3) {
                    Text(item.headline)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(item.isPlayable ? Theme.textPrimary : Theme.textTertiary)
                        .lineLimit(2)
                    HStack(spacing: 8) {
                        Text(item.addonName)
                        if let size = item.sizeText { Text(size) }
                        if !item.isPlayable { Text("Torrent: not supported in this app yet") }
                    }
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.textTertiary)
                }
                Spacer(minLength: 0)
                if item.isPlayable {
                    Image(systemName: "play.fill").foregroundStyle(hovering ? Theme.accent : Theme.textTertiary)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(RoundedRectangle(cornerRadius: 12).fill(hovering && item.isPlayable ? Color.white.opacity(0.09) : Theme.elevated))
        }
        .buttonStyle(.plain)
        .disabled(!item.isPlayable)
        .onHover { hovering = $0 }
    }
}
