import SwiftUI

/// The web app's top bar: the logo on the left and every place, Settings last, in a rounded translucent pill in the middle.
struct TopNavBar: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        HStack(alignment: .center) {
            LogoView(height: 30)
                .frame(maxWidth: .infinity, alignment: .leading)
                .onTapGesture { model.selected = .home }

            HStack(spacing: 2) {
                ForEach(NavItem.allCases) { item in
                    NavPill(item: item, selected: model.selected == item) { model.selected = item }
                }
            }
            .padding(4)
            .background(Capsule().fill(Color(hex: 0x141417).opacity(0.7)))
            .overlay(Capsule().stroke(Color.white.opacity(0.09), lineWidth: 1))

            // The right-hand side is where the profile picture goes once profiles are here.
            Color.clear.frame(maxWidth: .infinity, maxHeight: 1)
        }
        .padding(.horizontal, 36)
        .padding(.top, 14)
        .padding(.bottom, 26)
        .background(
            LinearGradient(colors: [Theme.background.opacity(0.9), Theme.background.opacity(0)], startPoint: .top, endPoint: .bottom)
        )
    }
}

private struct NavPill: View {
    let item: NavItem
    let selected: Bool
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Text(item.rawValue)
                .font(.system(size: 14, weight: selected ? .bold : .medium))
                .foregroundStyle(selected ? Theme.textPrimary : Theme.textSecondary)
                .padding(.horizontal, 16)
                .padding(.vertical, 7)
                .background(Capsule().fill(Color.white.opacity(selected ? 0.18 : (hovering ? 0.09 : 0))))
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}
