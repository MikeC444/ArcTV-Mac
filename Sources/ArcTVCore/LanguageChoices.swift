import Foundation

/// A language the person can pick for subtitles or audio. `code` is what the account stores (and what the player is told); nil means "decide for me".
public struct LanguageChoice: Equatable, Identifiable, Sendable {
    public var code: String?
    public var name: String
    public var id: String { code ?? "" }

    public init(code: String?, name: String) {
        self.code = code
        self.name = name
    }
}

public enum LanguageChoices {
    /// The same list the web app offers, in the same order: the system choice, then English, then every other language A to Z.
    public static func subtitles(systemName: String = "System Default") -> [LanguageChoice] {
        let english = all.filter { $0.code == "en" }
        let others = all.filter { $0.code != "en" }.sorted { $0.name.localizedCompare($1.name) == .orderedAscending }
        return [LanguageChoice(code: nil, name: systemName)] + english + others
    }

    public static func audio() -> [LanguageChoice] {
        [LanguageChoice(code: nil, name: "Automatic")] + all
    }

    public static let all: [LanguageChoice] = [
        LanguageChoice(code: "en", name: "English"),
        LanguageChoice(code: "es", name: "Spanish"),
        LanguageChoice(code: "fr", name: "French"),
        LanguageChoice(code: "de", name: "German"),
        LanguageChoice(code: "it", name: "Italian"),
        LanguageChoice(code: "pt", name: "Portuguese"),
        LanguageChoice(code: "nl", name: "Dutch"),
        LanguageChoice(code: "sv", name: "Swedish"),
        LanguageChoice(code: "pl", name: "Polish"),
        LanguageChoice(code: "tr", name: "Turkish"),
        LanguageChoice(code: "ar", name: "Arabic"),
        LanguageChoice(code: "hi", name: "Hindi"),
        LanguageChoice(code: "ja", name: "Japanese"),
        LanguageChoice(code: "ko", name: "Korean"),
        LanguageChoice(code: "zh", name: "Chinese")
    ]
}

/// Moving a row in Settings > Home Rows. A port of the web app's `moveRow`.
public enum HomeRowOrder {
    /// The full order after moving `id` one place up (`delta` -1) or down (+1); unchanged if it can't move.
    public static func move(_ order: [String], id: String, delta: Int) -> [String] {
        guard let index = order.firstIndex(of: id) else { return order }
        let target = index + delta
        guard order.indices.contains(target) else { return order }
        var next = order
        next.swapAt(index, target)
        return next
    }
}
