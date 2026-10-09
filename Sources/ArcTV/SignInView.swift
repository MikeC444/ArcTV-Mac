import SwiftUI

struct SignInView: View {
    @EnvironmentObject private var model: AppModel
    @State private var email = ""
    @State private var password = ""

    var body: some View {
        VStack(spacing: 18) {
            Text("Arc TV")
                .font(.system(size: 40, weight: .heavy))
                .foregroundStyle(Theme.accent)
            Text("Sign in with your Arc TV account")
                .foregroundStyle(Theme.textSecondary)

            VStack(spacing: 10) {
                TextField("Email", text: $email)
                    .textContentType(.username)
                SecureField("Password", text: $password)
                    .textContentType(.password)
                    .onSubmit { submit() }
                TextField("Server address (https://…)", text: $model.serverURL)
                    .disableAutocorrection(true)
            }
            .textFieldStyle(.roundedBorder)
            .frame(width: 320)

            if let error = model.signInError {
                Text(error)
                    .foregroundStyle(Color.red.opacity(0.9))
                    .font(.callout)
                    .multilineTextAlignment(.center)
                    .frame(width: 320)
            }

            Button(action: submit) {
                Text(model.signingIn ? "Signing in…" : "Sign in")
                    .frame(width: 320)
            }
            .buttonStyle(.borderedProminent)
            .tint(Theme.accent)
            .controlSize(.large)
            .disabled(model.signingIn || email.isEmpty || password.isEmpty)
        }
        .padding(40)
    }

    private func submit() {
        guard !email.isEmpty, !password.isEmpty, !model.signingIn else { return }
        Task { await model.signIn(email: email, password: password) }
    }
}
