import Foundation

/// The plans Arc TV Plus is sold as. The real prices live in Stripe and show on its checkout page; the cards only name the plan.
public struct PlusPlan: Identifiable, Equatable, Sendable {
    public var id: String
    public var label: String
    public var per: String
    public var blurb: String
    public var note: String?

    public static let all = [
        PlusPlan(id: "monthly", label: "Monthly", per: "per month", blurb: "Cancel any time.", note: nil),
        PlusPlan(id: "yearly", label: "Yearly", per: "per year", blurb: "Cancel any time.", note: "Best value"),
        PlusPlan(id: "lifetime", label: "Lifetime", per: "one-time payment", blurb: "Pay once, keep Plus forever. No renewals.", note: "Pay once")
    ]

    public static func label(for id: String?) -> String? { all.first { $0.id == id }?.label }
}

public enum PlusCopy {
    public static let freeNote = "Everything you use today stays free: browsing, playing, My List, Continue Watching, addons and Blocked Genres."
    public static let proceedsNote = "Every subscription goes straight back into building and running Arc TV: new features, faster servers and keeping the free app free."

    public struct Perk: Identifiable, Equatable, Sendable {
        public var title: String
        public var detail: String
        /// "Coming soon" instead of "Included".
        public var soon: Bool
        /// A small tag, such as "Web and Mac only", for a perk the phone and Fire TV apps don't have.
        public var tag: String? = nil
        public var id: String { title }
    }

    public static let perks = [
        Perk(title: "Picked for you", detail: "A Home row chosen from the movies and shows you like, finish and save, with the reason under each poster, plus Like and Not for me on movies and shows.", soon: false),
        Perk(title: "Profiles", detail: "Up to 5 profiles on one account, each with its own My List, Continue Watching, settings and recommendations. Add kids profiles, and lock any profile with a PIN.", soon: false),
        Perk(title: "Parental controls", detail: "Locks on individual genres and titles, built on kids profiles and Blocked Genres.", soon: true),
        Perk(title: "Smart source picking", detail: "Skips Select a Source and starts the best source your device can play, once every addon has answered. Turn it on in Plus settings.", soon: false),
        Perk(title: "Your stats", detail: "How much you watch, how this week compares, your streak, a map of your last 13 weeks and your busiest day, under Settings > Your stats.", soon: false),
        Perk(title: "Download", detail: "A Download button on a movie or episode lists the files from your debrid service, best quality at the smallest size first, to save to your Mac.", soon: false, tag: "Web and Mac only")
    ]
}

/// Where checkout sends the person: Stripe's own page.
public struct CheckoutLink: Decodable, Equatable, Sendable {
    public var url: String
    public var amountTotal: Int?
    public var currency: String?
    public var trialDays: Int?
}

private struct PlanBody: Encodable {
    var plan: String
}

extension AuthClient {
    /// Starts a checkout for "monthly", "yearly" or "lifetime". Throws 409 (already Plus for life) or 503 (checkout not available yet).
    public func startCheckout(accessToken: String, plan: String) async throws -> CheckoutLink {
        let data = try await sendJSON("POST", "/user/plus/checkout", body: try JSONEncoder().encode(PlanBody(plan: plan)), accessToken: accessToken)
        guard let link = try? JSONDecoder().decode(CheckoutLink.self, from: data) else { throw APIError.unreadable }
        return link
    }

    /// Cancels a monthly or yearly subscription at the end of the period already paid for (Plus stays on until then) and answers with the new status.
    public func cancelSubscription(accessToken: String) async throws -> PlusStatus {
        let data = try await sendJSON("POST", "/user/plus/cancel", body: Data("{}".utf8), accessToken: accessToken)
        guard let status = try? JSONDecoder().decode(PlusStatus.self, from: data) else { throw APIError.unreadable }
        return status
    }
}

/// The two Plus popups. The welcome shows once, ever (a revised tour gets a new id); the invitation comes back five days after it was closed,
/// and never after "Don't show me again".
public enum PlusPopups {
    public static let welcomeID = "2026-10-features-2"
    public static let snooze: TimeInterval = 5 * 24 * 3600

    public static func welcomeDue(seen: String?, shownThisLaunch: Bool) -> Bool { seen != welcomeID && !shownThisLaunch }

    public static func invitationDue(never: Bool, snoozedUntil: Date?, shownThisLaunch: Bool, now: Date = Date()) -> Bool {
        !never && !shownThisLaunch && now >= (snoozedUntil ?? .distantPast)
    }
}
