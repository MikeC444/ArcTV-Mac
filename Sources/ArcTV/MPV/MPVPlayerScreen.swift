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
    @State private var openMenu: PlayerMenu?
    @State private var menuSeason: Int?

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

            if !model.hasStarted && model.failure == nil {
                PlayerLoadingCover(title: item.target.title).allowsHitTesting(false).transition(.opacity)
            }

            if loading {
                ProgressView().controlSize(.large).allowsHitTesting(false)
            }

            if controlsVisible || model.paused || scrubbing || openMenu != nil {
                controls.transition(.opacity)
            }

            nextEpisodeButton
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                .padding(.trailing, 40)
                .padding(.bottom, 130)

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
            guard ended, !model.placeholder else { return }
            // The video finished: carry on with the next episode when Auto Play Next Episode is on, else go back.
            if let next = nextEpisode, appModel.settings?.autoplayNextEpisode ?? true { playEpisode(next, auto: true) } else { appModel.goBack() }
        }
        .onChange(of: openMenu) { open in if open == nil { showControls() } }
        .onAppear {
            model.runtimeMinutes = Format.runtimeMinutes(item.target.title.runtime)
            model.preferredSubtitleLanguage = appModel.settings?.defaultSubtitleLanguage
            model.subtitlesEnabled = appModel.settings?.subtitlesEnabled ?? false
            showControls()
            fullScreen = NSApp.keyWindow?.styleMask.contains(.fullScreen) ?? false
        }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didEnterFullScreenNotification)) { _ in fullScreen = true }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didExitFullScreenNotification)) { _ in fullScreen = false }
        .task(id: item.url) {
            // Ask the addons for subtitle files once per video; the list is ready (or empty) well before anyone opens the menu.
            let found = await SubtitleFinder.find(
                addons: appModel.addons, type: item.target.title.type, id: item.target.streamID, filename: item.filename,
                preferredLanguage: appModel.settings?.defaultSubtitleLanguage
            )
            if !Task.isCancelled { model.setAddonSubtitles(found) }
        }
        .task {
            // Tell the account where you are every half minute, so Continue Watching is right on every device.
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 30_000_000_000)
                if Task.isCancelled { break }
                if model.placeholder { continue }
                await appModel.reportProgress(item.target, position: model.position, duration: model.duration)
            }
        }
        .onDisappear {
            hideTask?.cancel()
            let target = item.target, position = model.position, duration = model.duration
            if !model.placeholder { Task { await appModel.reportProgress(target, position: position, duration: duration) } }
            model.stop()
        }
        .animation(.easeOut(duration: 0.2), value: controlsVisible)
        .animation(.easeOut(duration: 0.3), value: model.hasStarted)
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

            if openMenu != nil {
                Color.black.opacity(0.001).contentShape(Rectangle()).onTapGesture { openMenu = nil }
            }

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

    // MARK: Pills and their menus

    enum PlayerMenu: Hashable { case audio, subtitles, speed, episodes, player }

    private var pills: some View {
        HStack(spacing: 10) {
            if !model.audioTracks.isEmpty { pill(.audio, "Audio", "speaker.wave.2.fill") }
            if !model.subtitleTracks.isEmpty || !model.addonSubtitles.isEmpty { pill(.subtitles, "Subtitles", "captions.bubble.fill") }
            pill(.speed, model.speed == model.speed.rounded() ? "\(Int(model.speed))x" : "\(model.speed)x", "speedometer")
            if !item.target.title.seasonNumbers.isEmpty { pill(.episodes, "Episodes", "rectangle.stack.fill") }
            pill(.player, "Player", "square.and.arrow.up")
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

    /// A pill that opens its menu above itself; the menu is a dark card, not the system's pop-up list.
    private func pill(_ kind: PlayerMenu, _ text: String, _ symbol: String) -> some View {
        Button { openMenu = openMenu == kind ? nil : kind } label: { PillLabel(text: text, symbol: symbol, active: openMenu == kind) }
            .buttonStyle(.plain)
            .overlay(alignment: .bottom) {
                if openMenu == kind {
                    menuCard(kind).fixedSize().offset(y: -44)
                }
            }
            .zIndex(openMenu == kind ? 1 : 0)
    }

    @ViewBuilder
    private func menuCard(_ kind: PlayerMenu) -> some View {
        switch kind {
        case .audio:
            card("Audio") {
                ForEach(model.audioTracks) { track in
                    MenuRow(main: track.title.isEmpty ? "Track \(track.id)" : track.title, side: track.language?.uppercased(), selected: track.selected) {
                        model.selectAudio(track)
                        openMenu = nil
                    }
                }
            }
        case .subtitles:
            card("Subtitles") {
                MenuRow(main: "Off", side: nil, selected: !model.subtitleTracks.contains { $0.selected }) {
                    model.selectSubtitle(nil)
                    openMenu = nil
                }
                // The file's own tracks first, then the addons' files ("English · Addon name"); a file already loaded is one of mpv's tracks.
                ForEach(model.subtitleTracks.filter { !model.loadedAddonTracks.values.contains($0.id) }) { track in
                    MenuRow(main: track.title.isEmpty ? "Track \(track.id)" : track.title, side: track.language?.uppercased(), selected: track.selected) {
                        model.selectSubtitle(track)
                        openMenu = nil
                    }
                }
                ForEach(model.addonSubtitles) { file in
                    let shown = model.loadedAddonTracks[file.url].map { id in model.subtitleTracks.contains { $0.id == id && $0.selected } } ?? false
                    MenuRow(main: file.menuTitle, side: nil, selected: shown) {
                        model.selectAddonSubtitle(file)
                        openMenu = nil
                    }
                }
            }
        case .speed:
            card("Playback speed") {
                ForEach([0.5, 0.75, 1, 1.25, 1.5, 2], id: \.self) { value in
                    MenuRow(main: value == value.rounded() ? "\(Int(value))x" : "\(value)x", side: value == 1 ? "Normal" : nil, selected: model.speed == value) {
                        model.setSpeed(value)
                        openMenu = nil
                    }
                }
            }
        case .player:
            card("Player") {
                ForEach(PlayerEngine.allCases) { engine in
                    MenuRow(main: engine.title, side: nil, selected: appModel.playerEngine == engine) {
                        openMenu = nil
                        appModel.playing?.target.startAt = model.position
                        appModel.playerEngine = engine
                    }
                }
            }
        case .episodes:
            episodesCard
        }
    }

    private func card<Content: View>(_ title: String, @ViewBuilder _ rows: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title.uppercased())
                .font(.system(size: 11, weight: .bold))
                .tracking(1.2)
                .foregroundStyle(Theme.textTertiary)
                .padding(.horizontal, 12)
                .padding(.top, 6)
                .padding(.bottom, 4)
            ScrollView { VStack(alignment: .leading, spacing: 2) { rows() } }
                .frame(maxHeight: 300)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(8)
        .frame(minWidth: 260, maxWidth: 380, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 16).fill(Theme.elevated.opacity(0.98)))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(Theme.divider, lineWidth: 1))
        .shadow(color: .black.opacity(0.55), radius: 22, y: 8)
    }

    /// Seasons as numbers along the top and the chosen season's episodes under them.
    private var episodesCard: some View {
        let title = item.target.title
        let shown = menuSeason ?? item.target.season ?? title.seasonNumbers.first ?? 1
        return VStack(alignment: .leading, spacing: 8) {
            Text("EPISODES")
                .font(.system(size: 11, weight: .bold))
                .tracking(1.2)
                .foregroundStyle(Theme.textTertiary)
                .padding(.horizontal, 12)
                .padding(.top, 6)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(title.seasonNumbers, id: \.self) { number in
                        Button { menuSeason = number } label: {
                            Text("\(number)")
                                .font(.system(size: 13, weight: .bold))
                                .foregroundStyle(number == shown ? Color.black : Theme.textSecondary)
                                .frame(width: 32, height: 32)
                                .background(Circle().fill(number == shown ? Color.white : Color.white.opacity(0.12)))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 12)
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(title.seasons[shown] ?? []) { episode in
                        MenuRow(
                            main: "\(episode.episode ?? 0). \(episode.displayTitle)", side: nil,
                            selected: episode.season == item.target.season && episode.episode == item.target.episode
                        ) {
                            openMenu = nil
                            playEpisode(episode)
                        }
                    }
                }
            }
            .frame(maxHeight: 260)
            .fixedSize(horizontal: false, vertical: true)
        }
        .padding(8)
        .frame(width: 380, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 16).fill(Theme.elevated.opacity(0.98)))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(Theme.divider, lineWidth: 1))
        .shadow(color: .black.opacity(0.55), radius: 22, y: 8)
    }

    // MARK: Next episode

    private var nextEpisode: EpisodeInfo? {
        guard let season = item.target.season, let episode = item.target.episode else { return nil }
        return item.target.title.episode(after: season, episode)
    }

    private var inLastMinute: Bool { model.duration > 120 && model.duration - model.position <= 60 }

    private var nextEpisodeButton: some View {
        Group {
            if let next = nextEpisode, inLastMinute {
                Button { playEpisode(next, auto: true) } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "forward.end.fill").font(.system(size: 18))
                        VStack(alignment: .leading, spacing: 1) {
                            Text("Next episode").font(.system(size: 15, weight: .bold))
                            Text("S\(next.season ?? 0) E\(next.episode ?? 0) \u{2022} \(next.displayTitle)")
                                .font(.system(size: 12))
                                .lineLimit(1)
                        }
                    }
                    .foregroundStyle(.black)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 12)
                    .background(Capsule().fill(Color.white))
                }
                .buttonStyle(.plain)
                .shadow(color: .black.opacity(0.5), radius: 14, y: 4)
                .transition(.opacity.combined(with: .move(edge: .trailing)))
            }
        }
        .animation(.easeOut(duration: 0.25), value: inLastMinute)
    }

    private func playEpisode(_ episode: EpisodeInfo, auto: Bool = false) {
        let title = item.target.title
        let target = PlayTarget(
            title: title, season: episode.season, episode: episode.episode,
            episodeTitle: "S\(episode.season ?? 0) E\(episode.episode ?? 0) \(episode.displayTitle)", autoPick: auto
        )
        Task {
            if !model.placeholder { await appModel.reportProgress(item.target, position: model.position, duration: model.duration) }
            appModel.playing = nil
            appModel.openSources(target)
        }
    }

    /// Space pauses, the left and right arrow keys go back and forward 10 seconds (up and down change the volume), M mutes, C turns captions on or off
    /// (in the Settings language), F goes full screen, and Esc only leaves full screen.
    private var keyboardShortcuts: some View {
        ZStack {
            Button("") { model.togglePause() }.keyboardShortcut(.space, modifiers: [])
            Button("") { model.skip(-10) }.keyboardShortcut(.leftArrow, modifiers: [])
            Button("") { model.skip(10) }.keyboardShortcut(.rightArrow, modifiers: [])
            Button("") { model.setVolume(min(100, model.volume + 10)) }.keyboardShortcut(.upArrow, modifiers: [])
            Button("") { model.setVolume(max(0, model.volume - 10)) }.keyboardShortcut(.downArrow, modifiers: [])
            Button("") { toggleFullScreen() }.keyboardShortcut("f", modifiers: [])
            Button("") { model.toggleMute() }.keyboardShortcut("m", modifiers: [])
            Button("") { model.toggleCaptions() }.keyboardShortcut("c", modifiers: [])
            // Esc leaves full screen; it is not a back button here.
            Button("") { if fullScreen { toggleFullScreen() } }.keyboardShortcut(.escape, modifiers: [])
        }
        .opacity(0)
        .allowsHitTesting(false)
    }

    private func failurePanel(_ reason: String) -> some View {
        VStack(spacing: 14) {
            Text(model.placeholder ? "This source isn't ready yet" : "This source couldn't be played")
                .font(.system(size: 22, weight: .heavy))
                .foregroundStyle(Theme.textPrimary)
            Text(model.placeholder ? reason : "The player reported: \(reason). The file or the link may be broken. Try another source.")
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
            guard openMenu == nil else { return }
            controlsVisible = false
            // With the controls gone and the picture playing, the mouse pointer goes too, until the mouse moves again.
            if !model.paused { NSCursor.setHiddenUntilMouseMoves(true) }
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
    var active = false

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: symbol).font(.system(size: 12))
            Text(text).font(.system(size: 13, weight: .medium)).lineLimit(1)
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(Capsule().fill(active ? Color.white.opacity(0.28) : Color(hex: 0x5A5A5A).opacity(0.85)))
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

/// One line of a player menu: a tick for the chosen one, its name, and a small grey note (the language) at the right.
private struct MenuRow: View {
    let main: String
    let side: String?
    let selected: Bool
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: "checkmark")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(Theme.accent)
                    .frame(width: 16)
                    .opacity(selected ? 1 : 0)
                Text(main)
                    .font(.system(size: 14, weight: selected ? .semibold : .regular))
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(1)
                Spacer(minLength: 16)
                if let side {
                    Text(side)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Theme.textSecondary)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(Color.white.opacity(0.1)))
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 9).fill(hovering ? Color.white.opacity(0.1) : (selected ? Color.white.opacity(0.05) : .clear)))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}

/// What fills the player until the first picture plays: the title's artwork, darkened, with its logo (or name) in the middle.
private struct PlayerLoadingCover: View {
    let title: MetaDetail

    var body: some View {
        ZStack {
            Color.black
            if let url = (title.background ?? title.poster).flatMap(URL.init(string:)) {
                GeometryReader { geo in
                    CachedImage(url: url) { Color.clear }
                        .frame(width: geo.size.width, height: geo.size.height)
                        .clipped()
                }
            }
            Color.black.opacity(0.6)
            VStack {
                if let logo = title.logo, let url = URL(string: logo) {
                    CachedImage(url: url, contentMode: .fit) { name }
                        .frame(maxWidth: 460, maxHeight: 150)
                        .shadow(color: .black.opacity(0.6), radius: 8, y: 2)
                } else {
                    name
                }
                Spacer().frame(height: 90)
            }
        }
        .ignoresSafeArea()
    }

    private var name: some View {
        Text(title.name).font(.system(size: 40, weight: .heavy)).foregroundStyle(Theme.textPrimary).multilineTextAlignment(.center)
    }
}
