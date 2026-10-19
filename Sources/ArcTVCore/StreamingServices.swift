import Foundation

/// A streaming service (Netflix, Disney+ and so on) Home can offer as a tile. The same list, order, words and rules as the web app
/// (`domain/streamingServices.ts`) and the Fire TV app: a tile only exists while an installed addon has a catalogue for the service, found by the
/// catalogue's own name or id.
public struct StreamingService: Equatable, Identifiable, Sendable {
    public let id: String
    public let name: String
    /// Words (the id or name split on anything that is not a letter or number, lower case) that mean this service. Includes the short ids some addons use.
    public let words: [String]
    /// Switched off until the person turns it on (a service that is not listed first is more likely clutter than wanted).
    public let off: Bool

    public init(id: String, name: String, words: [String], off: Bool = false) {
        self.id = id
        self.name = name
        self.words = words
        self.off = off
    }
}

public enum StreamingServices {
    /// In the order the tiles appear until the person puts them in their own: the best known first, Shudder further back, then the rest. `off` marks
    /// a service that is switched off until the person turns it on (see `isVisible`), so a Home with many services stays tidy.
    public static let all: [StreamingService] = [
        StreamingService(id: "netflix", name: "Netflix", words: ["netflix", "nfx"]),
        StreamingService(id: "prime", name: "Prime Video", words: ["prime", "primevideo", "amazon", "amp"]),
        StreamingService(id: "apple", name: "Apple TV+", words: ["apple", "appletv", "atp"]),
        StreamingService(id: "max", name: "HBO Max", words: ["hbo", "hbomax", "hbm", "max"]),
        StreamingService(id: "disney", name: "Disney+", words: ["disney", "disneyplus", "dnp"]),
        StreamingService(id: "paramount", name: "Paramount+", words: ["paramount", "paramountplus", "pmp"]),
        StreamingService(id: "hulu", name: "Hulu", words: ["hulu", "hlu"]),
        StreamingService(id: "peacock", name: "Peacock", words: ["peacock", "pcp"]),
        StreamingService(id: "iplayer", name: "BBC iPlayer", words: ["iplayer", "bbciplayer"]),
        StreamingService(id: "shudder", name: "Shudder", words: ["shudder", "shd"]),
        StreamingService(id: "crunchyroll", name: "Crunchyroll", words: ["crunchyroll", "cru"], off: true),
        StreamingService(id: "skyshowtime", name: "SkyShowtime", words: ["skyshowtime", "sst"], off: true),
        StreamingService(id: "britbox", name: "BritBox", words: ["britbox", "bbo"], off: true),
        StreamingService(id: "itvx", name: "ITVX", words: ["itvx", "itv"], off: true),
        StreamingService(id: "channel4", name: "Channel 4", words: ["channel4", "all4", "al4"], off: true),
        StreamingService(id: "discovery", name: "Discovery+", words: ["discovery", "discoveryplus", "dpe"], off: true),
        StreamingService(id: "sky", name: "Sky", words: ["sky", "sgo"], off: true),
        StreamingService(id: "acorn", name: "Acorn TV", words: ["acorn", "acorntv", "act"], off: true),
        StreamingService(id: "canal", name: "Canal+", words: ["canal", "canalplus", "cpd"], off: true),
        StreamingService(id: "claro", name: "Claro video", words: ["claro", "clarovideo", "clv"], off: true),
        StreamingService(id: "criterion", name: "Criterion Channel", words: ["criterion", "crc"], off: true),
        StreamingService(id: "curiosity", name: "Curiosity Stream", words: ["curiosity", "curiositystream", "cts"], off: true),
        StreamingService(id: "globoplay", name: "Globoplay", words: ["globoplay", "gop"], off: true),
        StreamingService(id: "hayu", name: "Hayu", words: ["hayu", "hay"], off: true),
        StreamingService(id: "iqiyi", name: "iQIYI", words: ["iqiyi", "iqi"], off: true),
        StreamingService(id: "jiohotstar", name: "JioHotstar", words: ["jiohotstar", "hotstar", "jhs"], off: true),
        StreamingService(id: "magellan", name: "MagellanTV", words: ["magellantv", "magellan", "mgl"], off: true),
        StreamingService(id: "movistar", name: "Movistar+", words: ["movistar", "mp9"], off: true),
        StreamingService(id: "mubi", name: "MUBI", words: ["mubi", "mbi"], off: true),
        StreamingService(id: "netflixkids", name: "Netflix Kids", words: ["netflixkids", "nfk"], off: true),
        StreamingService(id: "nlziet", name: "NLZIET", words: ["nlziet", "nlz"], off: true),
        StreamingService(id: "sonyliv", name: "Sony LIV", words: ["sonyliv"], off: true),
        StreamingService(id: "starz", name: "Starz", words: ["starz", "stz"], off: true),
        StreamingService(id: "videoland", name: "Videoland", words: ["videoland", "vil"], off: true),
        StreamingService(id: "viki", name: "Viki", words: ["viki", "vik"], off: true),
        StreamingService(id: "zee5", name: "ZEE5", words: ["zee5", "z5", "zee"], off: true)
    ]

    private static let byID: [String: StreamingService] = Dictionary(uniqueKeysWithValues: all.map { ($0.id, $0) })

    public static func service(_ id: String) -> StreamingService? { byID[id] }

    /// Words of seven letters or more also count when they sit inside the whole name run together ("Netflix Kids" is "netflixkids").
    static let longWord = 7

    /// An addon with catalogues for at least this many services is a streaming-catalogue addon (one is just a catalogue called "Netflix Originals").
    static let minServicesForServiceAddon = 3

    /// Lower-case letters and digits, split on anything else.
    static func tokens(_ text: String?) -> [String] {
        (text ?? "").lowercased().split { !(("a"..."z").contains($0) || ("0"..."9").contains($0)) }.map(String.init)
    }

    /// Which service a catalogue is for (by its name first, then its id), or nil when it is not one of them. When more than one service fits
    /// ("Netflix Kids" is both Netflix Kids and Netflix) the longest matching word wins.
    public static func serviceOfCatalog(name: String?, id: String) -> String? {
        for source in [name, id] {
            let found = tokens(source)
            if found.isEmpty { continue }
            let compact = found.joined()
            var best: (id: String, length: Int)?
            for service in all {
                for word in service.words {
                    let hit = found.contains(word) || (word.count >= longWord && compact.contains(word))
                    if hit, best == nil || word.count > best!.length { best = (service.id, word.count) }
                }
            }
            if let best { return best.id }
        }
        return nil
    }

    /// The catalogues of an addon that is made of streaming-service catalogues (at least three services), each with its service, or none for an
    /// ordinary addon. Only catalogues that need nothing from the caller count, as on the web.
    public static func serviceCatalogs(in catalogs: [CatalogDefinition]) -> [(catalog: CatalogDefinition, service: String)] {
        let matched = catalogs
            .filter { catalog in !(catalog.extra ?? []).contains { $0.isRequired == true } }
            .compactMap { catalog in serviceOfCatalog(name: catalog.name, id: catalog.id).map { (catalog: catalog, service: $0) } }
        return Set(matched.map(\.service)).count >= minServicesForServiceAddon ? matched : []
    }

    /// Service ids in tile order, each once. Ids that are not known are dropped.
    public static func ordered(_ ids: Set<String>) -> [String] {
        all.filter { ids.contains($0.id) }.map(\.id)
    }

    /// The id Home Rows keeps in its hidden list for a service's tile (the same list that hides ordinary rows, so it is saved and synced with them).
    public static func rowID(_ service: String) -> String { "streaming:\(service)" }

    /// The marker Home Rows keeps in the same hidden list when the person has turned a switched-off-by-default service on.
    public static func onID(_ service: String) -> String { "streaming-on:\(service)" }

    /// Is this service shown as a tile? Not when the person hid it; a service that is off by default only when they have turned it on.
    public static func isVisible(_ service: String, hidden: Set<String>) -> Bool {
        if hidden.contains(rowID(service)) { return false }
        return byID[service]?.off == true ? hidden.contains(onID(service)) : true
    }

    /// The hidden list after the person turns a service on or off in Home Rows.
    public static func withVisible(_ hidden: [String], service: String, visible: Bool) -> [String] {
        let rest = hidden.filter { $0 != rowID(service) && $0 != onID(service) }
        if !visible { return rest + [rowID(service)] }
        return byID[service]?.off == true ? rest + [onID(service)] : rest
    }

    /// Which of these services are shown as tiles.
    public static func visible(_ services: [String], hidden: Set<String>) -> [String] {
        services.filter { isVisible($0, hidden: hidden) }
    }

    /// Is this entry in the Home Rows order a streaming service's (rather than an ordinary row's)?
    public static func isServiceRowID(_ id: String) -> Bool { id.hasPrefix("streaming:") }

    /// Services in the person's own order: the ones they have placed (in the Home Rows order list, as `streaming:<id>`) in that order, then any not
    /// placed yet in the default tile order. So a service an addon brings later joins at the end instead of jumping to the front.
    public static func inUserOrder(_ services: [String], order: [String]) -> [String] {
        var placed: [String] = []
        for entry in order where isServiceRowID(entry) {
            let id = String(entry.dropFirst("streaming:".count))
            if services.contains(id), !placed.contains(id) { placed.append(id) }
        }
        return placed + services.filter { !placed.contains($0) }
    }
}

public extension HomeSource {
    /// The streaming-service catalogues in this addon's manifest (movies and series), each with its service; empty for an ordinary addon.
    var serviceCatalogEntries: [(catalog: CatalogDefinition, service: String)] {
        StreamingServices.serviceCatalogs(in: (manifest.catalogs ?? []).filter { $0.type == "movie" || $0.type == "series" })
    }

    /// The services this addon has catalogues for, in the default tile order.
    var streamingServiceIDs: [String] {
        StreamingServices.ordered(Set(serviceCatalogEntries.map(\.service)))
    }

    /// One service's titles (movies and series together) from this addon: every catalogue it has for the service, taking turns.
    func serviceItems(_ service: String, client: AddonClient = AddonClient()) async -> [MetaPreview] {
        await fetchServiceCatalogs(serviceCatalogEntries.filter { $0.service == service }.map(\.catalog), skip: 0, client: client)
    }

    /// The following page (page 1 is the first after `serviceItems`). Only a catalogue that declares "skip" has more pages (the Streaming Catalogs
    /// addon's take no extras at all: its one page is all there is).
    func moreServiceItems(_ service: String, page: Int, client: AddonClient = AddonClient()) async -> [MetaPreview] {
        let paged = serviceCatalogEntries.filter { $0.service == service && $0.catalog.supportsSkip }.map(\.catalog)
        return await fetchServiceCatalogs(paged, skip: page * HomeSections.pageSize, client: client)
    }

    private func fetchServiceCatalogs(_ wanted: [CatalogDefinition], skip: Int, client: AddonClient) async -> [MetaPreview] {
        if wanted.isEmpty { return [] }
        var extra: [String: String] = [:]
        if skip > 0 { extra["skip"] = String(skip) }
        let request = extra
        let manifestURL = self.manifestURL
        let lists = await withTaskGroup(of: (Int, [MetaPreview]).self) { group -> [[MetaPreview]] in
            for (index, catalog) in wanted.enumerated() {
                group.addTask { (index, (try? await client.fetchCatalog(manifestURL: manifestURL, type: catalog.type, catalogId: catalog.id, extra: request)) ?? []) }
            }
            var results = Array(repeating: [MetaPreview](), count: wanted.count)
            for await (index, items) in group { results[index] = items }
            return results
        }
        return distinctByID(HomeSections.interleaved(lists))
    }
}
