import AppKit
import ArcTVCore
import SwiftUI

/// Puts the mpv video view into SwiftUI and wires it to the model.
struct MPVVideoRepresentable: NSViewRepresentable {
    let url: URL
    let startAt: Double
    let model: MPVPlayerModel

    func makeNSView(context: Context) -> MPVVideoView {
        let view = MPVVideoView(frame: .zero)
        view.onEvent = { [weak model] event in model?.handle(event) }
        model.view = view
        view.start(url: url, startAt: startAt)
        return view
    }

    func updateNSView(_ view: MPVVideoView, context: Context) {}
}

/// The player: mpv's video with the app's own controls (play and pause, seek bar, volume, audio and subtitle tracks, full screen).
struct MPVPlayerScreen: View {
    @EnvironmentObject private var appModel: AppModel
    let item: PlayingItem
    @StateObject private var model = MPVPlayerModel()
    @State private var controlsVisible = true
    @State private var hideTask: Task<Void, Never>?
    @State private var scrubbing = false
    @State private var scrubValue: Double = 0

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            MPVVideoRepresentable(url: item.url, startAt: item.target.startAt, model: model)
                .ignoresSafeArea()
                .onTapGesture { model.togglePause() }
                .onTapGesture(count: 2) { toggleFullScreen() }

            if model.buffering && model.failure == nil {
                ProgressView().controlSize(.large)
            }

            if controlsVisible || model.paused {
                VStack {
                    topBar
                    Spacer()
                    bottomBar
                }
                .transition(.opacity)
            }

            if let reason = model.failure {
                failurePanel(reason)
            }

            keyboardShortcuts
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onContinuousHover { phase in
            if case .active = phase { showControls() }
        }
        .onChange(of: model.ended) { ended in
            if ended { appModel.goBack() }
        }
        .onAppear { showControls() }
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

    // MARK: Pieces

    private var topBar: some View {
        HStack(spacing: 14) {
            BackButton { appModel.goBack() }
            VStack(alignment: .leading, spacing: 1) {
                Text(item.heading).font(.system(size: 14, weight: .semibold)).foregroundStyle(Theme.textPrimary)
                Text(item.sourceName).font(.system(size: 12)).foregroundStyle(Theme.textSecondary)
            }
            Spacer()
        }
        .padding(.leading, 28)
        .padding(.trailing, 28)
        .padding(.top, 22)
        .padding(.bottom, 30)
        .background(LinearGradient(colors: [.black.opacity(0.7), .clear], startPoint: .top, endPoint: .bottom))
    }

    private var bottomBar: some View {
        VStack(spacing: 8) {
            HStack(spacing: 12) {
                Text(MPVPlayerModel.clock(scrubbing ? scrubValue : model.position))
                    .font(.system(size: 12, weight: .medium).monospacedDigit())
                    .foregroundStyle(Theme.textPrimary)
                    .frame(width: 56, alignment: .trailing)
                Slider(
                    value: Binding(get: { scrubbing ? scrubValue : model.position }, set: { scrubValue = $0 }),
                    in: 0...max(model.duration, 1)
                ) { editing in
                    if editing {
                        scrubbing = true
                    } else {
                        model.seek(to: scrubValue)
                        scrubbing = false
                    }
                }
                .tint(Theme.accent)
                Text(MPVPlayerModel.clock(model.duration))
                    .font(.system(size: 12, weight: .medium).monospacedDigit())
                    .foregroundStyle(Theme.textSecondary)
                    .frame(width: 56, alignment: .leading)
            }

            HStack(spacing: 22) {
                controlButton("gobackward.10") { model.skip(-10) }
                controlButton(model.paused ? "play.fill" : "pause.fill", size: 22) { model.togglePause() }
                controlButton("goforward.10") { model.skip(10) }
                Spacer()
                HStack(spacing: 8) {
                    Image(systemName: model.volume < 1 ? "speaker.slash.fill" : "speaker.wave.2.fill")
                        .foregroundStyle(Theme.textSecondary)
                    Slider(value: Binding(get: { model.volume }, set: { model.setVolume($0) }), in: 0...100)
                        .frame(width: 100)
                        .tint(Theme.textSecondary)
                }
                trackMenu(symbol: "waveform", tracks: model.audioTracks, none: nil, select: { model.selectAudio($0) })
                trackMenu(symbol: "captions.bubble", tracks: model.subtitleTracks, none: "Off", select: { model.selectSubtitle($0) })
                controlButton("arrow.up.left.and.arrow.down.right") { toggleFullScreen() }
            }
            .padding(.horizontal, 6)
        }
        .padding(.horizontal, 28)
        .padding(.top, 36)
        .padding(.bottom, 20)
        .background(LinearGradient(colors: [.clear, .black.opacity(0.75)], startPoint: .top, endPoint: .bottom))
    }

    private func controlButton(_ symbol: String, size: CGFloat = 18, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: size))
                .foregroundStyle(Theme.textPrimary)
                .frame(width: 30, height: 30)
        }
        .buttonStyle(.plain)
    }

    private func trackMenu(symbol: String, tracks: [MediaTrack], none: String?, select: @escaping (MediaTrack?) -> Void) -> some View {
        Menu {
            if let none {
                Button(none) { select(nil) }
            }
            ForEach(tracks) { track in
                Button { select(track) } label: {
                    if track.selected { Label(track.label, systemImage: "checkmark") } else { Text(track.label) }
                }
            }
        } label: {
            Image(systemName: symbol)
                .font(.system(size: 18))
                .foregroundStyle(Theme.textPrimary)
                .frame(width: 30, height: 30)
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .disabled(tracks.isEmpty)
    }

    /// Space pauses, the arrow keys skip 10 seconds, F goes full screen. Esc (Back) is on the Back button.
    private var keyboardShortcuts: some View {
        ZStack {
            Button("") { model.togglePause() }.keyboardShortcut(.space, modifiers: [])
            Button("") { model.skip(-10) }.keyboardShortcut(.leftArrow, modifiers: [])
            Button("") { model.skip(10) }.keyboardShortcut(.rightArrow, modifiers: [])
            Button("") { toggleFullScreen() }.keyboardShortcut("f", modifiers: [])
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
