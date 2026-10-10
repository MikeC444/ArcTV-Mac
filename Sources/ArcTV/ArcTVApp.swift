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

/// The signed-in app: the top bar over whichever place is selected, with a title's page, its sources and the player opening over it.
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
            .task {
                await model.bootstrap()
            }

            TopNavBar()

            if let item = model.detail {
                DetailView(preview: item)
                    .id(item.id)
                    .transition(.opacity)
            }
            if let target = model.sourcesFor {
                SourcesView(target: target)
                    .id(target.id)
                    .transition(.opacity)
            }
            if model.guideOpen {
                SetupGuideView()
                    .transition(.opacity)
            }
            if let playing = model.playing {
                Group {
                    switch model.playerEngine {
                    case .mpv: MPVPlayerScreen(item: playing)
                    case .builtIn: BuiltInPlayerView(item: playing)
                    }
                }
                .transition(.opacity)
            }
            if let popup = model.plusPopup {
                PlusPopupView(popup: popup)
                    .transition(.opacity)
            }
            if model.profilePickerOpen {
                ProfilePickerView()
                    .transition(.opacity)
            }
            if !model.online {
                OfflineBanner()
                    .frame(maxHeight: .infinity, alignment: .bottom)
                    .allowsHitTesting(false)
            }
            if let menu = model.cardMenu {
                CardMenuView(target: menu)
                    .transition(.opacity)
            }
        }
        .task(id: "\(model.selected.rawValue)|\(model.home == .loaded)|\(model.plus.active)|\(model.plus.paywall)") {
            guard model.selected == .home, model.home == .loaded else { return }
            try? await Task.sleep(nanoseconds: 4_000_000_000)
            guard !Task.isCancelled else { return }
            model.showPlusPopupIfDue()
        }
        .animation(.easeOut(duration: 0.15), value: model.cardMenu)
        .animation(.easeOut(duration: 0.18), value: model.detail?.id)
        .animation(.easeOut(duration: 0.18), value: model.sourcesFor?.id)
        .animation(.easeOut(duration: 0.18), value: model.playing != nil)
    }
}
