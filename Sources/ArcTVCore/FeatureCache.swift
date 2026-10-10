import Foundation

/// Remembers each title's genres / directors / cast so a refresh rarely touches the network. Kept in a file so it survives launches.
public actor FeatureCache {
    private struct Entry: Codable {
        var features: Features
        var at: Date
    }

    private var store: [String: Entry] = [:]
    private let file: URL?
    private var loaded = false

    /// `file` nil keeps it in memory only (tests).
    public init(file: URL?) { self.file = file }

    public static func standard() -> FeatureCache {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
        return FeatureCache(file: base?.appendingPathComponent("ArcTV", isDirectory: true).appendingPathComponent("features.json"))
    }

    public func get(_ id: String, now: Date = Date()) -> Features? {
        loadIfNeeded()
        guard let entry = store[id], now.timeIntervalSince(entry.at) <= RecommendConfig.featureCacheTTL else { return nil }
        return entry.features
    }

    public func put(_ features: [String: Features], now: Date = Date()) {
        loadIfNeeded()
        for (id, value) in features { store[id] = Entry(features: value, at: now) }
        if store.count > RecommendConfig.featureCacheMaxEntries {
            let oldest = store.sorted { $0.value.at < $1.value.at }.prefix(store.count - RecommendConfig.featureCacheMaxEntries)
            for (key, _) in oldest { store.removeValue(forKey: key) }
        }
        save()
    }

    public func clear() {
        store = [:]
        save()
    }

    private func loadIfNeeded() {
        if loaded { return }
        loaded = true
        guard let file, let data = try? Data(contentsOf: file), let decoded = try? JSONDecoder().decode([String: Entry].self, from: data) else { return }
        store = decoded
    }

    private func save() {
        guard let file else { return }
        try? FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        if let data = try? JSONEncoder().encode(store) { try? data.write(to: file, options: .atomic) }
    }
}

public enum FeatureLoading {
    /// A loader that reads the cache first and looks up at most `limit` unknown titles through `fetch`, a few at a time. A failed lookup is just
    /// left out; it never throws.
    public static func loader(cache: FeatureCache, concurrency: Int = RecommendConfig.detailFetchConcurrency,
                              fetch: @escaping @Sendable (TitleRef) async -> Features?) -> FeatureLoader {
        return { refs, limit in
            var out: [String: Features] = [:]
            var missing: [TitleRef] = []
            var seen = Set<String>()
            for ref in refs where seen.insert(ref.id).inserted {
                if let cached = await cache.get(ref.id) { out[ref.id] = cached } else { missing.append(ref) }
            }
            let toFetch = Array(missing.prefix(limit))
            var fetched: [String: Features] = [:]
            await withTaskGroup(of: (String, Features?).self) { group in
                var next = 0
                while next < min(max(1, concurrency), toFetch.count) {
                    let ref = toFetch[next]
                    next += 1
                    group.addTask { (ref.id, await fetch(ref)) }
                }
                while let (id, features) = await group.next() {
                    if let features, features.hasAny { fetched[id] = features }
                    if next < toFetch.count {
                        let ref = toFetch[next]
                        next += 1
                        group.addTask { (ref.id, await fetch(ref)) }
                    }
                }
            }
            if !fetched.isEmpty { await cache.put(fetched) }
            return out.merging(fetched) { first, _ in first }
        }
    }
}
