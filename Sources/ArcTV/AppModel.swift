import ArcTVCore
import Foundation
import SwiftUI

/// The places in the top bar, in the web app's order.
enum NavItem: String, CaseIterable, Identifiable {
    case home = "Home"
    case movies = "Movies"
    case tv = "TV Shows"
    case search = "Search"
    case myList = "My List"
    case settings = "Settings"

    var id: String { rawValue }
}

/// What is being played: the title, which episode if any, and the id addons are asked for streams with.
struct PlayTarget: Equatable, Identifiable {
    var title: MetaDetail
    var season: Int?
    var episode: Int?
    var episodeTitle: String?
    /// Where to start, in seconds (resuming); 0 starts from the beginning.
    var startAt: Double = 0

    var id: String { streamID }
    var streamID: String { ArcTVCore.streamID(titleID: title.id, season: season, episode: episode) }
    var heading: String { episodeTitle.map { "\(title.name) · \($0)" } ?? title.name }
}

/// A source the person picked: what to play and what to call it.
struct PlayingItem: Equatable {
    var url: URL
    var heading: String
    var sourceName: String
    var target: PlayTarget
}

/// Which player plays video: mpv (plays almost anything) or the Mac's built-in player.
enum PlayerEngine: String, CaseIterable, Identifiable {
    case mpv
    case builtIn

    var id: String { rawValue }
    var title: String { self == .mpv ? "Arc TV player (mpv)" : "Mac built-in player" }
    var detail: String {
        self == .mpv
            ? "Plays MKV, HEVC, HDR and Dolby Vision, with audio and subtitle choices. Recommended."
            : "Apple's own player. Only plays MP4 and streaming (HLS) files; many sources won't open."
    }
}

/// What the whole app knows: who is signed in, which server it talks to, and what Home shows.
@MainActor
final class AppModel: ObservableObject {
    enum HomeState: Equatable {
        case idle
        case loading
        case loaded([HomeRow])
        case empty
    }

    @Published var session: Session?
    @Published var selected: NavItem = .home
    @Published var playerEngine: PlayerEngine = PlayerEngine(rawValue: UserDefaults.standard.string(forKey: "ArcTVPlayerEngine") ?? "") ?? .mpv {
        didSet { UserDefaults.standard.set(playerEngine.rawValue, forKey: "ArcTVPlayerEngine") }
    }
    @Published var home: HomeState = .idle
    /// Which screen is open over the tabs: a title's details, then its sources, then the player (each sits on top of the one before).
    @Published var detail: MetaPreview?
    @Published var sourcesFor: PlayTarget?
    @Published var playing: PlayingItem?
    @Published var addons: [SyncedAddon] = []
    /// Every addon on the account, switched off ones included (for Settings > Addons); [addons] is just the enabled ones.
    @Published var allAddons: [SyncedAddon] = []
    @Published var settings: AccountSettings?
    @Published var myList: [WatchlistItem]?
    @Published var continueItems: [ContinueItem] = []
    @Published var myListError: String?
    @Published var signInError: String?
    @Published var signingIn = false

    /// The backend address: what the person typed on the sign-in screen last time, else the one baked into this build, else the default.
    @Published var serverURL: String {
        didSet { UserDefaults.standard.set(serverURL, forKey: Self.serverKey) }
    }

    private static let serverKey = "ArcTVServerURL"
    private let store = SessionStore()

    init() {
        serverURL = AppInfo.resolveAPIBaseURL(saved: UserDefaults.standard.string(forKey: Self.serverKey), bundled: AppInfo.bundledAPIBaseURL)
        session = store.load()
    }

    func signIn(email: String, password: String) async {
        signInError = nil
        let address = serverURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !address.isEmpty, address.lowercased().hasPrefix("http") else {
            signInError = "Enter the server address first (it starts with https://)."
            return
        }
        signingIn = true
        defer { signingIn = false }
        do {
            let next = try await AuthClient(baseURL: address).login(
                email: email.trimmingCharacters(in: .whitespaces), password: password,
                deviceId: DeviceIdentity.id, deviceName: DeviceIdentity.name
            )
            store.save(next)
            session = next
        } catch let error as APIError {
            signInError = error.errorDescription
        } catch {
            signInError = "Couldn't reach the server. Check the address and your connection."
        }
    }

    /// Runs a call that needs the signed-in token; if the backend says the token has run out, trades the refresh token and tries once more.
    func authorized<T>(_ call: (AuthClient, String) async throws -> T) async throws -> T {
        guard let current = session else { throw APIError.server(status: 401, message: nil) }
        let client = AuthClient(baseURL: serverURL)
        do {
            return try await call(client, current.accessToken)
        } catch let APIError.server(status, _) where status == 401 {
            let renewed = try await client.refresh(current)
            store.save(renewed)
            session = renewed
            return try await call(client, renewed.accessToken)
        }
    }

    func signOut() async {
        if let token = session?.accessToken, !serverURL.isEmpty {
            await AuthClient(baseURL: serverURL).logout(accessToken: token)
        }
        store.clear()
        session = nil
        home = .idle
        myList = nil
        continueItems = []
        addons = []
        allAddons = []
        settings = nil
        detail = nil
        sourcesFor = nil
        playing = nil
        selected = .home
    }

    func loadHome() async {
        if case .loaded = home { return }
        home = .loading
        let year = Calendar.current.component(.year, from: Date())
        let rows = await HomeRows.load(specs: HomeRows.defaultRows(year: year), manifestURL: AppInfo.cinemetaManifestURL)
        home = rows.isEmpty ? .empty : .loaded(rows)
    }

    func openDetail(_ item: MetaPreview) { detail = item }

    func openSources(_ target: PlayTarget) { sourcesFor = target }

    func play(_ item: PlayingItem) { playing = item }

    /// Back one step: player, then sources, then the title's page.
    func goBack() {
        if playing != nil { playing = nil } else if sourcesFor != nil { sourcesFor = nil } else { detail = nil }
    }

    /// The account's installed addons: where streams come from. Loaded once after sign-in.
    func loadAddons() async {
        if let found = try? await authorized({ client, token in try await client.addons(accessToken: token, includeDisabled: true) }) {
            allAddons = found
            addons = found.filter(\.enabled)
        }
    }

    func installAddon(_ install: AddonInstall) async throws {
        let order = (allAddons.map(\.sortOrder).max() ?? -1) + 1
        try await authorized { client, token in
            try await client.saveAddon(accessToken: token, manifestURL: install.manifestURL, addonID: install.addonID, name: install.name,
                                       rawManifest: install.rawManifest, enabled: true, sortOrder: order)
        }
        await loadAddons()
    }

    func setAddon(_ addon: SyncedAddon, enabled: Bool) async {
        guard let raw = addon.rawManifest else { return }
        _ = try? await authorized { client, token in
            try await client.saveAddon(accessToken: token, manifestURL: addon.manifestUrl, addonID: addon.addonId, name: addon.name,
                                       rawManifest: raw, enabled: enabled, sortOrder: addon.sortOrder)
        }
        await loadAddons()
    }

    func removeAddon(_ addon: SyncedAddon) async {
        _ = try? await authorized { client, token in try await client.removeAddon(accessToken: token, manifestURL: addon.manifestUrl) }
        await loadAddons()
    }

    // MARK: Settings (blocked genres)

    var blockedGenres: Set<String> { Set(settings?.blockedGenres ?? []) }

    func loadSettings() async {
        if let found = try? await authorized({ client, token in try await client.settings(accessToken: token) }) { settings = found }
    }

    /// Hides (or shows again) a genre everywhere. Shown at once; put back if the account could not be reached.
    func setGenre(_ genre: String, blocked: Bool) async {
        if settings == nil { await loadSettings() }
        guard var next = settings else { return }
        let before = next
        var list = next.blockedGenres ?? []
        list.removeAll { $0.caseInsensitiveCompare(genre) == .orderedSame }
        if blocked { list.append(genre) }
        next.blockedGenres = list
        settings = next
        do {
            settings = try await authorized { client, token in try await client.saveSettings(accessToken: token, next) }
        } catch {
            settings = before
        }
    }

    // MARK: My List, Watched and Continue Watching

    /// Loads everything the account keeps: My List and Continue Watching.
    func loadAccountData() async {
        await loadMyList()
        await loadContinueWatching()
    }

    func loadMyList() async {
        myListError = nil
        do {
            myList = try await authorized { client, token in try await client.watchlist(accessToken: token) }
        } catch {
            myListError = (error as? APIError)?.errorDescription ?? "Couldn't load your list. Check your connection."
        }
    }

    func loadContinueWatching() async {
        if let items = try? await authorized({ client, token in try await client.continueWatching(accessToken: token) }) {
            continueItems = items
        }
    }

    func savedItem(_ id: String) -> WatchlistItem? { myList?.first { $0.contentId == id } }

    func isSaved(_ id: String) -> Bool { savedItem(id) != nil }

    func isWatched(_ id: String) -> Bool { savedItem(id)?.watched == true }

    /// Adds the title to My List, or takes it off. Shown at once; put back if the account could not be reached.
    func toggleSaved(_ title: MetaDetail) async {
        let before = myList ?? []
        if let existing = savedItem(title.id) {
            myList = before.filter { $0.contentId != title.id }
            do { try await authorized { client, token in try await client.removeFromWatchlist(accessToken: token, item: existing) } } catch { myList = before }
        } else {
            let item = title.watchlistItem(watched: false)
            myList = before + [item]
            do { try await authorized { client, token in try await client.saveToWatchlist(accessToken: token, item: item) } } catch { myList = before }
        }
    }

    /// Marks the title watched, or not watched again (adding it to My List if it was not there).
    func toggleWatched(_ title: MetaDetail) async {
        let before = myList ?? []
        let nowWatched = !isWatched(title.id)
        var item = savedItem(title.id) ?? title.watchlistItem(watched: nowWatched)
        item.watched = nowWatched
        item.updatedAt = ISODate.now()
        myList = before.filter { $0.contentId != title.id } + [item]
        let toSend = item
        do { try await authorized { client, token in try await client.saveToWatchlist(accessToken: token, item: toSend) } } catch { myList = before }
    }

    func removeFromContinueWatching(_ item: ContinueItem) async {
        let before = continueItems
        continueItems = before.filter { $0.contentId != item.contentId }
        do { try await authorized { client, token in try await client.removeContinueWatching(accessToken: token, item: item) } } catch { continueItems = before }
    }

    /// Where this episode or movie was left, if Continue Watching has it.
    func resumeItem(titleID: String, season: Int?, episode: Int?) -> ContinueItem? {
        guard let item = continueItems.first(where: { $0.contentId == titleID }) else { return nil }
        if season == nil && episode == nil { return item }
        return item.seasonNumber == season && item.episodeNumber == episode ? item : nil
    }

    /// Tells the account where playback is (called now and then while playing, and when leaving the player).
    func reportProgress(_ target: PlayTarget, position: Double, duration: Double) async {
        guard duration > 30, position > 5 else { return }
        let completed = position / duration >= 0.92
        _ = try? await authorized { client, token in
            try await client.reportProgress(accessToken: token, title: target.title, season: target.season, episode: target.episode,
                                            episodeTitle: target.episodeTitle, positionSeconds: position, durationSeconds: duration, completed: completed)
        }
        if completed, !isWatched(target.title.id), target.title.type == "movie" { await toggleWatched(target.title) }
        await loadContinueWatching()
    }

    func reloadHome() async {
        home = .idle
        await loadHome()
    }
}
