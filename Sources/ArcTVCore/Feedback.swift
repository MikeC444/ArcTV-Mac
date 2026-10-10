import Foundation

/// One title's Like / Not for me (`GET /user/feedback`).
public struct FeedbackItem: Codable, Equatable, Identifiable, Sendable {
    public var profileId: String
    public var providerId: String
    public var contentId: String
    public var contentType: String
    public var title: String
    public var feedback: String
    public var updatedAt: String
    public var deletedAt: String?

    public var id: String { contentId }
    public var rating: Rating? { Rating(rawValue: feedback) }

    public init(profileId: String = "main", providerId: String, contentId: String, contentType: String, title: String, feedback: String,
                updatedAt: String, deletedAt: String? = nil) {
        self.profileId = profileId
        self.providerId = providerId
        self.contentId = contentId
        self.contentType = contentType
        self.title = title
        self.feedback = feedback
        self.updatedAt = updatedAt
        self.deletedAt = deletedAt
    }

    /// A rating for this title, stamped now.
    public init(title: MetaPreview, rating: Rating) {
        self.init(providerId: AppInfo.cinemetaProviderId, contentId: title.id, contentType: title.type == "movie" ? "MOVIE" : "TV_SHOW",
                  title: title.name, feedback: rating.rawValue, updatedAt: ISODate.now())
    }
}

struct FeedbackResponse: Decodable {
    var items: [FeedbackItem]
}

/// What the account says about Arc TV Plus (`GET /user/plus`). While the paywall is off (early access) everyone is active.
public struct PlusStatus: Decodable, Equatable, Sendable {
    public var active: Bool
    public var plan: String?
    public var validUntil: String?
    public var paywall: Bool
    public var cancelAtPeriodEnd: Bool
    public var trialDays: Int

    public static let none = PlusStatus(active: false, plan: nil, validUntil: nil, paywall: false, cancelAtPeriodEnd: false, trialDays: 0)

    public init(active: Bool, plan: String?, validUntil: String?, paywall: Bool, cancelAtPeriodEnd: Bool, trialDays: Int) {
        self.active = active
        self.plan = plan
        self.validUntil = validUntil
        self.paywall = paywall
        self.cancelAtPeriodEnd = cancelAtPeriodEnd
        self.trialDays = trialDays
    }

    private enum Keys: String, CodingKey { case active, plan, validUntil, paywall, cancelAtPeriodEnd, trialDays }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: Keys.self)
        active = try c.decodeIfPresent(Bool.self, forKey: .active) ?? false
        plan = try c.decodeIfPresent(String.self, forKey: .plan)
        validUntil = try c.decodeIfPresent(String.self, forKey: .validUntil)
        paywall = try c.decodeIfPresent(Bool.self, forKey: .paywall) ?? false
        cancelAtPeriodEnd = try c.decodeIfPresent(Bool.self, forKey: .cancelAtPeriodEnd) ?? false
        trialDays = try c.decodeIfPresent(Int.self, forKey: .trialDays) ?? 0
    }
}

/// A title taken out of "Picked for you" (`GET /user/picked-dismissals`).
public struct PickedDismissal: Codable, Equatable, Sendable {
    public var profileId: String
    public var contentId: String
    public var dismissedAt: String
}

struct PickedDismissalsResponse: Decodable {
    var items: [PickedDismissal]
}

private struct FeedbackBody: Encodable {
    var profileId: String
    var providerId: String
    var contentId: String
    var contentType: String
    var title: String
    var feedback: String
    var updatedAt: String
}

private struct DismissalBody: Encodable {
    var profileId: String
    var contentId: String
    var dismissedAt: String
}

extension AuthClient {
    public func plusStatus(accessToken: String) async throws -> PlusStatus {
        let data = try await sendJSON("GET", "/user/plus", body: nil, accessToken: accessToken)
        guard let decoded = try? JSONDecoder().decode(PlusStatus.self, from: data) else { throw APIError.unreadable }
        return decoded
    }

    public func feedback(accessToken: String) async throws -> [FeedbackItem] {
        let data = try await sendJSON("GET", "/user/feedback", query: ["profileId": "main"], body: nil, accessToken: accessToken)
        guard let decoded = try? JSONDecoder().decode(FeedbackResponse.self, from: data) else { throw APIError.unreadable }
        return decoded.items
    }

    public func setFeedback(accessToken: String, item: FeedbackItem) async throws {
        let body = FeedbackBody(profileId: item.profileId, providerId: item.providerId, contentId: item.contentId, contentType: item.contentType,
                                title: item.title, feedback: item.feedback, updatedAt: item.updatedAt)
        _ = try await sendJSON("POST", "/user/feedback", body: try JSONEncoder().encode(body), accessToken: accessToken)
    }

    public func clearFeedback(accessToken: String, item: FeedbackItem) async throws {
        _ = try await sendJSON(
            "DELETE", "/user/feedback",
            query: ["profileId": item.profileId, "providerId": item.providerId, "contentId": item.contentId, "contentType": item.contentType, "updatedAt": ISODate.now()],
            body: nil, accessToken: accessToken
        )
    }

    public func pickedDismissals(accessToken: String) async throws -> [PickedDismissal] {
        let data = try await sendJSON("GET", "/user/picked-dismissals", query: ["profileId": "main"], body: nil, accessToken: accessToken)
        guard let decoded = try? JSONDecoder().decode(PickedDismissalsResponse.self, from: data) else { throw APIError.unreadable }
        return decoded.items
    }

    public func dismissPicked(accessToken: String, contentID: String, at date: Date) async throws {
        let body = DismissalBody(profileId: "main", contentId: contentID, dismissedAt: ISODate.string(from: date))
        _ = try await sendJSON("POST", "/user/picked-dismissals", body: try JSONEncoder().encode(body), accessToken: accessToken)
    }
}
