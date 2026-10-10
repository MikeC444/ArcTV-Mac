import AppKit
import AVKit
import ArcTVCore
import SwiftUI

/// Watches the Mac's built-in player so a source it cannot open is reported instead of leaving a black screen.
@MainActor
final class PlayerController: ObservableObject {
    @Published var failure: String?
    let player: AVPlayer
    private var observation: NSKeyValueObservation?

    init(url: URL) {
        let item = AVPlayerItem(url: url)
        player = AVPlayer(playerItem: item)
        observation = item.observe(\.status, options: [.new]) { [weak self] item, _ in
            guard item.status == .failed else { return }
            let reason = item.error?.localizedDescription ?? "unknown error"
            Task { @MainActor in self?.failure = reason }
        }
    }

    func start() { player.play() }

    func stop() {
        player.pause()
        player.replaceCurrentItem(with: nil)
        observation = nil
    }
}

/// The player: the Mac's own video player (AVKit) in a full window, with Back (or Esc) to leave.
struct PlayerView: View {
    @EnvironmentObject private var model: AppModel
    let item: PlayingItem
    @StateObject private var controller: PlayerController

    init(item: PlayingItem) {
        self.item = item
        _controller = StateObject(wrappedValue: PlayerController(url: item.url))
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            Color.black.ignoresSafeArea()
            VideoPlayer(player: controller.player)
                .ignoresSafeArea()

            HStack(spacing: 14) {
                BackButton { model.goBack() }
                VStack(alignment: .leading, spacing: 1) {
                    Text(item.heading).font(.system(size: 14, weight: .semibold)).foregroundStyle(Theme.textPrimary)
                    Text(item.sourceName).font(.system(size: 12)).foregroundStyle(Theme.textSecondary)
                }
                .shadow(color: .black.opacity(0.7), radius: 4)
            }
            .padding(.leading, 28)
            .padding(.top, 22)

            if let reason = controller.failure {
                failurePanel(reason)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear { controller.start() }
        .onDisappear { controller.stop() }
    }

    private func failurePanel(_ reason: String) -> some View {
        VStack(spacing: 14) {
            Text("This source can't be played here")
                .font(.system(size: 22, weight: .heavy))
                .foregroundStyle(Theme.textPrimary)
            Text("The Mac's built-in player can't open every kind of video file (MKV files, for example). Try another source, or open this one in VLC.")
                .foregroundStyle(Theme.textSecondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 440)
            Text(reason)
                .font(.system(size: 11))
                .foregroundStyle(Theme.textTertiary)
                .lineLimit(2)
                .frame(maxWidth: 440)
            HStack(spacing: 12) {
                if let vlc = Self.vlcURL {
                    Button { openInVLC(vlc) } label: { Label("Open in VLC", systemImage: "play.rectangle") }
                        .buttonStyle(BrandButtonStyle())
                }
                Button { copyLink() } label: { Label("Copy link", systemImage: "doc.on.doc") }
                    .buttonStyle(GlassButtonStyle())
                Button { model.goBack() } label: { Label("Other sources", systemImage: "list.bullet") }
                    .buttonStyle(GlassButtonStyle())
            }
            if Self.vlcURL == nil {
                Text("VLC isn't installed on this Mac. Get it free from videolan.org, then use Open in VLC.")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.textTertiary)
            }
        }
        .padding(28)
        .background(RoundedRectangle(cornerRadius: 18).fill(Theme.elevated.opacity(0.96)))
        .overlay(RoundedRectangle(cornerRadius: 18).stroke(Theme.divider, lineWidth: 1))
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private static var vlcURL: URL? {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: "org.videolan.vlc")
    }

    private func openInVLC(_ app: URL) {
        NSWorkspace.shared.open([item.url], withApplicationAt: app, configuration: NSWorkspace.OpenConfiguration())
    }

    private func copyLink() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(item.url.absoluteString, forType: .string)
    }
}
