import AppKit
import SwiftUI

/// The web app's top bar: the logo on the left and every place, Settings last, in a rounded translucent pill in the middle.
struct TopNavBar: View {
    @EnvironmentObject private var model: AppModel
    /// The bar slides away as you scroll down a page and comes back when you scroll up or move the pointer to the top, as on the web app.
    @State private var hidden = false
    @State private var scrolled: CGFloat = 0
    @State private var monitor: Any?

    var body: some View {
        // Roomy first; as the window narrows the logo goes, then the pills tighten, so a name never wraps onto two lines.
        ViewThatFits(in: .horizontal) {
            bar(logo: true, fontSize: 14, padding: 16)
            bar(logo: false, fontSize: 14, padding: 16)
            bar(logo: false, fontSize: 13, padding: 10)
            bar(logo: false, fontSize: 12, padding: 6)
        }
        .padding(.horizontal, 36)
        .padding(.top, 14)
        .padding(.bottom, 26)
        .background(
            LinearGradient(colors: [Theme.background.opacity(0.9), Theme.background.opacity(0)], startPoint: .top, endPoint: .bottom)
        )
        .offset(y: hidden ? -100 : 0)
        .opacity(hidden ? 0 : 1)
        .allowsHitTesting(!hidden)
        .animation(.easeOut(duration: 0.3), value: hidden)
        .onChange(of: model.selected) { _ in
            scrolled = 0
            hidden = false
        }
        .onAppear { watchScrolling() }
        .onDisappear {
            if let monitor { NSEvent.removeMonitor(monitor) }
            monitor = nil
        }
    }

    private func watchScrolling() {
        guard monitor == nil else { return }
        NSApp.keyWindow?.acceptsMouseMovedEvents = true
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.scrollWheel, .mouseMoved]) { event in
            let type = event.type
            let delta = event.scrollingDeltaY
            let fromTop = (event.window?.contentView?.bounds.height ?? 0) - event.locationInWindow.y
            DispatchQueue.main.async {
                if type == .mouseMoved {
                    if fromTop <= 60 { hidden = false }
                } else if abs(delta) > 1 {
                    // Going down a page makes the content move up (a negative change).
                    scrolled = max(0, scrolled - delta)
                    if delta < 0, scrolled > 80 { hidden = true } else if delta > 0 || scrolled <= 20 { hidden = false }
                }
            }
            return event
        }
    }

    private func bar(logo: Bool, fontSize: CGFloat, padding: CGFloat) -> some View {
        HStack(alignment: .center) {
            if logo {
                LogoView(height: 30)
                    .fixedSize()
                    .frame(minWidth: 130, maxWidth: .infinity, alignment: .leading)
                    .onTapGesture { model.selected = .home }
            }

            HStack(spacing: 2) {
                ForEach(NavItem.allCases) { item in
                    NavPill(item: item, selected: model.selected == item, fontSize: fontSize, padding: padding) { model.selected = item }
                }
            }
            .padding(4)
            .fixedSize()
            .background(Capsule().fill(Color(hex: 0x141417).opacity(0.7)))
            .overlay(Capsule().stroke(Color.white.opacity(0.09), lineWidth: 1))

            // The right-hand side is where the profile picture goes once profiles are here.
            if logo { Color.clear.frame(minWidth: 130, maxWidth: .infinity, maxHeight: 1) }
        }
    }
}

private struct NavPill: View {
    let item: NavItem
    let selected: Bool
    var fontSize: CGFloat = 14
    var padding: CGFloat = 16
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Text(item.rawValue)
                .font(.system(size: fontSize, weight: selected ? .bold : .medium))
                .foregroundStyle(selected ? Theme.textPrimary : Theme.textSecondary)
                .lineLimit(1)
                .fixedSize()
                .padding(.horizontal, padding)
                .padding(.vertical, 7)
                .background(Capsule().fill(Color.white.opacity(selected ? 0.14 : (hovering ? 0.09 : 0))))
                .overlay(alignment: .bottom) {
                    // The line under the place you are on: the logo's blue-to-purple, as on the web app.
                    if selected {
                        GeometryReader { geo in
                            Capsule()
                                .fill(Theme.brandGradient)
                                .frame(width: geo.size.width * 0.44, height: 2)
                                .frame(width: geo.size.width, alignment: .center)
                        }
                        .frame(height: 2)
                        .padding(.bottom, 4)
                    }
                }
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}
