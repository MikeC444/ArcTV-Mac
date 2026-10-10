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
    private var homeComplete = false
    private var homeGeneration = 0
    private var heroKey: String?
    private var trailers: [String: String] = [:]
    /// Which screen is open over the tabs: a title's details, then its sources, then the player (each sits on top of the one before).
    @Published var detail: MetaPreview?
    @Published var sourcesFor: PlayTarget?
    @Published var playing: PlayingItem?
    /// The poster whose actions menu (right-click) is open.
    @Published var cardMenu: CardMenuTarget?
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
    private var previousShown: Set<String> = Set(UserDefaults.standard.stringArray(forKey: "ArcTVPickedShown") ?? [])
    private var rememberedShown = false
    private let featureCache = FeatureCache.standard()
    @Published var signInError: String?
    @Published var signingIn = false

    /// The backend address: what the person typed on the sign-in screen last time, else the one baked into this build, else the default.
    @Published var serverURL: String {
        didSet { UserDefaults.standard.set(serverURL, forKey: Self.serverKey) }
    }

    private static let serverKey = "ArcTVServerURL"
    private static let removedKey = "ArcTVPickedRemoved"
    private static let posterKey = "ArcTVRatingPosters"
    private let store = SessionStore()

    init() {
        serverURL = AppInfo.resolveAPIBaseURL(saved: UserDefaults.standard.string(forKey: Self.serverKey), bundled: AppInfo.bundledAPIBaseURL)
        session = store.load()
        let saved = UserDefaults.standard.dictionary(forKey: Self.removedKey) as? [String: Double] ?? [:]
        pickedRemoved = saved.mapValues { Date(timeIntervalSince1970: $0) }
        ratingPosters = UserDefaults.standard.dictionary(forKey: Self.posterKey) as? [String: String] ?? [:]
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
        homeRaw = []
        heroTitles = []
        myList = nil
        continueItems = []
        addons = []
        allAddons = []
        settings = nil
        plus = .none
        ratings = [:]
        pickedResult = nil
        pickedKey = ""
        accountLoaded = false
        pickedTask?.cancel()
        detail = nil
        cardMenu = nil
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

        var sources = addons.compactMap { addon in addon.manifestJson.map { HomeSource(manifestURL: addon.manifestUrl, manifest: $0) } }
            .filter { !$0.catalogs.isEmpty }
        if sources.isEmpty, let manifest = try? await AddonClient().fetchManifest(AppInfo.cinemetaManifestURL) {
            sources = [HomeSource(manifestURL: AppInfo.cinemetaManifestURL, manifest: manifest)]
        }
        let seed = "\(session?.user.id ?? "guest")|\(HomeVariety.dayStamp())"
        await withTaskGroup(of: Void.self) { group in
            for source in sources {
                group.addTask { await HomeSections.load(source: source, seed: seed) { batch in await self.receive(batch, generation: generation) } }
            }
        }
        guard generation == homeGeneration else { return }
        homeComplete = true
        if homeRaw.isEmpty { home = .empty }
        pickHero()
        schedulePicked()
    }

    private func receive(_ batch: [HomeSection], generation: Int) {
        guard generation == homeGeneration else { return }
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

    func openCardMenu(_ item: MetaPreview, fromPicked: Bool = false) { cardMenu = CardMenuTarget(item: item, fromPicked: fromPicked) }

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

    var blockedGenres: Set<String> { Set(settings?.blockedGenres ?? []) }

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
            UserDefaults.standard.set(shown, forKey: "ArcTVPickedShown")
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
        UserDefaults.standard.set(ratingPosters, forKey: Self.posterKey)
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
        UserDefaults.standard.set(ratingPosters, forKey: Self.posterKey)
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
        UserDefaults.standard.set(live.mapValues { $0.timeIntervalSince1970 }, forKey: Self.removedKey)
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
                UserDefaults.standard.set(result.items.map(\.id), forKey: "ArcTVPickedShown")
            }
        }
    }
}
