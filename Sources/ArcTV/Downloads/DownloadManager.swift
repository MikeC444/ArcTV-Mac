import AppKit
import ArcTVCore
import Foundation

/// Saves files from a title's page into the Mac's Downloads folder, a few at a time, and keeps what each one is doing.
@MainActor
final class DownloadManager: NSObject, ObservableObject, URLSessionDownloadDelegate {
    static let shared = DownloadManager()

    struct Job: Identifiable, Equatable {
        enum State: Equatable { case running, done, failed(String) }
        var id: Int
        var name: String
        var fraction: Double?
        var state: State = .running
        var fileURL: URL?
    }

    @Published private(set) var jobs: [Job] = []
    private var session: URLSession!

    override private init() {
        super.init()
        session = URLSession(configuration: .default, delegate: self, delegateQueue: nil)
    }

    func start(url: URL, fileName: String) {
        let task = session.downloadTask(with: url)
        jobs.insert(Job(id: task.taskIdentifier, name: fileName), at: 0)
        task.taskDescription = fileName
        task.resume()
    }

    func cancel(_ job: Job) {
        session.getAllTasks { tasks in tasks.first { $0.taskIdentifier == job.id }?.cancel() }
        jobs.removeAll { $0.id == job.id }
    }

    func clearFinished() { jobs.removeAll { $0.state != .running } }

    func reveal(_ job: Job) {
        if let url = job.fileURL { NSWorkspace.shared.activateFileViewerSelecting([url]) }
    }

    private func update(_ id: Int, _ change: @escaping (inout Job) -> Void) {
        guard let index = jobs.firstIndex(where: { $0.id == id }) else { return }
        change(&jobs[index])
    }

    // MARK: URLSessionDownloadDelegate (called off the main thread)

    nonisolated func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64, totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        let id = downloadTask.taskIdentifier
        let fraction: Double? = totalBytesExpectedToWrite > 0 ? Double(totalBytesWritten) / Double(totalBytesExpectedToWrite) : nil
        Task { @MainActor in self.update(id) { $0.fraction = fraction } }
    }

    nonisolated func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        let id = downloadTask.taskIdentifier
        if let http = downloadTask.response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            Task { @MainActor in self.update(id) { $0.state = .failed("The server answered \(http.statusCode).") } }
            return
        }
        // The temporary file is deleted when this method returns, so it is moved now.
        let name = downloadTask.taskDescription ?? "Arc TV download.mkv"
        let folder = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first ?? FileManager.default.temporaryDirectory
        let destination = Self.uniqueURL(in: folder, name: name)
        do {
            try FileManager.default.moveItem(at: location, to: destination)
            Task { @MainActor in self.update(id) { $0.state = .done; $0.fraction = 1; $0.fileURL = destination } }
        } catch {
            Task { @MainActor in self.update(id) { $0.state = .failed("Couldn't save the file to your Downloads folder.") } }
        }
    }

    nonisolated func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        guard let error, (error as NSError).code != NSURLErrorCancelled else { return }
        let id = task.taskIdentifier
        Task { @MainActor in self.update(id) { $0.state = .failed("The download stopped. Check your connection and try again.") } }
    }

    /// "Name.mkv", else "Name 2.mkv", "Name 3.mkv"...
    nonisolated static func uniqueURL(in folder: URL, name: String) -> URL {
        var candidate = folder.appendingPathComponent(name)
        let stem = (name as NSString).deletingPathExtension
        let ext = (name as NSString).pathExtension
        var number = 2
        while FileManager.default.fileExists(atPath: candidate.path) {
            candidate = folder.appendingPathComponent(ext.isEmpty ? "\(stem) \(number)" : "\(stem) \(number).\(ext)")
            number += 1
        }
        return candidate
    }
}
