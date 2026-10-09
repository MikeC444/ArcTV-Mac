import SwiftUI

/// The web app's top bar: the logo on the left, the places in a rounded translucent pill in the middle, and who is signed in on the right.
struct TopNavBar: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        HStack(alignment: .center) {
            LogoView(height: 30)
                .frame(maxWidth: .infinity, alignment: .leading)
                .onTapGesture { model.selected = .home }

            HStack(spacing: 2) {
                ForEach(NavItem.allCases.filter { $0 != .settings }) { item in
                    NavPill(item: item, selected: model.selected == item) { model.selected = item }
                }
            }
            .padding(4)
            .background(Capsule().fill(Color(hex: 0x141417).opacity(0.7)))
            .overlay(Capsule().stroke(Color.white.opacity(0.09), lineWidth: 1))

            HStack(spacing: 10) {
                Spacer()
                Button {
                    model.selected = .settings
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "gearshape.fill")
                        Text(model.session?.user.displayName ?? model.session?.user.email ?? "Account")
                            .lineLimit(1)
                            .frame(maxWidth: 140, alignment: .leading)
                    }
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(model.selected == .settings ? Theme.textPrimary : Theme.textSecondary)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(Capsule().fill(Color.white.opacity(model.selected == .settings ? 0.16 : 0.08)))
                }
                .buttonStyle(.plain)
            }
            .frame(maxWidth: .infinity, alignment: .trailing)
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
