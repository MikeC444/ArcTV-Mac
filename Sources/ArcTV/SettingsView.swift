import ArcTVCore
import SwiftUI

/// The places in Settings, grouped and ordered like the web app's.
enum SettingsTab: String, CaseIterable, Identifiable {
    case account = "Account"
    case plus = "Arc TV Plus"
    case plusSettings = "Plus settings"
    case recommendations = "Recommendations"
    case stats = "Your stats"
    case addons = "Addons"
    case homeRows = "Home Rows"
    case blockedGenres = "Blocked Genres"
    case player = "Player"
    case subtitles = "Subtitles"
    case audio = "Audio"
    case sounds = "Sounds"
    case updates = "Updates"

    var id: String { rawValue }

    var subtitle: String {
        switch self {
        case .account: return "Manage your Arc TV account"
        case .plus: return "Extra features for supporters"
        case .plusSettings: return "Switches for your Plus features"
        case .recommendations: return "What shapes your Picked for you row"
        case .stats: return "How much you watch, at a glance"
        case .addons: return "Manage installed content providers"
        case .homeRows: return "Choose which rows show up on Home"
        case .blockedGenres: return "Hide genres you don't want to see"
        case .player: return "Choose how video plays"
        case .subtitles: return "Look and language"
        case .audio: return "Preferred audio language"
        case .sounds: return "Interface sounds"
        case .updates: return "Version and updates"
        }
    }

    var icon: String {
        switch self {
        case .account: return "person.crop.circle"
        case .plus: return "rosette"
        case .plusSettings: return "slider.horizontal.3"
        case .recommendations: return "star.fill"
        case .stats: return "chart.bar.fill"
        case .addons: return "puzzlepiece.extension"
        case .homeRows: return "square.grid.2x2"
        case .blockedGenres: return "nosign"
        case .player: return "play.rectangle"
        case .subtitles: return "captions.bubble"
        case .audio: return "speaker.wave.2"
        case .sounds: return "bell"
        case .updates: return "arrow.down.circle"
        }
    }

    static let groups: [(String, [SettingsTab])] = [
        ("You", [.account, .plus, .plusSettings, .recommendations, .stats]),
        ("Content", [.addons, .homeRows, .blockedGenres]),
        ("Playback & sound", [.player, .subtitles, .audio, .sounds]),
        ("App", [.updates])
    ]
}

/// Settings laid out like the web app's: grouped places down the left, the chosen one on the right. Account and Updates work; the rest say
/// they are coming (they are built in later stages).
struct SettingsView: View {
    @EnvironmentObject private var model: AppModel
    @State private var tab: SettingsTab = .account

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            sidebar
            pane
        }
        .padding(.top, 84)
    }

    private var sidebar: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 4) {
                ForEach(SettingsTab.groups, id: \.0) { group in
                    Text(group.0.uppercased())
                        .font(.system(size: 11, weight: .bold))
                        .tracking(1.2)
                        .foregroundStyle(Theme.textTertiary)
                        .padding(.leading, 12)
                        .padding(.top, group.0 == "You" ? 0 : 14)
                        .padding(.bottom, 2)
                    ForEach(group.1) { item in
                        SidebarRow(tab: item, selected: tab == item) { tab = item }
                    }
                }
            }
            .padding(12)
        }
        .frame(width: 270)
        .background(RoundedRectangle(cornerRadius: 18).fill(Theme.elevated))
        .overlay(RoundedRectangle(cornerRadius: 18).stroke(Theme.divider, lineWidth: 1))
        .padding(.leading, 44)
        .padding(.bottom, 28)
    }

    @ViewBuilder
    private var pane: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text(tab.rawValue)
                    .font(.system(size: 28, weight: .heavy))
                    .foregroundStyle(Theme.textPrimary)
                switch tab {
                case .account: account
                case .player: player
                case .updates: updates
                default:
                    Text("\(tab.rawValue) is coming in a later update.")
                        .foregroundStyle(Theme.textSecondary)
                }
            }
            .frame(maxWidth: 620, alignment: .leading)
            .padding(.horizontal, 36)
            .padding(.bottom, 40)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var account: some View {
        VStack(alignment: .leading, spacing: 18) {
            card {
                row("Signed in as", model.session?.user.email ?? "-")
                Divider().overlay(Theme.divider)
                row("Name", model.session?.user.displayName ?? "-")
                Divider().overlay(Theme.divider)
                row("Server", model.serverURL.isEmpty ? "-" : model.serverURL)
            }
            HStack(spacing: 12) {
                Button { Task { await model.reloadHome() } } label: { Label("Refresh Home", systemImage: "arrow.clockwise") }
                    .buttonStyle(GlassButtonStyle())
                Button { Task { await model.signOut() } } label: { Label("Sign out", systemImage: "rectangle.portrait.and.arrow.right") }
                    .buttonStyle(GlassButtonStyle())
            }
        }
    }

    private var player: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(PlayerEngine.allCases) { engine in
                Button { model.playerEngine = engine } label: {
                    HStack(spacing: 14) {
                        Image(systemName: model.playerEngine == engine ? "largecircle.fill.circle" : "circle")
                            .foregroundStyle(model.playerEngine == engine ? Theme.accent : Theme.textTertiary)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(engine.title).font(.system(size: 15, weight: .semibold)).foregroundStyle(Theme.textPrimary)
                            Text(engine.detail).font(.system(size: 13)).foregroundStyle(Theme.textSecondary)
                                .multilineTextAlignment(.leading)
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(16)
                    .background(RoundedRectangle(cornerRadius: 14).fill(Theme.elevated))
                    .overlay(RoundedRectangle(cornerRadius: 14).stroke(model.playerEngine == engine ? Theme.accent.opacity(0.7) : Theme.divider, lineWidth: 1))
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var updates: some View {
        card {
            row("Version", AppInfo.version)
            Divider().overlay(Theme.divider)
            Text("Checking for updates from inside the app is coming later. New versions are on the GitHub releases page.")
                .font(.system(size: 13))
                .foregroundStyle(Theme.textSecondary)
        }
    }

    private func card<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) { content() }
            .padding(18)
            .background(RoundedRectangle(cornerRadius: 14).fill(Theme.elevated))
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(Theme.divider, lineWidth: 1))
    }

    private func row(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label).foregroundStyle(Theme.textSecondary)
            Spacer()
            Text(value).foregroundStyle(Theme.textPrimary).lineLimit(1).truncationMode(.middle)
        }
        .font(.system(size: 14))
    }
}

private struct SidebarRow: View {
    let tab: SettingsTab
    let selected: Bool
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: tab.icon)
                    .font(.system(size: 14))
                    .foregroundStyle(selected ? Color(hex: 0x04161A) : Theme.accent)
                    .frame(width: 30, height: 30)
                    .background(RoundedRectangle(cornerRadius: 8).fill(selected ? AnyShapeStyle(Theme.brandGradient) : AnyShapeStyle(Color.white.opacity(0.08))))
                VStack(alignment: .leading, spacing: 1) {
                    Text(tab.rawValue)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(selected ? Theme.textPrimary : Theme.textSecondary)
                    Text(tab.subtitle)
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.textTertiary)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(RoundedRectangle(cornerRadius: 10).fill(Color.white.opacity(selected ? 0.1 : (hovering ? 0.05 : 0))))
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}
