import AppKit
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
    @Published var failure: String?
    @Published var ended = false
    @Published var volume: Double = 100
    @Published var audioTracks: [MediaTrack] = []
    @Published var subtitleTracks: [MediaTrack] = []

    weak var view: MPVVideoView?
    private var started = false

    func handle(_ event: MPVEvent) {
        switch event {
        case let .position(value):
            position = value
            if !started {
                started = true
                buffering = false
                refreshTracks()
            }
        case let .duration(value): duration = value
        case let .paused(value): paused = value
        case let .buffering(value): buffering = value
        case .ended: ended = true
        case let .failed(message): failure = message
        }
    }

    func togglePause() { view?.setFlag("pause", !paused) }

    func seek(to seconds: Double) { view?.seek(to: max(0, min(seconds, duration > 0 ? duration : seconds))) }

    func skip(_ seconds: Double) { view?.seek(by: seconds) }

    func setVolume(_ value: Double) {
        volume = value
        view?.setString("volume", String(Int(value)))
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
