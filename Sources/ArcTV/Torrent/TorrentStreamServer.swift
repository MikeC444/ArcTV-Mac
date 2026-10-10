import ArcTVCore
import CTorrent
import Foundation
import Network

/// Wraps the C engine pointer so it can be shared with the server's tasks (libtorrent's calls are safe from any thread).
final class EngineRef: @unchecked Sendable {
    let pointer: OpaquePointer
    init(_ pointer: OpaquePointer) { self.pointer = pointer }
}

/// True once, for the first caller: guards a continuation that more than one callback could resume.
final class OnceFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var used = false
    func first() -> Bool {
        lock.lock(); defer { lock.unlock() }
        if used { return false }
        used = true
        return true
    }
}

/// The video file being streamed out of a torrent.
struct TorrentVideo: Sendable {
    var engine: EngineRef
    var index: Int32
    var size: Int64
    var path: String
    var piecesAhead: Int
}

/// A tiny web server on this Mac only (127.0.0.1) that hands the player the torrent's video as the pieces arrive. The player asks for byte
/// ranges (it seeks); each answer waits until the pieces for that range have been downloaded, and asks the engine to fetch them first.
final class TorrentStreamServer: @unchecked Sendable {
    private let listener: NWListener
    private let queue = DispatchQueue(label: "tv.arc.mac.torrent-server")
    private let lock = NSLock()
    private var stopped = false
    private let video: TorrentVideo
    private(set) var port: UInt16 = 0

    init(video: TorrentVideo) throws {
        self.video = video
        let parameters = NWParameters.tcp
        parameters.requiredLocalEndpoint = NWEndpoint.hostPort(host: .ipv4(.loopback), port: .any)
        listener = try NWListener(using: parameters)
    }

    private var isStopped: Bool {
        lock.lock(); defer { lock.unlock() }
        return stopped
    }

    /// Starts listening and returns the address to give the player.
    func start() async throws -> URL {
        listener.newConnectionHandler = { [weak self] connection in
            guard let self else { connection.cancel(); return }
            connection.start(queue: self.queue)
            Task.detached { [weak self] in
                await self?.serve(connection)
                connection.cancel()
            }
        }
        let port: UInt16 = try await withCheckedThrowingContinuation { continuation in
            let once = OnceFlag()
            listener.stateUpdateHandler = { [listener] state in
                switch state {
                case .ready:
                    if once.first() { continuation.resume(returning: listener.port?.rawValue ?? 0) }
                case .failed(let error):
                    if once.first() { continuation.resume(throwing: error) }
                default:
                    break
                }
            }
            listener.start(queue: queue)
        }
        guard port != 0, let url = URL(string: "http://127.0.0.1:\(port)/video") else { throw TorrentError.serverFailed }
        self.port = port
        return url
    }

    func stop() {
        lock.lock(); stopped = true; lock.unlock()
        listener.cancel()
    }

    // MARK: Serving

    private func receive(_ connection: NWConnection) async -> Data? {
        await withCheckedContinuation { continuation in
            connection.receive(minimumIncompleteLength: 1, maximumLength: 16384) { data, _, _, _ in continuation.resume(returning: data) }
        }
    }

    private func send(_ connection: NWConnection, _ data: Data) async -> Bool {
        await withCheckedContinuation { continuation in
            connection.send(content: data, completion: .contentProcessed { error in continuation.resume(returning: error == nil) })
        }
    }

    private func serve(_ connection: NWConnection) async {
        var request = Data()
        let end = Data("\r\n\r\n".utf8)
        while request.range(of: end) == nil, request.count < 65536 {
            guard let more = await receive(connection) else { return }
            request.append(more)
        }
        let text = String(decoding: request, as: UTF8.self)
        let lines = text.components(separatedBy: "\r\n")
        let first = (lines.first ?? "").split(separator: " ")
        guard first.count >= 2 else { return }
        let method = String(first[0]).uppercased()
        var headers: [String: String] = [:]
        for line in lines.dropFirst() {
            guard let colon = line.firstIndex(of: ":") else { continue }
            headers[line[..<colon].lowercased()] = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
        }
        guard method == "GET" || method == "HEAD" else {
            _ = await send(connection, Data("HTTP/1.1 405 Method Not Allowed\r\nContent-Length: 0\r\nConnection: close\r\n\r\n".utf8))
            return
        }

        let size = video.size
        let range = ByteRange.parse(headers["range"], size: size)
        let start = range?.start ?? 0
        let last = range?.end ?? size - 1
        var head = range == nil ? "HTTP/1.1 200 OK\r\n" : "HTTP/1.1 206 Partial Content\r\n"
        head += "Content-Type: \(Self.contentType(for: video.path))\r\nAccept-Ranges: bytes\r\nContent-Length: \(last - start + 1)\r\n"
        if range != nil { head += "Content-Range: bytes \(start)-\(last)/\(size)\r\n" }
        head += "Connection: close\r\n\r\n"
        guard await send(connection, Data(head.utf8)), method == "GET" else { return }

        ct_stream_from(video.engine.pointer, video.index, start, Int32(video.piecesAhead))
        var handle: FileHandle?
        defer { try? handle?.close() }
        var position = start
        var chunksSincePush = 0
        while position <= last, !isStopped {
            let length = min(Int64(256 * 1024), last - position + 1)
            var waited = 0
            while ct_have_range(video.engine.pointer, video.index, position, length) == 0 {
                if isStopped { return }
                try? await Task.sleep(nanoseconds: 100_000_000)
                waited += 1
                if waited % 20 == 0 { ct_stream_from(video.engine.pointer, video.index, position, Int32(video.piecesAhead)) }
            }
            if handle == nil { handle = try? FileHandle(forReadingFrom: URL(fileURLWithPath: video.path)) }
            guard let file = handle else { try? await Task.sleep(nanoseconds: 200_000_000); continue }
            let data: Data
            do {
                try file.seek(toOffset: UInt64(position))
                data = try file.read(upToCount: Int(length)) ?? Data()
            } catch {
                return
            }
            if data.isEmpty { return }
            guard await send(connection, data) else { return }
            position += Int64(data.count)
            chunksSincePush += 1
            if chunksSincePush >= 4 {
                chunksSincePush = 0
                ct_stream_from(video.engine.pointer, video.index, position, Int32(video.piecesAhead))
            }
        }
    }

    static func contentType(for path: String) -> String {
        switch (path as NSString).pathExtension.lowercased() {
        case "mp4", "m4v": return "video/mp4"
        case "mkv": return "video/x-matroska"
        case "webm": return "video/webm"
        case "mov": return "video/quicktime"
        case "avi": return "video/x-msvideo"
        default: return "application/octet-stream"
        }
    }
}
