import ArcTVCore
import CTorrent
import Foundation

enum TorrentError: LocalizedError {
    case couldNotStart
    case noFileList
    case noVideo
    case noData
    case serverFailed
    case tooBig(size: Int64, limitGB: Int)

    var errorDescription: String? {
        switch self {
        case .couldNotStart: return "The torrent could not be started."
        case .noFileList: return "No one is sharing this torrent right now (it never gave its file list). Try another source."
        case .noVideo: return "This torrent has no video file in it."
        case .noData: return "The video did not start downloading in time. It may have too few people sharing it. Try another source."
        case .serverFailed: return "The player could not be given the video."
        case let .tooBig(size, limit):
            return String(format: "This file is %.1f GB, more than your torrent storage limit (%d GB). Raise the limit in Settings > Player, or pick a smaller source.", Double(size) / 1_073_741_824, limit)
        }
    }
}

/// What the person sees while a torrent gets ready.
struct TorrentProgress: Equatable {
    var message: String
    var detail: String?
}

/// Streams a torrent through libtorrent: finds the video, downloads it in order and serves it to the player over a local address. One torrent at
/// a time (the one being watched); its files are deleted when it stops.
@MainActor
final class TorrentEngine: ObservableObject {
    static let shared = TorrentEngine()

    @Published private(set) var progress: TorrentProgress?
    @Published var failure: String?

    private var engine: EngineRef?
    private var server: TorrentStreamServer?
    private let folder = FileManager.default.temporaryDirectory.appendingPathComponent("ArcTVTorrents", isDirectory: true)

    private func ensureEngine() throws -> EngineRef {
        if let engine { return engine }
        guard let pointer = ct_create() else { throw TorrentError.couldNotStart }
        let ref = EngineRef(pointer)
        engine = ref
        return ref
    }

    /// Starts the torrent and returns the local address of its video once the first part has arrived. Throws when cancelled.
    func prepare(magnet: String, fileIndex: Int?, season: Int?, episode: Int?) async throws -> URL {
        stop()
        failure = nil
        let engine = try ensureEngine()
        try? FileManager.default.removeItem(at: folder)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        guard ct_start(engine.pointer, magnet, folder.path) == 0 else { throw TorrentError.couldNotStart }
        progress = TorrentProgress(message: "Finding people who share this…", detail: nil)

        // 1. The file list.
        var status = ct_status()
        let metadataDeadline = Date().addingTimeInterval(120)
        while true {
            try Task.checkCancellation()
            ct_get_status(engine.pointer, &status)
            if status.has_metadata != 0 { break }
            if Date() > metadataDeadline { throw TorrentError.noFileList }
            progress = TorrentProgress(
                message: status.num_peers > 0 ? "Getting the file list…" : "Finding people who share this…",
                detail: status.num_peers > 0 ? "\(status.num_peers) connected" : nil
            )
            try await Task.sleep(nanoseconds: 500_000_000)
        }

        // 2. The video to play.
        var files: [TorrentFile] = []
        for index in 0..<Int(status.file_count) {
            var name = [CChar](repeating: 0, count: 2048)
            var size: Int64 = 0
            if ct_file_info(engine.pointer, Int32(index), &name, 2048, &size) == 0 {
                files.append(TorrentFile(index: index, name: String(cString: name), size: size))
            }
        }
        guard let chosen = TorrentFileChoice.pick(from: files, hint: fileIndex, season: season, episode: episode),
              let file = files.first(where: { $0.index == chosen }) else { throw TorrentError.noVideo }
        let limit = TorrentStorage.currentGB
        guard TorrentStorage.allows(size: file.size, gigabytes: limit) else { throw TorrentError.tooBig(size: file.size, limitGB: limit) }
        guard ct_select_file(engine.pointer, Int32(chosen)) == 0 else { throw TorrentError.couldNotStart }
        let buffer = TorrentBuffer.current
        ct_stream_from(engine.pointer, Int32(chosen), 0, Int32(buffer.piecesAhead))
        var pathBuffer = [CChar](repeating: 0, count: 4096)
        guard ct_file_path(engine.pointer, Int32(chosen), &pathBuffer, 4096) == 0 else { throw TorrentError.couldNotStart }
        let video = TorrentVideo(engine: engine, index: Int32(chosen), size: file.size, path: String(cString: pathBuffer), piecesAhead: buffer.piecesAhead)

        // 3. A local address for the player.
        let server = try TorrentStreamServer(video: video)
        self.server = server
        let url = try await server.start()

        // 4. Wait for the first few megabytes, so the player has something to start on.
        let wanted = min(file.size, buffer.startBytes)
        let dataDeadline = Date().addingTimeInterval(180)
        while ct_have_range(engine.pointer, Int32(chosen), 0, wanted) == 0 {
            try Task.checkCancellation()
            if Date() > dataDeadline { throw TorrentError.noData }
            ct_get_status(engine.pointer, &status)
            let speed = Double(status.download_rate) / 1_048_576
            progress = TorrentProgress(
                message: "Getting your video ready…",
                detail: "\(status.num_peers) connected · " + String(format: "%.1f MB/s", speed)
            )
            try await Task.sleep(nanoseconds: 500_000_000)
        }
        progress = nil
        return url
    }

    /// Stops the torrent, closes the local address and deletes what was downloaded.
    func stop() {
        server?.stop()
        server = nil
        if let engine { ct_stop(engine.pointer, 1) }
        progress = nil
        try? FileManager.default.removeItem(at: folder)
    }
}
