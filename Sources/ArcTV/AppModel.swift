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
    @Published var home: HomeState = .idle
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

    func signOut() async {
        if let token = session?.accessToken, !serverURL.isEmpty {
            await AuthClient(baseURL: serverURL).logout(accessToken: token)
        }
        store.clear()
        session = nil
        home = .idle
        selected = .home
    }

    func loadHome() async {
        if case .loaded = home { return }
        home = .loading
        let year = Calendar.current.component(.year, from: Date())
        let rows = await HomeRows.load(specs: HomeRows.defaultRows(year: year), manifestURL: AppInfo.cinemetaManifestURL)
        home = rows.isEmpty ? .empty : .loaded(rows)
    }

    func reloadHome() async {
        home = .idle
        await loadHome()
    }
}
