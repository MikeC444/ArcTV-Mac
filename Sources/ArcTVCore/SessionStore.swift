import Foundation
import Security

/// Keeps the signed-in session in the macOS Keychain (an ordinary generic-password item, which works for an ad-hoc-signed app).
public struct SessionStore: Sendable {
    private let service = "tv.arc.mac"
    private let account = "session"

    public init() {}

    public func load() -> Session? {
        var query = baseQuery()
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess, let data = result as? Data else { return nil }
        return try? JSONDecoder().decode(Session.self, from: data)
    }

    public func save(_ session: Session) {
        guard let data = try? JSONEncoder().encode(session) else { return }
        let update = [kSecValueData as String: data]
        if SecItemUpdate(baseQuery() as CFDictionary, update as CFDictionary) == errSecItemNotFound {
            var add = baseQuery()
            add[kSecValueData as String] = data
            SecItemAdd(add as CFDictionary, nil)
        }
    }

    public func clear() {
        SecItemDelete(baseQuery() as CFDictionary)
    }

    private func baseQuery() -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: account]
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
