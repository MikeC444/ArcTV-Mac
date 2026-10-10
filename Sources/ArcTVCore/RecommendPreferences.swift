import Foundation

/// A title of the profile's that pushed a feature, for honest explanations.
public struct Contribution: Equatable, Sendable {
    public var id: String
    public var title: String
    public var kind: SignalKind
    public var amount: Double
}

public struct TastePreferences: Sendable {
    public var genre: [String: Double] = [:]
    public var director: [String: Double] = [:]
    public var cast: [String: Double] = [:]
    /// Which titles pushed each feature ("genre|drama" -> [...]).
    public var contributions: [String: [Contribution]] = [:]

    public init() {}

    func vector(_ category: TasteCategory) -> [String: Double] {
        switch category {
        case .genre: return genre
        case .director: return director
        case .cast: return cast
        }
    }

    /// True when the profile has any nonzero preference in this category.
    func has(_ category: TasteCategory) -> Bool { vector(category).values.contains { $0 != 0 } }

    mutating func add(_ category: TasteCategory, feature: String, amount: Double, from interaction: Interaction) {
        switch category {
        case .genre: genre[feature, default: 0] += amount
        case .director: director[feature, default: 0] += amount
        case .cast: cast[feature, default: 0] += amount
        }
        contributions[contributionKey(category, feature), default: []]
            .append(Contribution(id: interaction.id, title: interaction.title, kind: interaction.kind, amount: amount))
    }
}

func contributionKey(_ category: TasteCategory, _ feature: String) -> String { "\(category.key)|\(feature)" }

/// One preference map per category. A title's signal weight is split equally among its unique features within each category, so a film with a
/// long cast list doesn't count for more than one with a short one. Titles without metadata for a category add nothing there.
public func buildPreferences(_ interactions: [Interaction], featuresByID: [String: Features]) -> TastePreferences {
    var prefs = TastePreferences()
    for interaction in interactions {
        guard let features = featuresByID[interaction.id] else { continue }
        for category in TasteCategory.allCases {
            let list = features.list(category)
            if list.isEmpty { continue }
            let share = interaction.weight / Double(list.count)
            for feature in list { prefs.add(category, feature: feature, amount: share, from: interaction) }
        }
    }
    return prefs
}
