import AppKit
import ArcTVCore
import SwiftUI

/// Puts the mpv video view into SwiftUI and wires it to the model.
struct MPVVideoRepresentable: NSViewRepresentable {
    let url: URL
    let startAt: Double
    let model: MPVPlayerModel
    var languages = PlaybackLanguages()

    func makeNSView(context: Context) -> MPVVideoView {
        let view = MPVVideoView(frame: .zero)
        view.onEvent = { [weak model] event in model?.handle(event) }
        model.view = view
        view.start(url: url, startAt: startAt, languages: languages)
        return view
    }

    func updateNSView(_ view: MPVVideoView, context: Context) {}
}

/// The player, laid out like the Fire TV app's VLC player: back and the 10-second jumps top left, the title's logo and episode top right, and along
/// the bottom a round Play / Pause button, the time played, a thin timeline and the time left, with a centred row of pills under it (Audio,
/// Subtitles, Speed, Episodes, Player, Sources). A spinner sits in the middle while the stream loads, including after a jump.
struct MPVPlayerScreen: View {
    @EnvironmentObject private var appModel: AppModel
    let item: PlayingItem
    @StateObject private var model = MPVPlayerModel()
    @State private var controlsVisible = true
    @State private var hideTask: Task<Void, Never>?
    @State private var scrubbing = false
    @State private var scrubValue: Double = 0
    @State private var fullScreen = false
    @State private var lastHover = Date.distantPast

    private var loading: Bool { (model.buffering || model.seeking) && model.failure == nil }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            MPVVideoRepresentable(
                url: item.url, startAt: item.target.startAt, model: model,
                languages: PlaybackLanguages(
                    audio: appModel.settings?.defaultAudioLanguage,
                    subtitle: appModel.settings?.defaultSubtitleLanguage,
                    subtitlesOn: appModel.settings?.subtitlesEnabled ?? false
                )
            )
                .ignoresSafeArea()
                .onTapGesture { model.togglePause() }
                .onTapGesture(count: 2) { toggleFullScreen() }

            if loading {
                ProgressView().controlSize(.large).allowsHitTesting(false)
            }

            if controlsVisible || model.paused || scrubbing {
                controls.transition(.opacity)
            }

            if let reason = model.failure {
                failurePanel(reason)
            }

            keyboardShortcuts
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onContinuousHover { phase in
            // Mouse moves arrive dozens of times a second; only restart the hide timer a couple of times a second.
            if case .active = phase, !controlsVisible || Date().timeIntervalSince(lastHover) > 0.5 {
                lastHover = Date()
                showControls()
            }
        }
        .onChange(of: model.ended) { ended in
            if ended { appModel.goBack() }
        }
        .onAppear {
            showControls()
            fullScreen = NSApp.keyWindow?.styleMask.contains(.fullScreen) ?? false
        }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didEnterFullScreenNotification)) { _ in fullScreen = true }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didExitFullScreenNotification)) { _ in fullScreen = false }
        .task {
            // Tell the account where you are every half minute, so Continue Watching is right on every device.
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 30_000_000_000)
                if Task.isCancelled { break }
                await appModel.reportProgress(item.target, position: model.position, duration: model.duration)
            }
        }
        .onDisappear {
            hideTask?.cancel()
            let target = item.target, position = model.position, duration = model.duration
            Task { await appModel.reportProgress(target, position: position, duration: duration) }
            model.stop()
        }
        .animation(.easeOut(duration: 0.2), value: controlsVisible)
    }

    // MARK: Controls

    private var controls: some View {
        ZStack {
            VStack(spacing: 0) {
                LinearGradient(colors: [.black.opacity(0.8), .clear], startPoint: .top, endPoint: .bottom).frame(height: 170)
                Spacer()
                LinearGradient(colors: [.clear, .black.opacity(0.9)], startPoint: .top, endPoint: .bottom).frame(height: 250)
            }
            .allowsHitTesting(false)
            .ignoresSafeArea()

            VStack(spacing: 0) {
                HStack(alignment: .top) {
                    HStack(spacing: 10) {
                        roundIcon("arrow.left", help: "Back") { appModel.goBack() }
                        roundIcon("gobackward.10", help: "Back 10 seconds") { model.skip(-10) }
                        roundIcon("goforward.10", help: "Forward 10 seconds") { model.skip(10) }
                    }
                    Spacer()
                    titleEnd
                }
                .padding(.horizontal, 40)
                .padding(.top, 28)
                Spacer()
                VStack(spacing: 6) {
                    HStack(spacing: 14) {
                        playButton
                        Text(MPVPlayerModel.clock(scrubbing ? scrubValue : model.position))
                            .font(.system(size: 13, weight: .medium).monospacedDigit())
                            .foregroundStyle(Theme.textPrimary)
                        PlayerTimeline(
                            value: scrubbing ? scrubValue : model.position,
                            total: model.duration,
                            onScrub: { scrubbing = true; scrubValue = $0 },
                            onEnd: { value in
                                model.seek(to: value)
                                scrubbing = false
                            }
                        )
                        Text("\u{2212}" + MPVPlayerModel.clock(max(0, model.duration - (scrubbing ? scrubValue : model.position))))
                            .font(.system(size: 13, weight: .medium).monospacedDigit())
                            .foregroundStyle(Theme.textPrimary)
                    }
                    pills
                }
                .padding(.horizontal, 40)
                .padding(.bottom, 28)
            }
        }
    }

    /// Top right: the title's logo (its name when there is none) and "S1 E2 • title" for an episode.
    private var titleEnd: some View {
        let title = item.target.title
        return VStack(alignment: .trailing, spacing: 4) {
            if let logo = title.logo, let url = URL(string: logo) {
                CachedImage(url: url, contentMode: .fit) { nameText(title.name) }
                    .frame(maxWidth: 280, maxHeight: 56, alignment: .trailing)
            } else {
                nameText(title.name)
            }
            if let season = item.target.season, let episode = item.target.episode {
                let name = title.seasons[season]?.first { $0.episode == episode }?.displayTitle
                Text("S\(season) E\(episode)" + (name.map { " \u{2022} \($0)" } ?? ""))
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.textSecondary)
            }
        }
    }

    private func nameText(_ name: String) -> some View {
        Text(name).font(.system(size: 22, weight: .bold)).foregroundStyle(Theme.textPrimary).multilineTextAlignment(.trailing)
    }

    private var playButton: some View {
        Button { model.togglePause() } label: {
            Image(systemName: model.paused ? "play.fill" : "pause.fill")
                .font(.system(size: 22))
                .foregroundStyle(.black)
                .frame(width: 48, height: 48)
                .background(Circle().fill(Color.white))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .help(model.paused ? "Play" : "Pause")
    }

    private func roundIcon(_ symbol: String, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 40, height: 40)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(help)
    }

    // MARK: Pills

    private var pills: some View {
        HStack(spacing: 10) {
            if !model.audioTracks.isEmpty {
                trackPill("Audio", "speaker.wave.2.fill", tracks: model.audioTracks, none: nil) { model.selectAudio($0) }
            }
            if !model.subtitleTracks.isEmpty {
                trackPill("Subtitles", "captions.bubble.fill", tracks: model.subtitleTracks, none: "Off") { model.selectSubtitle($0) }
            }
            speedPill
            if !item.target.title.seasonNumbers.isEmpty { episodesPill }
            playerPill
            Button { appModel.goBack() } label: { PillLabel(text: "Sources", symbol: "arrow.left.arrow.right") }
                .buttonStyle(.plain)
        }
        .frame(maxWidth: .infinity)
        .overlay(alignment: .trailing) {
            Button { toggleFullScreen() } label: {
                Image(systemName: fullScreen ? "arrow.down.right.and.arrow.up.left" : "arrow.up.left.and.arrow.down.right")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 40, height: 40)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(fullScreen ? "Exit full screen" : "Full screen")
        }
    }

    private func trackPill(_ title: String, _ symbol: String, tracks: [MediaTrack], none: String?, select: @escaping (MediaTrack?) -> Void) -> some View {
        Menu {
            if let none { Button(none) { select(nil) } }
            ForEach(tracks) { track in
                Button { select(track) } label: {
                    if track.selected { Label(track.label, systemImage: "checkmark") } else { Text(track.label) }
                }
            }
        } label: { PillLabel(text: title, symbol: symbol) }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
    }

    private var speedPill: some View {
        Menu {
            ForEach([0.5, 0.75, 1, 1.25, 1.5, 2], id: \.self) { value in
                Button { model.setSpeed(value) } label: {
                    let label = value == value.rounded() ? "\(Int(value))x" : "\(value)x"
                    if model.speed == value { Label(label, systemImage: "checkmark") } else { Text(label) }
                }
            }
        } label: { PillLabel(text: model.speed == model.speed.rounded() ? "\(Int(model.speed))x" : "\(model.speed)x", symbol: "speedometer") }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
    }

    /// Episodes of a show: pick one and its sources open.
    private var episodesPill: some View {
        let title = item.target.title
        return Menu {
            ForEach(title.seasonNumbers, id: \.self) { number in
                Menu("Season \(number)") {
                    ForEach(title.seasons[number] ?? []) { episode in
                        Button("\(episode.episode ?? 0). \(episode.displayTitle)") { playEpisode(episode) }
                    }
                }
            }
        } label: { PillLabel(text: "Episodes", symbol: "rectangle.stack.fill") }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
    }

    /// Switch between the Arc TV player and the Mac's own, carrying on from the same spot.
    private var playerPill: some View {
        Menu {
            ForEach(PlayerEngine.allCases) { engine in
                Button {
                    appModel.playing?.target.startAt = model.position
                    appModel.playerEngine = engine
                } label: {
                    if appModel.playerEngine == engine { Label(engine.title, systemImage: "checkmark") } else { Text(engine.title) }
                }
            }
        } label: { PillLabel(text: "Player", symbol: "square.and.arrow.up") }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
    }

    private func playEpisode(_ episode: EpisodeInfo) {
        let title = item.target.title
        let target = PlayTarget(
            title: title, season: episode.season, episode: episode.episode,
            episodeTitle: "S\(episode.season ?? 0) E\(episode.episode ?? 0) \(episode.displayTitle)"
        )
        Task {
            await appModel.reportProgress(item.target, position: model.position, duration: model.duration)
            appModel.playing = nil
            appModel.openSources(target)
        }
    }

    /// Space pauses, the arrow keys skip 10 seconds (up and down change the volume), F goes full screen, and Esc only leaves full screen.
    private var keyboardShortcuts: some View {
        ZStack {
            Button("") { model.togglePause() }.keyboardShortcut(.space, modifiers: [])
            Button("") { model.skip(-10) }.keyboardShortcut(.leftArrow, modifiers: [])
            Button("") { model.skip(10) }.keyboardShortcut(.rightArrow, modifiers: [])
            Button("") { model.setVolume(min(100, model.volume + 10)) }.keyboardShortcut(.upArrow, modifiers: [])
            Button("") { model.setVolume(max(0, model.volume - 10)) }.keyboardShortcut(.downArrow, modifiers: [])
            Button("") { toggleFullScreen() }.keyboardShortcut("f", modifiers: [])
            // Esc leaves full screen; it is not a back button here.
            Button("") { if fullScreen { toggleFullScreen() } }.keyboardShortcut(.escape, modifiers: [])
        }
        .opacity(0)
        .allowsHitTesting(false)
    }

    private func failurePanel(_ reason: String) -> some View {
        VStack(spacing: 14) {
            Text("This source couldn't be played")
                .font(.system(size: 22, weight: .heavy))
                .foregroundStyle(Theme.textPrimary)
            Text("The player reported: \(reason). The file or the link may be broken. Try another source.")
                .foregroundStyle(Theme.textSecondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 440)
            HStack(spacing: 12) {
                Button { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(item.url.absoluteString, forType: .string) } label: {
                    Label("Copy link", systemImage: "doc.on.doc")
                }
                .buttonStyle(GlassButtonStyle())
                Button { appModel.goBack() } label: { Label("Other sources", systemImage: "list.bullet") }
                    .buttonStyle(BrandButtonStyle())
            }
        }
        .padding(28)
        .background(RoundedRectangle(cornerRadius: 18).fill(Theme.elevated.opacity(0.96)))
        .overlay(RoundedRectangle(cornerRadius: 18).stroke(Theme.divider, lineWidth: 1))
    }

    // MARK: Behaviour

    private func showControls() {
        controlsVisible = true
        hideTask?.cancel()
        hideTask = Task {
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            guard !Task.isCancelled else { return }
            controlsVisible = false
        }
    }

    private func toggleFullScreen() {
        NSApp.keyWindow?.toggleFullScreen(nil)
    }
}

/// One rounded pill under the timeline: grey, white text, an icon at the left.
private struct PillLabel: View {
    let text: String
    let symbol: String

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: symbol).font(.system(size: 12))
            Text(text).font(.system(size: 13, weight: .medium)).lineLimit(1)
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(Capsule().fill(Color(hex: 0x5A5A5A).opacity(0.85)))
        .overlay(Capsule().stroke(Color.white.opacity(0.25), lineWidth: 1))
        .contentShape(Capsule())
    }
}

/// The thin timeline between the two times: a track, what has played, and a dot while it is being dragged or hovered. Click or drag to jump.
private struct PlayerTimeline: View {
    let value: Double
    let total: Double
    let onScrub: (Double) -> Void
    let onEnd: (Double) -> Void
    @State private var hovering = false
    @State private var dragging = false

    var body: some View {
        GeometryReader { geo in
            let width = max(geo.size.width, 1)
            let fraction = total > 0 ? min(max(value / total, 0), 1) : 0
            ZStack(alignment: .leading) {
                Capsule().fill(Color.white.opacity(0.3)).frame(height: hovering || dragging ? 6 : 4)
                Capsule().fill(Theme.accent).frame(width: width * fraction, height: hovering || dragging ? 6 : 4)
                Circle().fill(Color.white).frame(width: 14, height: 14)
                    .offset(x: width * fraction - 7)
                    .opacity(hovering || dragging ? 1 : 0)
            }
            .frame(maxHeight: .infinity)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { drag in
                        dragging = true
                        onScrub(total * Double(min(max(drag.location.x / width, 0), 1)))
                    }
                    .onEnded { drag in
                        dragging = false
                        onEnd(total * Double(min(max(drag.location.x / width, 0), 1)))
                    }
            )
            .onHover { hovering = $0 }
        }
        .frame(height: 24)
    }
}
