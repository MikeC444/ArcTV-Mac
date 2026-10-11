import Foundation

/// A subtitle file an addon offers for the video being played (the Stremio protocol's `/subtitles/{type}/{id}.json`).
public struct AddonSubtitle: Equatable, Identifiable, Sendable {
    public var addonName: String
    /// The language as the addon wrote it ("eng").
    public var languageCode: String
    /// The language as a person reads it ("English").
    public var languageName: String
    public var url: String
    public var id: String { url }

    public init(addonName: String, languageCode: String, languageName: String, url: String) {
        self.addonName = addonName
        self.languageCode = languageCode
        self.languageName = languageName
        self.url = url
    }

    /// How the Subtitles menu names it: "English · Addon name".
    public var menuTitle: String { "\(languageName) · \(addonName)" }
}

struct SubtitlesResponse: Decodable {
    var subtitles: [RawSubtitle]?
}

struct RawSubtitle: Decodable, Equatable {
    var id: String?
    var url: String?
    // ISO 639-2 ("eng") in the protocol, though addons also send ISO 639-1 ("en") or a name.
    var lang: String?

    init(id: String? = nil, url: String? = nil, lang: String? = nil) {
        self.id = id
        self.url = url
        self.lang = lang
    }

    // Never throws: one odd entry must not make the whole answer unreadable.
    private enum CodingKeys: String, CodingKey { case id, url, lang }
    init(from decoder: Decoder) throws {
        let keyed = try? decoder.container(keyedBy: CodingKeys.self)
        id = (try? keyed?.decodeIfPresent(String.self, forKey: .id)) ?? nil
        url = (try? keyed?.decodeIfPresent(String.self, forKey: .url)) ?? nil
        lang = (try? keyed?.decodeIfPresent(String.self, forKey: .lang)) ?? nil
    }
}

extension AddonManifest {
    /// Whether this addon offers subtitles for a title of [type] ("movie" or "series") with this [id]. Unlike streams, an addon that doesn't
    /// list "subtitles" among its resources isn't asked, so catalogue addons never get a request they can't answer. A resource's own types and
    /// id prefixes ("tt" for IMDb ids) apply, else the manifest's; none listed means anything.
    public func offersSubtitles(type: String, id titleId: String) -> Bool {
        for resource in resources ?? [] where resource.name == "subtitles" {
            let allowedTypes = (resource.types?.isEmpty ?? true) ? types : resource.types
            let prefixes = (resource.idPrefixes?.isEmpty ?? true) ? idPrefixes : resource.idPrefixes
            if let allowedTypes, !allowedTypes.isEmpty, !allowedTypes.contains(type) { continue }
            if let prefixes, !prefixes.isEmpty, !prefixes.contains(where: { titleId.hasPrefix($0) }) { continue }
            return true
        }
        return false
    }
}

public enum SubtitleLanguage {
    /// ISO 639-2 codes ("eng", "fre") to the two-letter codes a language preference ("en") uses.
    private static let iso3to1: [String: String] = {
        let pairs = """
        eng en,spa es,fra fr,fre fr,deu de,ger de,ita it,por pt,nld nl,dut nl,swe sv,pol pl,tur tr,ara ar,hin hi,jpn ja,kor ko,zho zh,chi zh,rus ru,\
        ukr uk,ces cs,cze cs,slk sk,slo sk,hun hu,ron ro,rum ro,bul bg,ell el,gre el,heb he,fas fa,per fa,tha th,vie vi,ind id,msa ms,may ms,fin fi,\
        dan da,nor no,nob nb,isl is,ice is,hrv hr,srp sr,bos bs,scc sr,scr hr,slv sl,lit lt,lav lv,est et,cat ca,eus eu,baq eu,glg gl,ben bn,tam ta,tel te,urd ur,fil tl,sqi sq,alb sq,mkd mk,mac mk,hye hy,arm hy,kat ka,geo ka
        """
        var map: [String: String] = [:]
        for pair in pairs.split(separator: ",") {
            let parts = pair.split(separator: " ")
            if parts.count == 2 { map[String(parts[0])] = String(parts[1]) }
        }
        return map
    }()

    private static func englishName(_ key: String) -> String? {
        let name = Locale(identifier: "en").localizedString(forLanguageCode: key)
        guard let name, !name.isEmpty, name.lowercased() != key.lowercased() else { return nil }
        return name
    }

    /// The two-letter code for whatever an addon sent: "eng", "en", "en-US", "pt-BR", "English" all give a code a language preference ("en")
    /// can be compared with; nil when it can't be told.
    public static func key(_ raw: String?) -> String? {
        let text = (raw ?? "").trimmingCharacters(in: .whitespaces).lowercased()
        if text.isEmpty { return nil }
        let base = text.split(whereSeparator: { $0 == "-" || $0 == "_" }).first.map(String.init) ?? text
        if base.count == 2 { return base }
        if let two = iso3to1[base] { return two }
        // A written-out name ("english").
        return Set(iso3to1.values).first { englishName($0)?.lowercased() == text }
    }

    /// "English" for "eng"; the code in capitals when the language isn't known, so the list never shows a blank.
    public static func displayName(_ raw: String?) -> String {
        if let key = key(raw), let name = englishName(key) { return name }
        let text = (raw ?? "").trimmingCharacters(in: .whitespaces).uppercased()
        return text.isEmpty ? "Unknown" : text
    }
}

public enum AddonSubtitles {
    /// Turns one addon's answer into list entries: only files with a web address, one per address, each with a readable language.
    static func entries(from raw: [RawSubtitle], addonName: String) -> [AddonSubtitle] {
        var seen = Set<String>()
        var out: [AddonSubtitle] = []
        for item in raw {
            let url = (item.url ?? "").trimmingCharacters(in: .whitespaces)
            let lower = url.lowercased()
            guard lower.hasPrefix("https://") || lower.hasPrefix("http://"), seen.insert(url).inserted else { continue }
            let lang = (item.lang ?? "").trimmingCharacters(in: .whitespaces)
            out.append(AddonSubtitle(addonName: addonName, languageCode: lang, languageName: SubtitleLanguage.displayName(lang), url: url))
        }
        return out
    }

    /// Puts the person's preferred language first, then the rest by language name (keeping each addon's own order within one language), and
    /// keeps at most [perLanguage] files per language and [total] overall so the menu stays short.
    public static func rank(_ found: [AddonSubtitle], preferredLanguage: String?, perLanguage: Int = 5, total: Int = 60) -> [AddonSubtitle] {
        let preferred = SubtitleLanguage.key(preferredLanguage)
        var order: [String] = []
        var groups: [String: [AddonSubtitle]] = [:]
        for file in found {
            let key = SubtitleLanguage.key(file.languageCode) ?? file.languageName.lowercased()
            if groups[key] == nil { order.append(key) }
            groups[key, default: []].append(file)
        }
        let sorted = order.sorted { a, b in
            let rankA = a == preferred ? 0 : 1, rankB = b == preferred ? 0 : 1
            if rankA != rankB { return rankA < rankB }
            return groups[a]![0].languageName.localizedCompare(groups[b]![0].languageName) == .orderedAscending
        }
        return Array(sorted.flatMap { groups[$0]!.prefix(perLanguage) }.prefix(total))
    }
}

extension AddonClient {
    /// The subtitles an addon offers for a video: `/subtitles/{type}/{id}.json`, with the file name as an extra
    /// (`/subtitles/{type}/{id}/filename=....json`) when it is known, which addons use to match a release.
    public func fetchSubtitles(manifestURL: String, type: String, id: String, filename: String? = nil) async throws -> [AddonSubtitle] {
        let extra = filename.flatMap { $0.isEmpty ? nil : "/filename=\(AddonURL.encode($0))" } ?? ""
        let url = "\(AddonURL.resourceBase(manifestURL))/subtitles/\(AddonURL.encode(type))/\(AddonURL.encodeID(id))\(extra).json"
        let data = try await HTTP.get(url)
        guard let decoded = try? JSONDecoder().decode(SubtitlesResponse.self, from: data) else { throw APIError.unreadable }
        return AddonSubtitles.entries(from: decoded.subtitles ?? [], addonName: "")
    }
}

public enum SubtitleFinder {
    private static let addonTimeoutNanoseconds: UInt64 = 8_000_000_000

    /// Asks the enabled addons that offer subtitles which files they have for the video being played. Best-effort: an addon that is slow, down
    /// or answers badly just adds nothing, and this never throws, since a missing subtitle list must never get in the way of the video.
    public static func find(
        addons: [SyncedAddon], type: String, id: String, filename: String?, preferredLanguage: String?, client: AddonClient = AddonClient()
    ) async -> [AddonSubtitle] {
        let asked = addons.filter { $0.enabled && ($0.manifestJson?.offersSubtitles(type: type, id: id) ?? false) }
        if asked.isEmpty { return [] }
        let found = await withTaskGroup(of: (Int, [AddonSubtitle]).self) { group -> [AddonSubtitle] in
            for (order, addon) in asked.enumerated() {
                group.addTask {
                    // The answer races a timer; whichever finishes first counts.
                    let files = await withTaskGroup(of: [AddonSubtitle]?.self) { race -> [AddonSubtitle] in
                        race.addTask { try? await client.fetchSubtitles(manifestURL: addon.manifestUrl, type: type, id: id, filename: filename) }
                        race.addTask {
                            try? await Task.sleep(nanoseconds: addonTimeoutNanoseconds)
                            return nil
                        }
                        let first = await race.next() ?? nil
                        race.cancelAll()
                        return first ?? []
                    }
                    return (order, files.map { AddonSubtitle(addonName: addon.name, languageCode: $0.languageCode, languageName: $0.languageName, url: $0.url) })
                }
            }
            var all: [(Int, [AddonSubtitle])] = []
            for await answer in group { all.append(answer) }
            return all.sorted { $0.0 < $1.0 }.flatMap(\.1)
        }
        return AddonSubtitles.rank(found, preferredLanguage: preferredLanguage)
    }
}
