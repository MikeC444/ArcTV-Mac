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
                .frame(minWidth: 960, minHeight: 640)
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
                HomeView()
            }
        }
    }
}
