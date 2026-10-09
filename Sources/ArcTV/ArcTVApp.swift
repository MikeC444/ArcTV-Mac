import AppKit
import ArcTVCore
import SwiftUI

@main
struct ArcTVApp: App {
    @StateObject private var model = AppModel()

    init() {
        // Run from Xcode or `swift run` the program is not inside an .app bundle; without this its window can open without keyboard focus.
        NSApplication.shared.setActivationPolicy(.regular)
        NSApplication.shared.activate(ignoringOtherApps: true)
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(model)
                .frame(minWidth: 1000, minHeight: 680)
                .preferredColorScheme(.dark)
        }
        .windowStyle(.hiddenTitleBar)
    }
}

struct RootView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()
            if model.session == nil {
                SignInView()
            } else {
                MainView()
            }
        }
    }
}

/// The signed-in app: the top bar over whichever place is selected.
struct MainView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        ZStack(alignment: .top) {
            Group {
                switch model.selected {
                case .home: HomeView()
                case .movies: BrowseView(title: "Movies", type: "movie")
                case .tv: BrowseView(title: "TV Shows", type: "series")
                case .search: SearchView()
                case .myList: MyListView()
                case .settings: SettingsView()
                }
            }
            .task { await model.loadHome() }

            TopNavBar()
        }
    }
}
