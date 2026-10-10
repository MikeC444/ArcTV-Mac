import ArcTVCore
import AppKit
import Foundation
import Network
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
    /// Show the source list even when this title was watched on a source before (Choose source).
    var chooseSource = false

    var id: String { streamID }
    var streamID: String { ArcTVCore.streamID(titleID: title.id, season: season, episode: episode) }
    var heading: String { episodeTitle.map { "\(title.name) · \($0)" } ?? title.name }
}

/// What the poster menu is about, and where it was opened from.
struct CardMenuTarget: Equatable {
    var item: MetaPreview
    var fromPicked = false
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
        case loaded
        case empty
    }

    @Published var session: Session?
    @Published var selected: NavItem = .home
    @Published var playerEngine: PlayerEngine = PlayerEngine(rawValue: UserDefaults.standard.string(forKey: "ArcTVPlayerEngine") ?? "") ?? .mpv {
        didSet { UserDefaults.standard.set(playerEngine.rawValue, forKey: "ArcTVPlayerEngine") }
    }
    @Published var home: HomeState = .idle
    /// Every row the account's addons gave Home, as they arrived (before hiding, ordering and leaving out what has been seen).
    @Published private(set) var homeRaw: [HomeSection] = []
    /// The titles the Home banner rotates through, picked once per launch.
    @Published private(set) var heroTitles: [MetaPreview] = []
    /// The addons that fill Home, Movies, TV Shows and Search (every enabled one that offers catalogues; Cinemeta when there is none).
    @Published private(set) var catalogSources: [HomeSource] = []
    /// False while the Mac has no network.
    @Published private(set) var online = true
    private var homeFromCache = false
    private let homeCache = HomeCache()
    private let pathMonitor = NWPathMonitor()
    private var homeComplete = false
    private var homeGeneration = 0
    private var heroKey: String?
    private var trailers: [String: String] = [:]
    /// Which screen is open over the tabs: a title's details, then its sources, then the player (each sits on top of the one before).
    @Published var detail: MetaPreview?
    @Published var sourcesFor: PlayTarget?
    @Published var playing: PlayingItem? {
        didSet { if playing == nil { TorrentEngine.shared.stop() } }
    }
    /// The poster whose actions menu (right-click) is open.
    @Published var cardMenu: CardMenuTarget?
    /// The account's profiles (Arc TV Plus), the one in use, and whether "Who's watching?" is open.
    @Published private(set) var profiles: [Profile] = []
    @Published private(set) var activeProfileID = Profile.mainID
    @Published var profilePickerOpen = false
    private var profileChosen = false
    private var bootstrapped = false
    /// The sources set-up guide is open.
    @Published var guideOpen = false
    /// Which place in Settings is showing.
    @Published var settingsTab: SettingsTab = .account
    @Published var addons: [SyncedAddon] = []
    /// Every addon on the account, switched off ones included (for Settings > Addons); [addons] is just the enabled ones.
    @Published var allAddons: [SyncedAddon] = []
    @Published var settings: AccountSettings?
    @Published var myList: [WatchlistItem]?
    @Published var continueItems: [ContinueItem] = []
    @Published var myListError: String?
    /// What the account has of Arc TV Plus (Like / Not for me and Picked for you need it).
    @Published var plus: PlusStatus = .none
    /// Like / Not for me by title id.
    @Published var ratings: [String: FeedbackItem] = [:]
    /// Titles taken out of Picked for you by hand, and when (each stays out for five days).
    @Published var pickedRemoved: [String: Date] = [:]
    /// Posters of rated titles, kept on this Mac so Settings can show them (the account does not store them).
    @Published var ratingPosters: [String: String] = [:]
    /// What the engine last picked; the row on Home is made from it, minus anything marked since.
    @Published private(set) var pickedResult: EngineResult?
    private var pickedPool: [MetaPreview] = []
    private var pickedKey = ""
    private var accountLoaded = false
    private var pickedTask: Task<Void, Never>?
    private var pickedSeed = Int.random(in: 0...Int(Int32.max))
    private var previousShown: Set<String> = []
    private var rememberedShown = false
    private let featureCache = FeatureCache.standard()
    @Published var signInError: String?
    @Published var signingIn = false
    /// Set when the service says "too many attempts": the time the sign-in button works again.
    @Published var waitUntil: Date?

    /// The backend address: what the person typed on the sign-in screen last time, else the one baked into this build, else the default.
    @Published var serverURL: String {
        didSet { UserDefaults.standard.set(serverURL, forKey: Self.serverKey) }
    }

    private static let serverKey = "ArcTVServerURL"
    private static let removedBase = "ArcTVPickedRemoved"
    private static let posterBase = "ArcTVRatingPosters"
    private static let shownBase = "ArcTVPickedShown"
    private static let activeProfileBase = "ArcTVActiveProfile"
    private let store = SessionStore()

    init() {
        serverURL = AppInfo.resolveAPIBaseURL(saved: UserDefaults.standard.string(forKey: Self.serverKey), bundled: AppInfo.bundledAPIBaseURL)
        session = store.load()
        pathMonitor.pathUpdateHandler = { [weak self] path in
            let reachable = path.status == .satisfied
            Task { @MainActor [weak self] in self?.online = reachable }
        }
        pathMonitor.start(queue: DispatchQueue(label: "arctv.network"))
        loadProfileLocalState()
    }

    /// Signs in (or, with `register`, makes the account first). Failures are put in words in `signInError`; "too many tries" sets `waitUntil`.
    func signIn(email: String, password: String, register: Bool = false, displayName: String = "") async {
        signInError = nil
        let address = serverURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !address.isEmpty, address.lowercased().hasPrefix("http") else {
            signInError = "Enter the server address first (it starts with https://)."
            return
        }
        if let problem = Credentials.problem(email: email, password: password) {
            signInError = problem
            return
        }
        signingIn = true
        defer { signingIn = false }
        do {
            let client = AuthClient(baseURL: address)
            let cleanEmail = email.trimmingCharacters(in: .whitespaces)
            let next = register
                ? try await client.register(email: cleanEmail, password: password, displayName: displayName, deviceId: DeviceIdentity.id, deviceName: DeviceIdentity.name)
                : try await client.login(email: cleanEmail, password: password, deviceId: DeviceIdentity.id, deviceName: DeviceIdentity.name)
            store.save(next)
            session = next
        } catch let error as APIError {
            if case .server(429, _) = error {
                waitUntil = Date().addingTimeInterval(30)
            } else {
                signInError = error.errorDescription
            }
        } catch {
            signInError = "Couldn't reach the server. Check the address and your connection."
        }
    }

    /// Finishes a sign-in that was completed on a phone (the QR code): keeps the session as if the person had typed their password.
    func finishQRSignIn(_ next: Session) {
        store.save(next)
        signInError = nil
        session = next
    }

    /// Runs a call that needs the signed-in token; if the backend says the token has run out, trades the refresh token and tries once more.
    func authorized<T>(_ call: (AuthClient, String) async throws -> T) async throws -> T {
        guard let current = session else { throw APIError.server(status: 401, message: nil) }
        let client = AuthClient(baseURL: serverURL, profileID: activeProfileID)
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
        homeRaw = []
        heroTitles = []
        myList = nil
        continueItems = []
        addons = []
        allAddons = []
        settings = nil
        plus = .none
        profiles = []
        activeProfileID = Profile.mainID
        profilePickerOpen = false
        profileChosen = false
        bootstrapped = false
        stats = nil
        plusPopup = nil
        popupShownThisLaunch = false
        ratings = [:]
        pickedResult = nil
        pickedKey = ""
        accountLoaded = false
        pickedTask?.cancel()
        detail = nil
        cardMenu = nil
        guideOpen = false
        sourcesFor = nil
        playing = nil
        selected = .home
    }

    /// Fills Home from the account's addons (every enabled one that offers catalogues; Cinemeta when there is none), as the web app does.
    func loadHome() async {
        guard home == .idle else { return }
        home = .loading
        homeRaw = []
        homeComplete = false
        homeGeneration += 1
        let generation = homeGeneration
        // The last launch's rows are on screen at once; the fresh ones replace them as soon as the first arrive.
        if let userID = scope, let cached = homeCache.load(userID: userID) {
            homeRaw = cached
            homeFromCache = true
            home = .loaded
            pickHero()
        }

        var sources = addons.compactMap { addon in addon.manifestJson.map { HomeSource(manifestURL: addon.manifestUrl, manifest: $0) } }
            .filter { !$0.catalogs.isEmpty }
        if sources.isEmpty, let manifest = try? await AddonClient().fetchManifest(AppInfo.cinemetaManifestURL) {
            sources = [HomeSource(manifestURL: AppInfo.cinemetaManifestURL, manifest: manifest)]
        }
        catalogSources = sources
        let seed = "\(session?.user.id ?? "guest")|\(HomeVariety.dayStamp())"
        await withTaskGroup(of: Void.self) { group in
            for source in sources {
                group.addTask { await HomeSections.load(source: source, seed: seed) { batch in await self.receive(batch, generation: generation) } }
            }
        }
        guard generation == homeGeneration else { return }
        homeComplete = true
        if homeRaw.isEmpty { home = .empty }
        if !homeFromCache, !homeRaw.isEmpty, let userID = scope { homeCache.save(homeRaw, userID: userID) }
        pickHero()
        schedulePicked()
    }

    private func receive(_ batch: [HomeSection], generation: Int) {
        guard generation == homeGeneration else { return }
        if homeFromCache {
            homeFromCache = false
            homeRaw = []
        }
        homeRaw += batch
        home = .loaded
        pickHero()
        schedulePicked()
    }

    /// What Home shows below the banner: the rows without titles you have watched, saved or rated, in the order chosen in Settings, hidden rows
    /// left out, each title once.
    var homeSections: [HomeSection] {
        let blocked = blockedGenres
        var raw = homeRaw
        if !blocked.isEmpty {
            raw = raw.map { HomeSection(id: $0.id, title: $0.title, items: $0.items.withoutBlocked(blocked)) }.filter { !$0.items.isEmpty }
        }
        var seen = Set(ratings.keys)
        for item in myList ?? [] { seen.insert(item.contentId) }
        let unseen = raw.map { HomeSection(id: $0.id, title: $0.title, items: $0.items.filter { !seen.contains($0.id) }) }.filter { !$0.items.isEmpty }
        let hidden = settings?.hiddenRowIds ?? []
        let preferences = HomeRowPreferences(order: settings?.homeRowOrder ?? [], hiddenRowIds: hidden)
        return unseen.ordered(by: preferences).filter { !hidden.contains($0.id) }.deduped()
    }

    /// Ten random titles from the rows that are switched on, chosen once per launch (again only if the hidden rows or blocked genres change).
    private func pickHero() {
        let key = (settings?.hiddenRowIds ?? []).joined(separator: "|") + "#" + blockedGenres.sorted().joined(separator: "|")
        if heroKey != key {
            heroKey = key
            heroTitles = []
        }
        guard heroTitles.isEmpty else { return }
        let pool = distinctByID(homeSections.flatMap(\.items))
        guard pool.count >= 10 || homeComplete else { return }
        let backup = distinctByID(homeRaw.flatMap(\.items)).withoutBlocked(blockedGenres)
        var generator = SystemRandomNumberGenerator()
        heroTitles = HeroPool.pickTitles(enabled: pool, backup: backup, size: 10, using: &generator)
    }

    /// Plays a title the way the poster menu and the banner do: pick up where you left off, play a movie, or open a show's page (it knows the
    /// first episode).
    func play(_ item: MetaPreview) {
        let detail = item.asDetail
        if let resume = continueItems.first(where: { $0.contentId == item.id }) {
            openSources(PlayTarget(title: detail, season: resume.seasonNumber, episode: resume.episodeNumber, episodeTitle: resume.episodeTitle, startAt: resume.positionSeconds))
        } else if item.type == "series" {
            openDetail(item)
        } else {
            openSources(PlayTarget(title: detail))
        }
    }

    /// The YouTube id of a title's trailer, nil when there is none. Remembered for the session.
    func trailerID(for item: MetaPreview) async -> String? {
        let key = "\(item.type)|\(item.name)|\(item.year ?? 0)"
        if let known = trailers[key] { return known }
        guard let found = try? await authorized({ client, token in
            try await client.trailerID(accessToken: token, title: item.name, type: item.type, year: item.year)
        }) else { return nil }
        trailers[key] = found
        return found
    }

    func openDetail(_ item: MetaPreview) { detail = item }

    /// Goes to a place in Settings from anywhere (closing whatever is open over the tabs).
    func openSettings(_ tab: SettingsTab) {
        playing = nil
        sourcesFor = nil
        detail = nil
        guideOpen = false
        settingsTab = tab
        selected = .settings
    }

    func openCardMenu(_ item: MetaPreview, fromPicked: Bool = false) { cardMenu = CardMenuTarget(item: item, fromPicked: fromPicked) }

    func openSources(_ target: PlayTarget) { sourcesFor = target }

    func play(_ item: PlayingItem) { playing = item }

    private var torrentTask: Task<Void, Never>?

    /// Streams a torrent source in the app's own torrent engine, then plays it. The engine reports how it is getting on.
    func startTorrent(_ item: SourceItem, target: PlayTarget) {
        guard let magnet = item.stream.magnetURI else { return }
        torrentTask?.cancel()
        torrentTask = Task { @MainActor [weak self] in
            do {
                let url = try await TorrentEngine.shared.prepare(
                    magnet: magnet, fileIndex: item.stream.fileIdx, season: target.season, episode: target.episode
                )
                self?.play(PlayingItem(url: url, heading: target.heading, sourceName: item.addonName, target: target))
            } catch is CancellationError {
                TorrentEngine.shared.stop()
            } catch {
                TorrentEngine.shared.stop()
                TorrentEngine.shared.failure = (error as? LocalizedError)?.errorDescription ?? "The torrent could not be played."
            }
        }
    }

    func cancelTorrent() {
        torrentTask?.cancel()
        torrentTask = nil
        TorrentEngine.shared.stop()
    }

    /// Back one step: player, then sources, then the title's page.
    func goBack() {
        if playing != nil { playing = nil } else if sourcesFor != nil { cancelTorrent(); sourcesFor = nil } else { detail = nil }
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
        await refreshHomeRows()
    }

    func setAddon(_ addon: SyncedAddon, enabled: Bool) async {
        guard let raw = addon.rawManifest else { return }
        _ = try? await authorized { client, token in
            try await client.saveAddon(accessToken: token, manifestURL: addon.manifestUrl, addonID: addon.addonId, name: addon.name,
                                       rawManifest: raw, enabled: enabled, sortOrder: addon.sortOrder)
        }
        await loadAddons()
        await refreshHomeRows()
    }

    func removeAddon(_ addon: SyncedAddon) async {
        _ = try? await authorized { client, token in try await client.removeAddon(accessToken: token, manifestURL: addon.manifestUrl) }
        await loadAddons()
        await refreshHomeRows()
    }

    // MARK: Settings (blocked genres)

    /// What is hidden everywhere: the profile's own blocked genres, and on a kids profile the kids list too.
    var blockedGenres: Set<String> {
        var set = Set(settings?.blockedGenres ?? [])
        if isKids { set.formUnion(Profile.kidsBlockedGenres) }
        return set
    }

    func loadSettings() async {
        if let found = try? await authorized({ client, token in try await client.settings(accessToken: token) }) { settings = found }
        schedulePicked()
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
        schedulePicked()
    }

    /// Changes one or more of the account's settings: shown at once, saved to the account, and put back if the save fails.
    func updateSettings(_ edit: (inout AccountSettings) -> Void) async {
        if settings == nil { await loadSettings() }
        guard var next = settings else { return }
        let before = next
        edit(&next)
        guard next != before else { return }
        settings = next
        do {
            settings = try await authorized { client, token in try await client.saveSettings(accessToken: token, next) }
        } catch {
            settings = before
        }
    }

    /// Every row Home can show, in the order the person has chosen, with whether it is switched on.
    var homeRowChoices: [(section: HomeSection, visible: Bool)] {
        let hidden = Set(settings?.hiddenRowIds ?? [])
        let preferences = HomeRowPreferences(order: settings?.homeRowOrder ?? [], hiddenRowIds: Array(hidden))
        return homeRaw.ordered(by: preferences).map { ($0, !hidden.contains($0.id)) }
    }

    func setRowVisible(_ id: String, visible: Bool) async {
        await updateSettings { value in
            value.hiddenRowIds.removeAll { $0 == id }
            if !visible { value.hiddenRowIds.append(id) }
        }
        pickHero()
        schedulePicked()
    }

    func moveRow(_ id: String, delta: Int) async {
        let order = homeRowChoices.map(\.section.id)
        await updateSettings { $0.homeRowOrder = HomeRowOrder.move(order, id: id, delta: delta) }
    }

    // MARK: My List, Watched and Continue Watching

    /// Loads everything the account keeps: My List and Continue Watching.
    func loadAccountData() async {
        await loadMyList()
        await loadContinueWatching()
        await loadPlus()
        if plus.active {
            await loadRatings()
            await loadPickedRemovals()
        }
        accountLoaded = true
        schedulePicked()
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
            schedulePicked()
        } else {
            let item = title.watchlistItem(watched: false)
            myList = before + [item]
            do { try await authorized { client, token in try await client.saveToWatchlist(accessToken: token, item: item) } } catch { myList = before }
            schedulePicked()
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
        schedulePicked()
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
        // A refresh swaps most of Picked for you: what is showing now becomes "shown last time" and a new draw starts.
        if let shown = picked?.entries.map(\.id) {
            previousShown = Set(shown)
            UserDefaults.standard.set(shown, forKey: shownKey)
        }
        pickedSeed = Int.random(in: 0...Int(Int32.max))
        pickedKey = ""
        await refreshHomeRows()
    }

    /// Fetches Home's rows again (after the addons change, or on a refresh).
    func refreshHomeRows() async {
        heroTitles = []
        home = .idle
        await loadHome()
    }

    // MARK: Arc TV Plus: Like / Not for me and Picked for you

    func loadPlus() async {
        if let found = try? await authorized({ client, token in try await client.plusStatus(accessToken: token) }) { plus = found }
    }

    func loadRatings() async {
        guard let items = try? await authorized({ client, token in try await client.feedback(accessToken: token) }) else { return }
        var next: [String: FeedbackItem] = [:]
        for item in items where item.deletedAt == nil && item.rating != nil { next[item.contentId] = item }
        ratings = next
    }

    func loadPickedRemovals() async {
        guard let items = try? await authorized({ client, token in try await client.pickedDismissals(accessToken: token) }) else { return }
        pickedRemoved = PickedDismissals.merged(pickedRemoved, with: items)
        savePickedRemoved()
    }

    func rating(of id: String) -> Rating? { ratings[id]?.rating }

    /// Likes (or marks Not for me) a title; doing the same again takes the rating off. Shown at once; put back if the account could not be reached.
    func rate(_ item: MetaPreview, _ rating: Rating) async {
        guard plus.active else { return }
        let before = ratings
        let beforePosters = ratingPosters
        if let existing = ratings[item.id], existing.rating == rating {
            ratings[item.id] = nil
            do { try await authorized { client, token in try await client.clearFeedback(accessToken: token, item: existing) } } catch { ratings = before }
        } else {
            let entry = FeedbackItem(title: item, rating: rating)
            ratings[item.id] = entry
            if let poster = item.poster { ratingPosters[item.id] = poster }
            do { try await authorized { client, token in try await client.setFeedback(accessToken: token, item: entry) } } catch {
                ratings = before
                ratingPosters = beforePosters
            }
        }
        UserDefaults.standard.set(ratingPosters, forKey: posterKey)
        schedulePicked()
    }

    /// Clears every Like and Not for me. Anything the account could not clear stays.
    func resetRatings() async {
        let all = Array(ratings.values)
        ratings = [:]
        for item in all {
            do { try await authorized { client, token in try await client.clearFeedback(accessToken: token, item: item) } } catch { ratings[item.contentId] = item }
        }
        if ratings.isEmpty { ratingPosters = [:] }
        UserDefaults.standard.set(ratingPosters, forKey: posterKey)
        schedulePicked()
    }

    /// Takes a title out of Picked for you for five days (no taste signal), on every device.
    func removeFromPicked(_ id: String) async {
        let now = Date()
        pickedRemoved[id] = now
        savePickedRemoved()
        _ = try? await authorized { client, token in try await client.dismissPicked(accessToken: token, contentID: id, at: now) }
    }

    private func savePickedRemoved() {
        let live = pickedRemoved.filter { Date().timeIntervalSince($0.value) < PickedDismissals.window }
        pickedRemoved = live
        UserDefaults.standard.set(live.mapValues { $0.timeIntervalSince1970 }, forKey: removedKey)
    }

    /// Titles that must not show in Picked for you right now: rated, finished, or already in Continue Watching.
    private var hiddenFromPicked: Set<String> {
        var ids = Set(ratings.keys).union(continueItems.map(\.contentId))
        for item in myList ?? [] where item.watched == true { ids.insert(item.contentId) }
        return ids
    }

    var pickedAvailable: Bool { plus.active && session != nil }

    /// The Picked for you row for Home, nil when there is none (not Plus, nothing picked yet).
    var picked: PickedRow? {
        guard pickedAvailable else { return nil }
        return pickedRow(result: pickedResult, pool: pickedPool, hiddenIDs: hiddenFromPicked, dismissed: PickedDismissals.active(pickedRemoved))
    }

    /// Works out the row again when what feeds it has changed (ratings, My List, what is on offer). The picks are chosen with this launch's seed,
    /// so they stay put until Home is refreshed.
    func schedulePicked() {
        guard pickedAvailable else {
            pickedResult = nil
            return
        }
        guard accountLoaded, home == .loaded else { return }
        let pool = distinctByID(homeRaw.flatMap(\.items)).withoutBlocked(blockedGenres)
        let types = Dictionary((myList ?? []).map { ($0.contentId, $0.contentType == "MOVIE" ? "movie" : "series") }, uniquingKeysWith: { first, _ in first })
        var refs: [String: TitleRef] = [:]
        var rated: [String: (title: String, rating: Rating)] = [:]
        for (id, item) in ratings {
            guard let rating = item.rating else { continue }
            rated[id] = (item.title, rating)
            refs[id] = TitleRef(id: id, providerId: item.providerId, type: item.contentType == "MOVIE" ? "movie" : "series")
        }
        for item in myList ?? [] where refs[item.contentId] == nil {
            refs[item.contentId] = TitleRef(id: item.contentId, providerId: item.providerId, type: types[item.contentId])
        }
        let interactions = collectInteractions(interactionInputs(list: myList ?? [], ratings: rated))
        let key = signatureOf(interactions) + "#" + pool.map(\.id).joined(separator: ",")
        if key == pickedKey { return }
        pickedKey = key

        let excluded = excludedFromPicks(list: myList ?? [], ratedIDs: Set(ratings.keys), continueIDs: Set(continueItems.map(\.contentId)),
                                         dismissed: PickedDismissals.active(pickedRemoved))
        let loader = FeatureLoading.loader(cache: featureCache) { ref in
            let meta = try? await AddonClient().fetchMeta(manifestURL: AppInfo.cinemetaManifestURL, type: ref.type ?? "movie", id: ref.id)
            return meta.map(featuresFromMeta)
        }
        let input = EngineInput(interactions: interactions, excludeIDs: excluded, pool: pool.map(\.asCandidate), interactionRefs: refs,
                                loadFeatures: loader, seed: pickedSeed, previousShown: previousShown)
        pickedTask?.cancel()
        pickedTask = Task { [weak self] in
            let result = await recommend(input)
            guard !Task.isCancelled, let model = self else { return }
            model.pickedPool = pool
            model.pickedResult = result
            if !model.rememberedShown, result.isPersonal {
                model.rememberedShown = true
                UserDefaults.standard.set(result.items.map(\.id), forKey: shownKey)
            }
        }
    }

    // MARK: Profiles (Arc TV Plus)

    var activeProfile: Profile? { profiles.first { $0.id == activeProfileID } }

    var isKids: Bool { activeProfile?.isKids == true }

    /// What this account's local copies (cached Home rows, recent searches, remembered sources) are filed under: the account, and the profile when it
    /// is not the account's own, so the account's own profile keeps the names it always had.
    var scope: String? {
        guard let user = session?.user.id else { return nil }
        return activeProfileID == Profile.mainID ? user : "\(user)-\(activeProfileID)"
    }

    private var suffix: String { activeProfileID == Profile.mainID ? "" : "-\(activeProfileID)" }
    private var removedKey: String { Self.removedBase + suffix }
    private var posterKey: String { Self.posterBase + suffix }
    private var shownKey: String { Self.shownBase + suffix }

    /// Reads what is kept on this Mac for the profile in use: picks taken out of Picked for you, rated titles' posters, what showed last time.
    private func loadProfileLocalState() {
        let defaults = UserDefaults.standard
        pickedRemoved = (defaults.dictionary(forKey: removedKey) as? [String: Double] ?? [:]).mapValues { Date(timeIntervalSince1970: $0) }
        ratingPosters = defaults.dictionary(forKey: posterKey) as? [String: String] ?? [:]
        previousShown = Set(defaults.stringArray(forKey: shownKey) ?? [])
        rememberedShown = false
    }

    /// Everything after sign-in: Plus, the profiles (and "Who's watching?" when there is more than one), then the library of the profile in use.
    func bootstrap() async {
        guard !bootstrapped else { return }
        bootstrapped = true
        await loadPlus()
        await loadProfiles()
        if plus.active, profiles.count > 1, !profileChosen {
            profilePickerOpen = true
            return
        }
        await loadLibrary()
    }

    private func loadLibrary() async {
        await loadAddons()
        await loadSettings()
        async let home: Void = loadHome()
        async let account: Void = loadAccountData()
        _ = await (home, account)
    }

    /// Reads the profile list. Without Plus (or on a backend that has no profiles) there is only the account's own profile.
    func loadProfiles() async {
        let found = plus.active ? ((try? await authorized { client, token in try await client.profiles(accessToken: token) }) ?? []) : []
        profiles = found.isEmpty ? [] : found
        let user = session?.user.id ?? ""
        let remembered = UserDefaults.standard.string(forKey: "\(Self.activeProfileBase)-\(user)") ?? Profile.mainID
        let wanted = profiles.contains { $0.id == remembered } ? remembered : Profile.mainID
        if wanted != activeProfileID {
            activeProfileID = wanted
            loadProfileLocalState()
        }
    }

    /// Opens a profile: checks its PIN when it has one, then starts over on that profile's library (nothing of the last one stays in memory).
    /// Returns nil when it worked, else what to tell the person.
    func selectProfile(_ profile: Profile, pin: String?) async -> String? {
        if profile.hasPin {
            guard let pin, Profile.isValidPin(pin) else { return "Enter the 4-digit PIN." }
            let result = (try? await authorized { client, token in try await client.verifyPin(accessToken: token, id: profile.id, pin: pin) })
            switch result {
            case .ok: break
            case .wrong: return "That PIN is wrong."
            case .locked: return "Too many wrong PINs. Try again in a few minutes."
            case nil: return "Couldn't check the PIN. Check your connection and try again."
            }
        }
        profileChosen = true
        profilePickerOpen = false
        let different = profile.id != activeProfileID
        UserDefaults.standard.set(profile.id, forKey: "\(Self.activeProfileBase)-\(session?.user.id ?? "")")
        if different || !bootstrappedLibrary {
            activeProfileID = profile.id
            resetLibrary()
            await loadLibrary()
        }
        return nil
    }

    /// True once a library has been loaded (so choosing the same profile again does not load it twice).
    private var bootstrappedLibrary: Bool { home != .idle || myList != nil }

    /// Forgets the library in memory so the next profile starts clean.
    private func resetLibrary() {
        pickedTask?.cancel()
        homeGeneration += 1
        home = .idle
        homeRaw = []
        heroTitles = []
        heroKey = nil
        homeFromCache = false
        homeComplete = false
        catalogSources = []
        myList = nil
        continueItems = []
        addons = []
        allAddons = []
        settings = nil
        ratings = [:]
        pickedResult = nil
        pickedPool = []
        pickedKey = ""
        accountLoaded = false
        trailers = [:]
        detail = nil
        sourcesFor = nil
        playing = nil
        cardMenu = nil
        guideOpen = false
        selected = .home
        loadProfileLocalState()
    }

    func createProfile(name: String, avatar: String, kind: String, pin: String?) async throws {
        _ = try await authorized { client, token in try await client.createProfile(accessToken: token, name: name, avatar: avatar, kind: kind, pin: pin) }
        await loadProfiles()
    }

    func updateProfile(_ profile: Profile, name: String, avatar: String, kind: String, pin: String??, currentPin: String?) async throws {
        _ = try await authorized { client, token in
            try await client.updateProfile(accessToken: token, id: profile.id, name: name, avatar: avatar, kind: kind, pin: pin, currentPin: currentPin)
        }
        await loadProfiles()
    }

    func deleteProfile(_ profile: Profile, currentPin: String?) async throws {
        try await authorized { client, token in try await client.deleteProfile(accessToken: token, id: profile.id, currentPin: currentPin) }
        await loadProfiles()
    }

    // MARK: Arc TV Plus: plans, stats, switches and popups

    /// Smart source picking (Plus): start the best source without asking. Kept on this Mac, like the other player choices.
    @Published var smartPicking: Bool = UserDefaults.standard.bool(forKey: "ArcTVSmartPicking") {
        didSet { UserDefaults.standard.set(smartPicking, forKey: "ArcTVSmartPicking") }
    }

    /// Watch statistics for the profile in use (nil while loading).
    @Published var stats: WatchStats?
    @Published var statsFailed = false
    @Published var statsTruncated = false

    /// Which Plus popup is on screen.
    enum PlusPopup: Equatable { case welcome, invitation }
    @Published var plusPopup: PlusPopup?
    /// A popup opened from Settings > Updates to look at it: closing it leaves no trace (it is not counted as seen).
    private var plusPopupIsPreview = false
    /// Demo: while true, the Plus invitation shows by itself a few seconds after Home loads (as a preview, so it is never counted as seen).
    static let plusPopupDemo = false

    func previewPlusPopup(_ popup: PlusPopup) {
        plusPopupIsPreview = true
        plusPopup = popup
    }
    /// A newer version of the app than this one, offered once (until "Skip this version" or Later).
    @Published var updateOffer: ReleaseInfo?
    private static let skippedUpdateKey = "ArcTVSkippedUpdate"
    private var checkedForUpdate = false

    /// Asks GitHub once per launch whether a newer version is out; quiet when offline or when the person skipped that version.
    func checkForUpdate() async {
        guard !checkedForUpdate else { return }
        checkedForUpdate = true
        guard case let .available(info)? = try? await UpdateCheck.check(current: AppInfo.version) else { return }
        if UserDefaults.standard.string(forKey: Self.skippedUpdateKey) == info.version { return }
        updateOffer = info
    }

    func dismissUpdate(skip: Bool) {
        if skip, let version = updateOffer?.version { UserDefaults.standard.set(version, forKey: Self.skippedUpdateKey) }
        updateOffer = nil
    }
    private var popupShownThisLaunch = false
    private var purchaseWatch: Task<Void, Never>?

    private func popupKey(_ name: String) -> String { "ArcTVPlus\(name)-\(session?.user.id ?? "")" }

    func loadStats() async {
        statsFailed = false
        do {
            let found = try await authorized { client, token in try await client.history(accessToken: token) }
            stats = WatchStats.compute(found.items)
            statsTruncated = found.truncated
        } catch {
            statsFailed = true
        }
    }

    /// Opens Stripe's checkout for a plan in the browser, then asks every few seconds until Plus is on (or ten minutes pass).
    func startCheckout(_ plan: String) async throws {
        let link = try await authorized { client, token in try await client.startCheckout(accessToken: token, plan: plan) }
        guard let url = URL(string: link.url), url.scheme?.lowercased() == "https" else { throw APIError.unreadable }
        NSWorkspace.shared.open(url)
        watchForPurchase()
    }

    func watchForPurchase() {
        purchaseWatch?.cancel()
        purchaseWatch = Task { [weak self] in
            let until = Date().addingTimeInterval(10 * 60)
            while !Task.isCancelled, Date() < until {
                try? await Task.sleep(nanoseconds: 4_000_000_000)
                guard let model = self else { return }
                await model.loadPlus()
                if model.plus.active { return }
            }
        }
    }

    func cancelSubscription() async throws {
        plus = try await authorized { client, token in try await client.cancelSubscription(accessToken: token) }
    }

    /// The welcome tour (Plus members, once ever) or the invitation (everyone else once Plus is paid, again five days after it was closed, never
    /// after "Don't show me again"). Not on a kids profile, and never twice in one launch.
    func showPlusPopupIfDue() {
        guard session != nil, !isKids, !popupShownThisLaunch, plusPopup == nil, detail == nil, sourcesFor == nil, playing == nil, !profilePickerOpen, selected == .home else { return }
        let defaults = UserDefaults.standard
        if plus.active {
            if PlusPopups.welcomeDue(seen: defaults.string(forKey: popupKey("WelcomeSeen")), shownThisLaunch: false) { plusPopup = .welcome }
        } else if plus.paywall {
            let snoozed = defaults.object(forKey: popupKey("InvitationSnoozedUntil")) as? Double
            if PlusPopups.invitationDue(never: defaults.bool(forKey: popupKey("InvitationNever")), snoozedUntil: snoozed.map { Date(timeIntervalSince1970: $0) }, shownThisLaunch: false) {
                plusPopup = .invitation
            }
        }
        if plusPopup != nil { popupShownThisLaunch = true }
    }

    /// Close or the main button: the welcome is never shown again; the invitation waits five days.
    func closePlusPopup(openSettings tab: SettingsTab? = nil) {
        let defaults = UserDefaults.standard
        let preview = plusPopupIsPreview
        plusPopupIsPreview = false
        switch preview ? nil : plusPopup {
        case .welcome: defaults.set(PlusPopups.welcomeID, forKey: popupKey("WelcomeSeen"))
        case .invitation: defaults.set(Date().addingTimeInterval(PlusPopups.snooze).timeIntervalSince1970, forKey: popupKey("InvitationSnoozedUntil"))
        case nil: break
        }
        plusPopup = nil
        if let tab { openSettings(tab) }
    }

    func dismissInvitationForever() {
        if !plusPopupIsPreview { UserDefaults.standard.set(true, forKey: popupKey("InvitationNever")) }
        plusPopupIsPreview = false
        plusPopup = nil
    }
}

