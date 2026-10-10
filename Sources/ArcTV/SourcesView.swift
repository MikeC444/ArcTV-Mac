import ArcTVCore
import SwiftUI

/// "Select a source": every stream the account's addons offer for this title, the ones that can play here first, best quality first.
struct SourcesView: View {
    @EnvironmentObject private var model: AppModel
    let target: PlayTarget
    @State private var items: [SourceItem] = []
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
                    } else if items.isEmpty {
                        Text(emptyMessage)
                            .foregroundStyle(Theme.textSecondary)
                            .frame(maxWidth: 560, alignment: .leading)
                            .padding(.top, 12)
                    } else {
                        VStack(spacing: 8) {
                            ForEach(items) { item in
                                SourceRow(item: item) { choose(item) }
                            }
                        }
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

    private var emptyMessage: String {
        let streamAddons = model.addons.filter { $0.manifestJson?.providesStreams(type: target.title.type, id: target.streamID) ?? false }
        if model.addons.isEmpty || streamAddons.isEmpty {
            return "Your account has no addon that gives streams. Add one (such as Torrentio) in Settings > Addons on another device, then come back."
        }
        return "Your addons had no streams for this title."
    }

    private func load() async {
        if model.addons.isEmpty { await model.loadAddons() }
        items = await SourceFinder.find(addons: model.addons, type: target.title.type, id: target.streamID)
        loading = false
    }

    private func choose(_ item: SourceItem) {
        guard let url = item.playURL else { return }
        model.play(PlayingItem(url: url, heading: target.heading, sourceName: item.addonName))
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
