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
        // The Dock icon: from the app bundle when packaged; this also covers a run from Xcode, which has no bundle to take it from.
        if let data = Data(base64Encoded: AppIconData.base64), let icon = NSImage(data: data) {
            NSApplication.shared.applicationIconImage = icon
        }
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
            if let offer = model.updateOffer {
                UpdateOfferView(offer: offer)
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
        .task(id: model.home == .loaded) {
            guard model.home == .loaded else { return }
            if AppModel.plusPopupDemo {
                try? await Task.sleep(nanoseconds: 3_000_000_000)
                if !Task.isCancelled, model.plusPopup == nil { model.previewPlusPopup(.invitation) }
                return
            }
            try? await Task.sleep(nanoseconds: 6_000_000_000)
            guard !Task.isCancelled else { return }
            await model.checkForUpdate()
        }
        .onAppear { CardHover.start { target in Task { @MainActor in model.openCardMenu(target.item, fromPicked: target.fromPicked) } } }
        .animation(.easeOut(duration: 0.15), value: model.cardMenu)
        .animation(.easeOut(duration: 0.18), value: model.detail?.id)
        .animation(.easeOut(duration: 0.18), value: model.sourcesFor?.id)
        .animation(.easeOut(duration: 0.18), value: model.playing != nil)
    }
}
