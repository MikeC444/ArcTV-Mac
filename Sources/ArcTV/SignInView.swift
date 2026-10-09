import SwiftUI

struct SignInView: View {
    @EnvironmentObject private var model: AppModel
    @State private var email = ""
    @State private var password = ""

    var body: some View {
        ZStack {
            // Two soft glows in the corners (blue top-left, violet top-right), like the web app's popups.
            RadialGradient(colors: [Theme.blue.opacity(0.22), .clear], center: .topLeading, startRadius: 0, endRadius: 520)
            RadialGradient(colors: [Theme.violet.opacity(0.18), .clear], center: .topTrailing, startRadius: 0, endRadius: 420)

            VStack(spacing: 20) {
                LogoView(height: 54)
                VStack(spacing: 6) {
                    Text("Welcome back")
                        .font(.system(size: 26, weight: .heavy))
                        .foregroundStyle(Theme.textPrimary)
                    Text("Sign in with your Arc TV account")
                        .foregroundStyle(Theme.textSecondary)
                }

                VStack(spacing: 10) {
                    field { TextField("Email", text: $email).textContentType(.username) }
                    field { SecureField("Password", text: $password).textContentType(.password).onSubmit { submit() } }
                    field { TextField("Server address (https://…)", text: $model.serverURL).disableAutocorrection(true) }
                }
                .frame(width: 340)

                if let error = model.signInError {
                    Text(error)
                        .foregroundStyle(Color(hex: 0xFF6B8A))
                        .font(.callout)
                        .multilineTextAlignment(.center)
                        .frame(width: 340)
                }

                Button(action: submit) {
                    Text(model.signingIn ? "Signing in…" : "Sign in")
                        .frame(width: 296)
                }
                .buttonStyle(BrandButtonStyle())
                .disabled(model.signingIn || email.isEmpty || password.isEmpty)
            }
            .padding(36)
            .background(RoundedRectangle(cornerRadius: 18).fill(Theme.elevated))
            .overlay(RoundedRectangle(cornerRadius: 18).stroke(Theme.divider, lineWidth: 1))
        }
    }

    private func field<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        content()
            .textFieldStyle(.plain)
            .font(.system(size: 15))
            .foregroundStyle(Theme.textPrimary)
            .padding(.horizontal, 14)
            .padding(.vertical, 11)
            .background(RoundedRectangle(cornerRadius: 10).fill(Theme.surface))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(Theme.divider, lineWidth: 1))
    }

    private func submit() {
        guard !email.isEmpty, !password.isEmpty, !model.signingIn else { return }
        Task { await model.signIn(email: email, password: password) }
    }
}
