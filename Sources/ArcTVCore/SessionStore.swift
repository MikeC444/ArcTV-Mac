import Foundation

/// Keeps the signed-in session in a private file in the app's own folder (~/Library/Application Support/ArcTV/session.json, readable only by
/// this Mac account). Not the Keychain: an unsigned app's signature changes with every build and update, and macOS then asks for the login
/// password each time it touches the Keychain item.
public struct SessionStore: Sendable {
    private let fileURL: URL

    public init(directory: URL? = nil) {
        let base = directory ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!.appendingPathComponent("ArcTV", isDirectory: true)
        fileURL = base.appendingPathComponent("session.json")
    }

    public func load() -> Session? {
        guard let data = try? Data(contentsOf: fileURL) else { return nil }
        return try? JSONDecoder().decode(Session.self, from: data)
    }

    public func save(_ session: Session) {
        guard let data = try? JSONEncoder().encode(session) else { return }
        let folder = fileURL.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        try? data.write(to: fileURL, options: .atomic)
        try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: fileURL.path)
    }

    public func clear() {
        try? FileManager.default.removeItem(at: fileURL)
    }
}

/// A random id for this Mac, made once and kept, so the backend can tell devices apart (the other apps do the same).
public enum DeviceIdentity {
    private static let key = "ArcTVDeviceId"

    public static var id: String {
        if let existing = UserDefaults.standard.string(forKey: key) { return existing }
        let made = UUID().uuidString.lowercased()
        UserDefaults.standard.set(made, forKey: key)
        return made
    }

    public static var name: String { Host.current().localizedName ?? "Mac" }
}
