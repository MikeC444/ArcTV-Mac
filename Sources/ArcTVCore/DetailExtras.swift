import Foundation

public extension String {
    /// Text with the HTML entities some addons leave in names and descriptions turned back into characters (&apos; &amp; &#39; ...).
    var htmlDecoded: String {
        guard contains("&") else { return self }
        var text = self
        let named = ["&apos;": "'", "&quot;": "\"", "&lt;": "<", "&gt;": ">", "&nbsp;": " "]
        for (entity, character) in named { text = text.replacingOccurrences(of: entity, with: character) }
        if let regex = try? NSRegularExpression(pattern: "&#(x?)([0-9a-fA-F]+);") {
            let nsText = text as NSString
            var out = ""
            var last = 0
            for match in regex.matches(in: text, range: NSRange(location: 0, length: nsText.length)) {
                out += nsText.substring(with: NSRange(location: last, length: match.range.location - last))
                let isHex = nsText.substring(with: match.range(at: 1)) == "x"
                let digits = nsText.substring(with: match.range(at: 2))
                if let value = UInt32(digits, radix: isHex ? 16 : 10), let scalar = Unicode.Scalar(value) { out += String(Character(scalar)) } else { out += nsText.substring(with: match.range) }
                last = match.range.location + match.range.length
            }
            text = out + nsText.substring(from: last)
        }
        return text.replacingOccurrences(of: "&" + "amp;", with: "&")
    }
}

/// Times and dates the way the web app writes them.
public enum Format {
    /// "2h 17m" ("49m" under an hour: the web app writes "0h 49m", which reads like a mistake).
    public static func runtime(minutes: Int) -> String { minutes < 60 ? "\(minutes)m" : "\(minutes / 60)h \(minutes % 60)m" }

    /// "142 min" -> 142, "2h 22min" -> 142.
    public static func runtimeMinutes(_ text: String?) -> Int? {
        guard let text, !text.isEmpty else { return nil }
        if let match = text.range(of: #"(\d+)\s*h(?:\D*?(\d+)\s*m)?"#, options: [.regularExpression, .caseInsensitive]) {
            let found = String(text[match])
            let numbers = found.split(whereSeparator: { !$0.isNumber }).compactMap { Int($0) }
            if let hours = numbers.first { return hours * 60 + (numbers.count > 1 ? numbers[1] : 0) }
        }
        let digits = text.filter(\.isNumber)
        return Int(digits)
    }

    /// "yyyy-MM-dd" -> "Mar 5, 2024"
    public static func releaseDate(_ iso: String) -> String? {
        guard iso.count >= 10 else { return nil }
        let parser = DateFormatter()
        parser.locale = Locale(identifier: "en_US_POSIX")
        parser.timeZone = TimeZone(identifier: "UTC")
        parser.dateFormat = "yyyy-MM-dd"
        guard let date = parser.date(from: String(iso.prefix(10))) else { return nil }
        let out = DateFormatter()
        out.locale = Locale(identifier: "en_US")
        out.timeZone = TimeZone(identifier: "UTC")
        out.dateFormat = "MMM d, yyyy"
        return out.string(from: date)
    }
}

/// What the account's cast lookup answers (`GET /user/cast`): TMDB's cast, with a photo address and the character where it has them.
public struct TmdbCast: Decodable, Equatable, Sendable {
    public var name: String
    public var character: String?
    public var photo: String?

    public init(name: String, character: String? = nil, photo: String? = nil) {
        self.name = name
        self.character = character
        self.photo = photo
    }
}

private struct TmdbCastResponse: Decodable {
    var cast: [TmdbCast]
}

private struct ReleaseDateResponse: Decodable {
    var releaseDate: String?
}

public enum CastMerge {
    private static func key(_ name: String) -> String {
        let folded = name.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: nil)
        return folded.split(whereSeparator: { !$0.isLetter && !$0.isNumber }).joined(separator: " ")
    }

    /// Fills in photos (and characters) the addon didn't send, matching people by name. Whatever the addon did send is kept as it is. If the addon
    /// sent no cast at all, TMDB's list is used.
    public static func merge(_ addon: [CastMember], _ tmdb: [TmdbCast]) -> [CastMember] {
        if tmdb.isEmpty { return addon }
        if addon.isEmpty { return tmdb.map { CastMember(name: $0.name, role: $0.character, photoURL: $0.photo) } }
        var byName: [String: TmdbCast] = [:]
        for entry in tmdb where byName[key(entry.name)] == nil { byName[key(entry.name)] = entry }
        return addon.map { member in
            if member.photoURL != nil, member.role != nil { return member }
            guard let match = byName[key(member.name)] else { return member }
            return CastMember(name: member.name, role: member.role ?? match.character, photoURL: member.photoURL ?? match.photo)
        }
    }
}

extension AuthClient {
    /// A movie's release date ("2024-03-05"), nil when the lookup has none.
    public func releaseDate(accessToken: String, title: String, year: Int?) async throws -> String? {
        var query = ["title": title]
        if let year { query["year"] = String(year) }
        let data = try await sendJSON("GET", "/user/release-date", query: query, body: nil, accessToken: accessToken)
        guard let decoded = try? JSONDecoder().decode(ReleaseDateResponse.self, from: data) else { throw APIError.unreadable }
        return decoded.releaseDate
    }

    /// The cast with photos, from the account's server (which holds the movie database key). `type` is "movie" or "series".
    public func castPhotos(accessToken: String, imdbID: String, type: String) async throws -> [TmdbCast] {
        let data = try await sendJSON("GET", "/user/cast", query: ["imdbId": imdbID, "type": type == "movie" ? "MOVIE" : "TV_SHOW"], body: nil, accessToken: accessToken)
        guard let decoded = try? JSONDecoder().decode(TmdbCastResponse.self, from: data) else { throw APIError.unreadable }
        return decoded.cast
    }
}
