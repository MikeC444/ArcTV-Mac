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

    var id: String { streamID }
    var streamID: String { ArcTVCore.streamID(titleID: title.id, season: season, episode: episode) }
    var heading: String { episodeTitle.map { "\(title.name) · \($0)" } ?? title.name }
}

/// A source the person picked: what to play and what to call it.
struct PlayingItem: Equatable {
    var url: URL
    var heading: String
    var sourceName: String
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
    @Published var myList: [MetaPreview]?
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
        addons = []
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
        if let found = try? await authorized({ client, token in try await client.addons(accessToken: token) }) {
            addons = found
        }
    }

    func loadMyList() async {
        myListError = nil
        do {
            let items = try await authorized { client, token in try await client.watchlist(accessToken: token) }
            myList = items.map(\.asPreview)
        } catch {
            myListError = (error as? APIError)?.errorDescription ?? "Couldn't load your list. Check your connection."
        }
    }

    func reloadHome() async {
        home = .idle
        await loadHome()
    }
}
