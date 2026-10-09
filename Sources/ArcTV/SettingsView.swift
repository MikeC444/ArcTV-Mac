import ArcTVCore
import SwiftUI

/// Stage 1's Settings: who is signed in, which server, the version, and Sign out. The real tabs come later.
struct SettingsView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text("Settings")
                    .font(.system(size: 34, weight: .heavy))
                    .foregroundStyle(Theme.textPrimary)

                card {
                    row("Signed in as", model.session?.user.email ?? "-")
                    Divider().overlay(Theme.divider)
                    row("Server", model.serverURL.isEmpty ? "-" : model.serverURL)
                    Divider().overlay(Theme.divider)
                    row("Version", AppInfo.version)
                }

                HStack(spacing: 12) {
                    Button { Task { await model.reloadHome() } } label: { Label("Refresh Home", systemImage: "arrow.clockwise") }
                        .buttonStyle(GlassButtonStyle())
                    Button { Task { await model.signOut() } } label: { Label("Sign out", systemImage: "rectangle.portrait.and.arrow.right") }
                        .buttonStyle(GlassButtonStyle())
                }
            }
            .frame(maxWidth: 560, alignment: .leading)
            .padding(.horizontal, 44)
            .padding(.top, 96)
            .padding(.bottom, 40)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func card<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) { content() }
            .padding(18)
            .background(RoundedRectangle(cornerRadius: 14).fill(Theme.elevated))
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(Theme.divider, lineWidth: 1))
    }

    private func row(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label).foregroundStyle(Theme.textSecondary)
            Spacer()
            Text(value).foregroundStyle(Theme.textPrimary).lineLimit(1).truncationMode(.middle)
        }
        .font(.system(size: 14))
    }
}
