import AppKit
import ArcTVCore
import Foundation
import SwiftUI

/// An audio or subtitle track in the file being played.
struct MediaTrack: Identifiable, Equatable {
    var id: Int
    var type: String
    var title: String
    var language: String?
    var selected: Bool

    var label: String {
        let name = [title.isEmpty ? nil : title, language.map { $0.uppercased() }].compactMap { $0 }.joined(separator: " · ")
        return name.isEmpty ? "Track \(id)" : name
    }
}

/// What the player screen shows and does: the playing position, pause, volume, tracks. The mpv view reports in, the controls send commands out.
@MainActor
final class MPVPlayerModel: ObservableObject {
    @Published var position: Double = 0
    @Published var duration: Double = 0
    @Published var paused = false
    @Published var buffering = true
    /// False until the first picture is playing: the screen shows the title's artwork and logo until then.
    @Published private(set) var hasStarted = false
    /// True from the moment a jump is asked for until mpv has landed on the new spot (and kept playing); shows the spinner while the stream loads.
    @Published var seeking = false
    @Published var failure: String?
    @Published var ended = false
    /// True when the source turned out to be a "not ready yet" slate (see `PlaceholderVideo`): nothing it plays is saved, and its end is not "finished".
    @Published private(set) var placeholder = false
    /// The title's runtime, set by the screen, to recognise such a slate once the length is known.
    var runtimeMinutes: Int? { didSet { checkPlaceholder() } }
    /// The volume and speed last chosen, for every title on this Mac (not part of the synced account settings).
    @Published var volume: Double = UserDefaults.standard.object(forKey: "ArcTVPlayerVolume") as? Double ?? 100
    @Published var speed: Double = UserDefaults.standard.object(forKey: "ArcTVPlayerSpeed") as? Double ?? 1
    @Published var audioTracks: [MediaTrack] = []
    @Published var subtitleTracks: [MediaTrack] = []

    weak var view: MPVVideoView?
    private var started = false

    func handle(_ event: MPVEvent) {
        switch event {
        case let .position(value):
            // mpv reports the position with every frame; SwiftUI redrawing the controls that often is what made the player feel slow.
            if !started || abs(value - position) >= 0.25 { position = value }
            if !started {
                started = true
                hasStarted = true
                buffering = false
                view?.setString("volume", String(Int(volume)))
                if speed != 1 { view?.setString("speed", String(speed)) }
                refreshTracks()
            }
        case let .duration(value):
            duration = value
            checkPlaceholder()
        case let .paused(value): paused = value
        case let .buffering(value): buffering = value
        case let .seeking(value): seeking = value
        case .ended: ended = true
        case let .failed(message): failure = message
        }
    }

    /// A source far shorter than its title is a slate: stop it and say the source isn't ready, instead of playing it as the film.
    private func checkPlaceholder() {
        guard !placeholder, PlaceholderVideo.isPlaceholder(durationSeconds: duration, runtimeMinutes: runtimeMinutes) else { return }
        placeholder = true
        view?.setFlag("pause", true)
        failure = PlaceholderVideo.message
    }

    func togglePause() { view?.setFlag("pause", !paused) }

    private var seekGuard: Task<Void, Never>?

    /// Shows the loading spinner at once; mpv's own "seeking" flag takes over, and a seek that mpv never reports ends after a few seconds anyway.
    private func markSeeking() {
        seeking = true
        seekGuard?.cancel()
        seekGuard = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 8_000_000_000)
            if !Task.isCancelled { self?.seeking = false }
        }
    }

    func seek(to seconds: Double) {
        markSeeking()
        view?.seek(to: max(0, min(seconds, duration > 0 ? duration : seconds)))
    }

    func skip(_ seconds: Double) {
        markSeeking()
        view?.seek(by: seconds)
    }

    func setVolume(_ value: Double) {
        volume = value
        view?.setString("volume", String(Int(value)))
        UserDefaults.standard.set(value, forKey: "ArcTVPlayerVolume")
    }

    func setSpeed(_ value: Double) {
        speed = value
        view?.setString("speed", String(value))
        UserDefaults.standard.set(value, forKey: "ArcTVPlayerSpeed")
    }

    func selectAudio(_ track: MediaTrack?) {
        view?.setString("aid", track.map { String($0.id) } ?? "no")
        refreshTracks()
    }

    func selectSubtitle(_ track: MediaTrack?) {
        view?.setString("sid", track.map { String($0.id) } ?? "no")
        refreshTracks()
    }

    /// Reads mpv's track list (a JSON array) so the menus can list the audio and subtitle tracks.
    func refreshTracks() {
        guard let json = view?.string("track-list"), let data = json.data(using: .utf8),
              let list = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else { return }
        var audio: [MediaTrack] = []
        var subtitles: [MediaTrack] = []
        for entry in list {
            guard let id = entry["id"] as? Int, let type = entry["type"] as? String else { continue }
            let track = MediaTrack(
                id: id, type: type, title: entry["title"] as? String ?? "", language: entry["lang"] as? String,
                selected: entry["selected"] as? Bool ?? false
            )
            if type == "audio" { audio.append(track) } else if type == "sub" { subtitles.append(track) }
        }
        audioTracks = audio
        subtitleTracks = subtitles
    }

    func stop() {
        view?.shutdown()
        view = nil
    }

    static func clock(_ seconds: Double) -> String {
        guard seconds.isFinite, seconds >= 0 else { return "--:--" }
        let total = Int(seconds)
        let hours = total / 3600, minutes = (total % 3600) / 60, secs = total % 60
        return hours > 0 ? String(format: "%d:%02d:%02d", hours, minutes, secs) : String(format: "%d:%02d", minutes, secs)
    }
}
