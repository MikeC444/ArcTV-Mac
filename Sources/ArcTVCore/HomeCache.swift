import Foundation

/// The last Home rows, kept in a file so the next launch has something to show at once while the fresh rows load.
public struct HomeCache {
    public static let maxAge: TimeInterval = 7 * 24 * 3600
    public static let itemsPerRow = 30

    private struct Payload: Codable {
        var at: Date
        var sections: [HomeSectionRecord]
    }

    private struct HomeSectionRecord: Codable {
        var id: String
        var title: String
        var items: [MetaPreview]
    }

    let directory: URL

    public init(directory: URL? = nil) {
        self.directory = directory ?? (FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first ?? URL(fileURLWithPath: NSTemporaryDirectory()))
            .appendingPathComponent("ArcTV", isDirectory: true)
    }

    private func file(for userID: String) -> URL {
        let safe = String(userID.map { $0.isLetter || $0.isNumber || $0 == "-" ? $0 : "_" })
        return directory.appendingPathComponent("home-\(safe).json")
    }

    public func load(userID: String, now: Date = Date()) -> [HomeSection]? {
        guard let data = try? Data(contentsOf: file(for: userID)), let payload = try? JSONDecoder().decode(Payload.self, from: data),
              now.timeIntervalSince(payload.at) < Self.maxAge, !payload.sections.isEmpty else { return nil }
        return payload.sections.map { HomeSection(id: $0.id, title: $0.title, items: $0.items) }
    }

    public func save(_ sections: [HomeSection], userID: String, now: Date = Date()) {
        let records = sections.map { HomeSectionRecord(id: $0.id, title: $0.title, items: Array($0.items.prefix(Self.itemsPerRow))) }
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        if let data = try? JSONEncoder().encode(Payload(at: now, sections: records)) { try? data.write(to: file(for: userID), options: .atomic) }
    }
}
