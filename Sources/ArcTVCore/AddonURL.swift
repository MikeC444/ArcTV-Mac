import Foundation

/// Normalizes the many shapes an addon URL is shared in ("stremio://" links, a bare host, a URL without manifest.json) into a manifest URL,
/// the same rules as the Android apps.
public enum AddonURL {
    public static func normalizeManifestURL(_ input: String) -> String {
        var url = input.trimmingCharacters(in: .whitespacesAndNewlines)
        if url.hasPrefix("stremio://") {
            url = "https://" + url.dropFirst("stremio://".count)
        }
        if !url.hasPrefix("http://") && !url.hasPrefix("https://") {
            url = "https://" + url
        }
        let last = url.split(separator: "/", omittingEmptySubsequences: false).last.map(String.init) ?? ""
        if last.lowercased() != "manifest.json" {
            while url.hasSuffix("/") { url.removeLast() }
            url += "/manifest.json"
        }
        return url
    }

    /// The addon's resource base: the manifest URL with `manifest.json` taken off.
    public static func resourceBase(_ manifestURL: String) -> String {
        var base = manifestURL
        if base.lowercased().hasSuffix("manifest.json") { base.removeLast("manifest.json".count) }
        while base.hasSuffix("/") { base.removeLast() }
        return base
    }

    /// One URL path segment, percent-encoded (spaces as %20, slashes encoded too).
    static func encode(_ segment: String) -> String {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        return segment.addingPercentEncoding(withAllowedCharacters: allowed) ?? segment
    }

    /// `<base>/catalog/<type>/<id>[/key=value&key=value].json`, as Stremio addons expect.
    public static func catalogURL(manifestURL: String, type: String, catalogId: String, extra: [String: String] = [:]) -> String {
        let base = resourceBase(manifestURL)
        var url = "\(base)/catalog/\(encode(type))/\(encode(catalogId))"
        if !extra.isEmpty {
            let pairs = extra.sorted { $0.key < $1.key }.map { "\(encode($0.key))=\(encode($0.value))" }
            url += "/" + pairs.joined(separator: "&")
        }
        return url + ".json"
    }
}
