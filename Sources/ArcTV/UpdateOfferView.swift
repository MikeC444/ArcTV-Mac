import AppKit
import ArcTVCore
import SwiftUI

/// "A new version is out": what is new, with Download, Later and "Skip this version".
struct UpdateOfferView: View {
    @EnvironmentObject private var model: AppModel
    let offer: ReleaseInfo

    var body: some View {
        ZStack {
            Color.black.opacity(0.65).ignoresSafeArea().onTapGesture { model.dismissUpdate(skip: false) }
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 8) {
                    LogoView(height: 26)
                    Spacer()
                    Button { model.dismissUpdate(skip: false) } label: {
                        Image(systemName: "xmark").font(.system(size: 12, weight: .bold)).foregroundStyle(Theme.textSecondary)
                            .frame(width: 28, height: 28).background(Circle().fill(Theme.surfaceHigh))
                    }
                    .buttonStyle(.plain)
                }
                Text("Arc TV \(offer.version) is out").font(.system(size: 26, weight: .heavy)).foregroundStyle(Theme.textPrimary)
                Text("You have \(AppInfo.version). Here is what is new:").font(.system(size: 14)).foregroundStyle(Theme.textSecondary)
                ScrollView {
                    Text(offer.notes.isEmpty ? "Improvements and fixes." : offer.notes)
                        .font(.system(size: 14))
                        .foregroundStyle(Theme.textPrimary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                }
                .frame(maxHeight: 240)
                .padding(14)
                .background(RoundedRectangle(cornerRadius: 12).fill(Theme.surface))
                HStack(spacing: 12) {
                    Button {
                        if let url = offer.downloadURL ?? offer.pageURL { NSWorkspace.shared.open(url) }
                        model.dismissUpdate(skip: false)
                    } label: { Label("Download", systemImage: "arrow.down.circle") }
                        .buttonStyle(BrandButtonStyle())
                    Button { model.dismissUpdate(skip: false) } label: { Text("Later") }
                        .buttonStyle(GlassButtonStyle())
                    Spacer()
                    Button("Skip this version") { model.dismissUpdate(skip: true) }
                        .buttonStyle(.plain)
                        .font(.system(size: 13))
                        .foregroundStyle(Theme.textTertiary)
                        .underline()
                }
            }
            .padding(26)
            .frame(width: 520)
            .background(RoundedRectangle(cornerRadius: 20).fill(Theme.elevated))
            .overlay(RoundedRectangle(cornerRadius: 20).stroke(Theme.divider, lineWidth: 1))
            .shadow(color: .black.opacity(0.6), radius: 30, y: 12)
        }
    }
}
