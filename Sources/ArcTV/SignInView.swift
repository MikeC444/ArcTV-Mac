import AppKit
import ArcTVCore
import CoreImage
import SwiftUI

/// The sign-in pages, laid out like the web app's: the living-room photo on the right fading into the page, and on the left the logo, "Your
/// Entertainment, Your Way" and Log In / Sign Up, then the email and password form, or a QR code to finish signing in on a phone.
struct SignInView: View {
    @EnvironmentObject private var model: AppModel
    enum Step { case start, form, qr }
    @State private var step: Step = .start
    @State private var registering = false

    private static let hero: NSImage? = Data(base64Encoded: AuthHeroData.base64).flatMap { NSImage(data: $0) }

    var body: some View {
        ZStack(alignment: .leading) {
            Theme.background
            if let hero = Self.hero {
                Image(nsImage: hero)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .trailing)
                    .clipped()
            }
            GeometryReader { geo in
                LinearGradient(stops: [.init(color: Theme.background, location: 0), .init(color: Theme.background, location: 0.5), .init(color: Theme.background.opacity(0), location: 1)],
                               startPoint: .leading, endPoint: .trailing)
                    .frame(width: geo.size.width, height: geo.size.height)
            }

            VStack(alignment: .leading, spacing: 20) {
                LogoView(height: 32).padding(.bottom, 20)
                switch step {
                case .start: start
                case .form: SignInForm(registering: $registering) { step = .start }
                case .qr: QRSignInPanel { step = .start }
                }
            }
            .frame(width: 420, alignment: .leading)
            .padding(.horizontal, 56)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var start: some View {
        VStack(alignment: .leading, spacing: 20) {
            if let notice = model.signInError {
                Text(notice)
                    .font(.system(size: 14))
                    .foregroundStyle(Theme.textPrimary)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(RoundedRectangle(cornerRadius: 10).fill(Theme.coral.opacity(0.14)))
                    .overlay(RoundedRectangle(cornerRadius: 10).stroke(Theme.coral.opacity(0.4), lineWidth: 1))
            }
            (Text("Your Entertainment,\n").foregroundColor(Theme.textPrimary) + Text("Your Way").foregroundColor(Theme.cyan))
                .font(.system(size: 40, weight: .heavy))
                .lineSpacing(2)
            Text("Stream the latest movies, TV shows and more. Create an account to get the full experience.")
                .font(.system(size: 16))
                .foregroundStyle(Theme.textSecondary)
            VStack(spacing: 16) {
                AuthButton(title: "Log In", icon: "person.fill", filled: true) {
                    model.signInError = nil
                    registering = false
                    step = .form
                }
                AuthButton(title: "Sign Up", icon: "plus", filled: false) {
                    model.signInError = nil
                    registering = true
                    step = .form
                }
            }
            .padding(.top, 20)
            Button {
                model.signInError = nil
                step = .qr
            } label: {
                Label("Scan a QR code to sign in from your phone", systemImage: "qrcode")
                    .font(.system(size: 14))
                    .foregroundStyle(Theme.textSecondary)
            }
            .buttonStyle(.plain)
        }
    }
}

/// Signing in with a phone: this Mac shows a QR code, the phone opens the page it points to and signs in, and this Mac is signed in too.
private struct QRSignInPanel: View {
    @EnvironmentObject private var model: AppModel
    let back: () -> Void
    @State private var image: NSImage?
    @State private var message: String?
    @State private var attempt = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Sign in with your phone").font(.system(size: 26, weight: .bold)).foregroundStyle(Theme.textPrimary)
            Text("Point your phone's camera at this code, open the link and sign in there. This Mac signs in by itself.")
                .font(.system(size: 14)).foregroundStyle(Theme.textSecondary)
            ZStack {
                RoundedRectangle(cornerRadius: 14).fill(Color.white)
                if let image {
                    Image(nsImage: image).interpolation(.none).resizable().scaledToFit().padding(14)
                } else if message == nil {
                    ProgressView()
                }
            }
            .frame(width: 240, height: 240)
            if let message { Text(message).font(.system(size: 13)).foregroundStyle(Theme.coralText) }
            HStack(spacing: 12) {
                if message != nil {
                    Button { attempt += 1 } label: { Label("New code", systemImage: "arrow.clockwise") }.buttonStyle(GlassButtonStyle())
                }
                Button(action: back) { Label("Back", systemImage: "arrow.left") }.buttonStyle(GlassButtonStyle())
            }
        }
        .task(id: attempt) { await run() }
    }

    private func run() async {
        image = nil
        message = nil
        let address = model.serverURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard address.lowercased().hasPrefix("http") else {
            message = "Enter the server address first (Log In > Server address)."
            return
        }
        let client = AuthClient(baseURL: address)
        do {
            let created = try await client.createQRSession(deviceId: DeviceIdentity.id, deviceName: DeviceIdentity.name)
            image = Self.qrImage(created.activationUrl)
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 2_000_000_000)
                if Task.isCancelled { return }
                switch try await client.pollQRSession(token: created.token) {
                case .waiting: continue
                case .expired:
                    image = nil
                    message = "This code ran out. Make a new one."
                    return
                case let .signedIn(session):
                    model.finishQRSignIn(session)
                    return
                }
            }
        } catch {
            image = nil
            message = "Couldn't reach the server. Check the address and your connection."
        }
    }

    static func qrImage(_ text: String) -> NSImage? {
        guard let filter = CIFilter(name: "CIQRCodeGenerator") else { return nil }
        filter.setValue(Data(text.utf8), forKey: "inputMessage")
        filter.setValue("M", forKey: "inputCorrectionLevel")
        guard let output = filter.outputImage?.transformed(by: CGAffineTransform(scaleX: 10, y: 10)) else { return nil }
        let rep = NSCIImageRep(ciImage: output)
        let result = NSImage(size: rep.size)
        result.addRepresentation(rep)
        return result
    }
}

private struct SignInForm: View {
    @EnvironmentObject private var model: AppModel
    @Binding var registering: Bool
    let back: () -> Void
    @State private var email = ""
    @State private var password = ""
    @State private var displayName = ""
    @State private var visible = false
    @State private var showServer = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(registering ? "Create Your Account" : "Log In")
                .font(.system(size: 26, weight: .bold))
                .foregroundStyle(Theme.textPrimary)
            AuthField(placeholder: "Email", text: $email)
            if registering { AuthField(placeholder: "Display name (optional)", text: $displayName) }
            AuthField(placeholder: "Password", text: $password, secure: !visible, onSubmit: submit)
            smallButton(visible ? "Hide Password" : "Show Password", icon: visible ? "eye.slash" : "eye") { visible.toggle() }

            if let error = model.signInError {
                Text(error).font(.system(size: 14)).foregroundStyle(Theme.coralText).frame(maxWidth: .infinity)
            }
            TimelineView(.periodic(from: .now, by: 1)) { context in
                let left = max(0, Int((model.waitUntil?.timeIntervalSince(context.date) ?? 0).rounded(.up)))
                VStack(spacing: 14) {
                    if left > 0 {
                        Text("Too many sign-in attempts right now. Arc TV only accepts a few a minute. You can try again in \(left) s.")
                            .font(.system(size: 14))
                            .foregroundStyle(Theme.coralText)
                    }
                    AuthButton(title: left > 0 ? "Try again in \(left) s" : (registering ? "Create Account" : "Log In"), icon: registering ? "plus" : "person.fill", filled: true, action: submit)
                        .disabled(model.signingIn || left > 0)
                        .opacity(model.signingIn || left > 0 ? 0.5 : 1)
                }
            }
            if model.signingIn {
                HStack(spacing: 10) {
                    ProgressView().controlSize(.small)
                    Text(registering ? "Creating account…" : "Signing in…").font(.system(size: 14)).foregroundStyle(Theme.textSecondary)
                }
                .frame(maxWidth: .infinity)
            }
            smallButton(registering ? "Already have an account? Log in" : "New here? Create an account", icon: "chevron.right") {
                registering.toggle()
                model.signInError = nil
            }
            smallButton("Back", icon: "arrow.left", action: back)

            Button(showServer ? "Hide server address" : "Server address") { showServer.toggle() }
                .buttonStyle(.plain)
                .font(.system(size: 12))
                .foregroundStyle(Theme.textTertiary)
                .padding(.top, 10)
            if showServer { AuthField(placeholder: "Server address (https://…)", text: $model.serverURL) }
        }
    }

    private func submit() {
        guard !model.signingIn else { return }
        Task { await model.signIn(email: email, password: password, register: registering, displayName: displayName) }
    }

    private func smallButton(_ title: String, icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: icon).font(.system(size: 12, weight: .semibold))
                Text(title).font(.system(size: 13, weight: .medium))
            }
            .foregroundStyle(Theme.textPrimary)
            .padding(.horizontal, 16)
            .frame(height: 36)
            .background(RoundedRectangle(cornerRadius: 10).fill(Color.white.opacity(0.12)))
        }
        .buttonStyle(.plain)
    }
}

/// The web app's big full-width button: an icon and a label on the left, a chevron on the right; the main one is filled with the logo's colours.
private struct AuthButton: View {
    let title: String
    let icon: String
    let filled: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: icon).font(.system(size: 18))
                Text(title).font(.system(size: 16, weight: .bold))
                Spacer()
                Image(systemName: "chevron.right").font(.system(size: 14, weight: .semibold))
            }
            .foregroundStyle(filled ? Color(hex: 0x08080A) : Theme.textPrimary)
            .padding(.horizontal, 22)
            .frame(maxWidth: .infinity, minHeight: 52)
            .background(RoundedRectangle(cornerRadius: 12).fill(filled ? AnyShapeStyle(Theme.brandGradient) : AnyShapeStyle(Color.white.opacity(0.12))))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

/// The web app's filled text field: a raised box with a line under it that turns cyan while you type.
private struct AuthField: View {
    let placeholder: String
    @Binding var text: String
    var secure = false
    var onSubmit: () -> Void = {}
    @FocusState private var focused: Bool

    var body: some View {
        Group {
            if secure {
                SecureField(placeholder, text: $text).onSubmit(onSubmit)
            } else {
                TextField(placeholder, text: $text).onSubmit(onSubmit).disableAutocorrection(true)
            }
        }
        .textFieldStyle(.plain)
        .focused($focused)
        .font(.system(size: 16))
        .foregroundStyle(Theme.textPrimary)
        .padding(.horizontal, 16)
        .frame(height: 56)
        .background(RoundedRectangle(cornerRadius: 4).fill(Theme.surface))
        .overlay(alignment: .bottom) {
            Rectangle().fill(focused ? Theme.accent : Theme.textTertiary).frame(height: focused ? 2 : 1)
        }
    }
}
