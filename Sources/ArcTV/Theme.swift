import AppKit
import SwiftUI

/// The app's colours, the web app's design tokens (client/src/styles/tokens.css), which are the Fire TV app's.
enum Theme {
    static let background = Color(hex: 0x08080A)
    static let elevated = Color(hex: 0x141417)
    static let surface = Color(hex: 0x1C1C20)
    static let surfaceHigh = Color(hex: 0x26262B)

    static let cyan = Color(hex: 0x19E6FF)
    static let blue = Color(hex: 0x2F80FF)
    static let violet = Color(hex: 0x9B5CFF)
    static let accent = cyan
    static let coral = Color(hex: 0xFF3D68)
    /// The tick on a title you have watched.
    static let watched = Color(hex: 0x2ECC71)
    /// Coral for text on raised surfaces (readable; the brand coral is not).
    static let coralText = Color(hex: 0xFF6B8A)

    static let textPrimary = Color(hex: 0xF6F6F8)
    static let textSecondary = Color(hex: 0xAFAFB8)
    static let textTertiary = Color(hex: 0x92929C)
    static let divider = Color.white.opacity(0.122)

    /// The logo's cyan, blue, violet run.
    static let brandGradient = LinearGradient(colors: [cyan, blue, violet], startPoint: .leading, endPoint: .trailing)
}

extension Color {
    init(hex: UInt32) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: 1
        )
    }
}

/// The Arc TV logo image, embedded in the app.
struct LogoView: View {
    var height: CGFloat = 30

    private static let image: NSImage? = Data(base64Encoded: LogoData.base64).flatMap { NSImage(data: $0) }

    var body: some View {
        if let image = Self.image {
            Image(nsImage: image)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(height: height)
        } else {
            Text("ArcTV")
                .font(.system(size: height * 0.8, weight: .heavy))
                .foregroundStyle(Theme.brandGradient)
        }
    }
}

/// A filled button in the brand gradient with dark text (the web app's primary button).
struct BrandButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 15, weight: .bold))
            .foregroundStyle(Color(hex: 0x04161A))
            .padding(.horizontal, 22)
            .padding(.vertical, 10)
            .background(Theme.brandGradient, in: Capsule())
            .opacity(isEnabled ? (configuration.isPressed ? 0.8 : 1) : 0.4)
    }
}

/// A translucent pill button (the web app's secondary button).
struct GlassButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 15, weight: .semibold))
            .foregroundStyle(Theme.textPrimary)
            .padding(.horizontal, 22)
            .padding(.vertical, 10)
            .background(Color.white.opacity(configuration.isPressed ? 0.22 : 0.14), in: Capsule())
            .opacity(isEnabled ? 1 : 0.4)
    }
}

/// A white pill with dark text: the web app's main "Play" button.
struct LightButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 15, weight: .bold))
            .foregroundStyle(.black)
            .padding(.horizontal, 26)
            .frame(height: 48)
            .background(Color.white.opacity(configuration.isPressed ? 0.8 : 1), in: Capsule())
            .opacity(isEnabled ? 1 : 0.4)
    }
}

/// A round translucent icon button (the web app's icon button); `on` tints it when what it stands for is set.
struct RoundIconButton: View {
    let icon: String
    var on = false
    let help: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(on ? Theme.cyan : Theme.textPrimary)
                .frame(width: 48, height: 48)
                .background(Circle().fill(on ? Theme.cyan.opacity(0.2) : Color.white.opacity(0.14)))
                .overlay(Circle().stroke(on ? Theme.cyan : .clear, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .help(help)
    }
}
