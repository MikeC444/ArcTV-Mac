import AppKit
import ArcTVCore
import SwiftUI

/// A profile's picture, from the sixteen embedded in the app.
struct ProfileAvatarView: View {
    let avatar: String
    private static var cache: [String: NSImage] = [:]

    private var image: NSImage? {
        let id = Avatars.resolve(avatar)
        if let cached = Self.cache[id] { return cached }
        guard let text = AvatarData.base64[id], let data = Data(base64Encoded: text), let image = NSImage(data: data) else { return nil }
        Self.cache[id] = image
        return image
    }

    var body: some View {
        if let image {
            Image(nsImage: image).resizable().aspectRatio(contentMode: .fill)
        } else {
            Color(hex: 0x26262B)
        }
    }
}

/// "Who's watching?": the account's profiles as tiles, with Add profile and Manage profiles. A locked profile asks for its PIN first.
struct ProfilePickerView: View {
    @EnvironmentObject private var model: AppModel
    @State private var managing = false
    @State private var locked: Profile?
    @State private var editing: EditTarget?
    @State private var error: String?
    @State private var busy = false

    enum EditTarget: Identifiable {
        case new
        case existing(Profile)
        var id: String { if case let .existing(profile) = self { return profile.id } else { return "new" } }
    }

    private var canAdd: Bool { model.plus.active && model.profiles.count < Profile.limit }

    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()
            VStack(spacing: 0) {
                HStack {
                    LogoView(height: 32)
                    Spacer()
                    Button("Switch account") { Task { await model.signOut() } }
                        .buttonStyle(.plain)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(Theme.textSecondary)
                }
                .padding(.horizontal, 44)
                .padding(.top, 28)

                Spacer(minLength: 20)
                VStack(spacing: 10) {
                    Text(managing ? "Manage profiles." : "Welcome back to ArcTV.")
                        .font(.system(size: 36, weight: .heavy))
                        .foregroundStyle(Theme.textPrimary)
                    Text(managing ? "Choose a profile to change." : "Who's watching today?")
                        .font(.system(size: 24, weight: .semibold))
                        .foregroundStyle(Theme.textPrimary)
                    Text(managing ? "Rename it, change its picture, lock it with a PIN or remove it." : "Choose your profile to pick up where you left off.")
                        .font(.system(size: 15))
                        .foregroundStyle(Theme.textSecondary)
                    if let error { Text(error).font(.system(size: 14)).foregroundStyle(Theme.coralText) }
                }
                .multilineTextAlignment(.center)

                HStack(alignment: .top, spacing: 26) {
                    ForEach(model.profiles) { profile in
                        tile(profile)
                    }
                    if canAdd { addTile }
                }
                .padding(.top, 36)

                HStack(spacing: 14) {
                    if model.plus.active {
                        Button { managing.toggle() } label: { Label(managing ? "Done" : "Manage profiles", systemImage: managing ? "checkmark" : "pencil") }
                            .buttonStyle(GlassButtonStyle())
                    }
                    if model.profiles.count >= Profile.limit { Text("An account can have up to \(Profile.limit) profiles.").font(.system(size: 12)).foregroundStyle(Theme.textTertiary) }
                }
                .padding(.top, 30)
                Spacer(minLength: 20)
            }

            if let profile = locked {
                PinPrompt(profile: profile, onCancel: { locked = nil }) { pin in
                    let message = await model.selectProfile(profile, pin: pin)
                    if message == nil { locked = nil }
                    return message
                }
            }
            if let target = editing {
                ProfileEditor(target: target) { editing = nil }
            }
        }
    }

    private func tile(_ profile: Profile) -> some View {
        let current = profile.id == model.activeProfileID
        return VStack(spacing: 10) {
            Button { tapped(profile) } label: {
                ProfileAvatarView(avatar: profile.avatar)
                    .frame(width: 150, height: 150)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                    .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.white.opacity(current && !managing ? 0.9 : 0), lineWidth: 3))
                    .overlay(alignment: .bottomTrailing) {
                        if profile.hasPin { badge("lock.fill") }
                    }
                    .overlay(alignment: .topTrailing) {
                        if managing { badge("pencil") }
                    }
            }
            .buttonStyle(.plain)
            .disabled(busy)
            Text(profile.name).font(.system(size: 16, weight: .semibold)).foregroundStyle(Theme.textPrimary).lineLimit(1).frame(width: 150)
            if profile.isKids { Text("Kids").font(.system(size: 12, weight: .semibold)).foregroundStyle(Theme.accent) }
        }
    }

    private var addTile: some View {
        VStack(spacing: 10) {
            Button { editing = .new } label: {
                Image(systemName: "plus")
                    .font(.system(size: 40, weight: .light))
                    .foregroundStyle(Theme.textSecondary)
                    .frame(width: 150, height: 150)
                    .background(RoundedRectangle(cornerRadius: 14).fill(Theme.surface))
            }
            .buttonStyle(.plain)
            Text("Add profile").font(.system(size: 16, weight: .semibold)).foregroundStyle(Theme.textSecondary)
        }
    }

    private func badge(_ symbol: String) -> some View {
        Image(systemName: symbol)
            .font(.system(size: 13, weight: .bold))
            .foregroundStyle(.white)
            .frame(width: 30, height: 30)
            .background(Circle().fill(Color.black.opacity(0.65)))
            .padding(8)
    }

    private func tapped(_ profile: Profile) {
        error = nil
        if managing {
            editing = .existing(profile)
        } else if profile.hasPin {
            locked = profile
        } else {
            busy = true
            Task {
                error = await model.selectProfile(profile, pin: nil)
                busy = false
            }
        }
    }
}

/// Asks for a locked profile's PIN. A wrong one keeps the box open with the reason.
private struct PinPrompt: View {
    let profile: Profile
    let onCancel: () -> Void
    let submit: (String) async -> String?
    @State private var pin = ""
    @State private var message: String?
    @State private var busy = false

    var body: some View {
        ZStack {
            Color.black.opacity(0.65).ignoresSafeArea().onTapGesture(perform: onCancel)
            VStack(spacing: 16) {
                ProfileAvatarView(avatar: profile.avatar).frame(width: 84, height: 84).clipShape(RoundedRectangle(cornerRadius: 12))
                Text("Enter the PIN for \(profile.name)").font(.system(size: 20, weight: .bold)).foregroundStyle(Theme.textPrimary)
                PinField(pin: $pin, onSubmit: go)
                if let message { Text(message).font(.system(size: 14)).foregroundStyle(Theme.coralText) }
                HStack(spacing: 12) {
                    Button("Cancel", action: onCancel).buttonStyle(GlassButtonStyle())
                    Button(busy ? "Checking…" : "Open", action: go).buttonStyle(BrandButtonStyle()).disabled(busy || !Profile.isValidPin(pin))
                }
            }
            .padding(30)
            .frame(width: 380)
            .background(RoundedRectangle(cornerRadius: 20).fill(Theme.elevated))
            .overlay(RoundedRectangle(cornerRadius: 20).stroke(Theme.divider, lineWidth: 1))
        }
    }

    private func go() {
        guard Profile.isValidPin(pin), !busy else { return }
        busy = true
        Task {
            message = await submit(pin)
            if message != nil { pin = "" }
            busy = false
        }
    }
}

/// The 4-digit PIN box every PIN prompt uses: digits only, masked.
struct PinField: View {
    @Binding var pin: String
    var placeholder = "••••"
    var onSubmit: () -> Void = {}

    var body: some View {
        SecureField(placeholder, text: Binding(get: { pin }, set: { pin = String($0.filter { $0.isASCII && $0.isNumber }.prefix(Profile.pinLength)) }))
            .textFieldStyle(.plain)
            .multilineTextAlignment(.center)
            .font(.system(size: 28, weight: .bold).monospacedDigit())
            .foregroundStyle(Theme.textPrimary)
            .frame(width: 160, height: 56)
            .background(RoundedRectangle(cornerRadius: 12).fill(Theme.surface))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.divider, lineWidth: 1))
            .onSubmit(onSubmit)
    }
}

/// Add or change a profile: its name, picture, Adult or Kids, and a PIN; remove it.
private struct ProfileEditor: View {
    @EnvironmentObject private var model: AppModel
    let target: ProfilePickerView.EditTarget
    let close: () -> Void
    @State private var name = ""
    @State private var avatar = Avatars.ids[0]
    @State private var kids = false
    @State private var lock = false
    @State private var newPin = ""
    @State private var currentPin = ""
    @State private var message: String?
    @State private var busy = false
    @State private var confirmingRemove = false

    private var existing: Profile? { if case let .existing(profile) = target { return profile } else { return nil } }

    var body: some View {
        ZStack {
            Color.black.opacity(0.65).ignoresSafeArea().onTapGesture(perform: close)
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text(existing == nil ? "Add profile" : "Edit profile").font(.system(size: 24, weight: .heavy)).foregroundStyle(Theme.textPrimary)

                    VStack(alignment: .leading, spacing: 6) {
                        Text("Name").font(.system(size: 13, weight: .semibold)).foregroundStyle(Theme.textSecondary)
                        TextField("Name", text: Binding(get: { name }, set: { name = String($0.prefix(Profile.nameMax)) }))
                            .textFieldStyle(.plain)
                            .font(.system(size: 16))
                            .foregroundStyle(Theme.textPrimary)
                            .padding(.horizontal, 14)
                            .frame(height: 44)
                            .background(RoundedRectangle(cornerRadius: 10).fill(Theme.surface))
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Picture").font(.system(size: 13, weight: .semibold)).foregroundStyle(Theme.textSecondary)
                        LazyVGrid(columns: Array(repeating: GridItem(.fixed(56), spacing: 10), count: 8), spacing: 10) {
                            ForEach(Avatars.ids, id: \.self) { id in
                                Button { avatar = id } label: {
                                    ProfileAvatarView(avatar: id)
                                        .frame(width: 56, height: 56)
                                        .clipShape(RoundedRectangle(cornerRadius: 10))
                                        .overlay(RoundedRectangle(cornerRadius: 10).stroke(avatar == id ? Theme.accent : .clear, lineWidth: 3))
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }

                    if existing?.isDefault != true {
                        VStack(alignment: .leading, spacing: 6) {
                            Toggle(isOn: $kids) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Kids profile").font(.system(size: 15, weight: .semibold)).foregroundStyle(Theme.textPrimary)
                                    Text("Hides horror, thriller, crime, war and mystery titles, and has no Settings.").font(.system(size: 12)).foregroundStyle(Theme.textSecondary)
                                }
                            }
                            .toggleStyle(.switch)
                            .tint(Theme.accent)
                        }
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        Toggle(isOn: $lock) {
                            Text("Lock with a PIN").font(.system(size: 15, weight: .semibold)).foregroundStyle(Theme.textPrimary)
                        }
                        .toggleStyle(.switch)
                        .tint(Theme.accent)
                        if lock {
                            HStack(spacing: 14) {
                                PinField(pin: $newPin, placeholder: existing?.hasPin == true ? "New PIN" : "PIN")
                                Text(existing?.hasPin == true ? "Leave empty to keep the PIN it has." : "4 digits.").font(.system(size: 12)).foregroundStyle(Theme.textSecondary)
                            }
                        }
                        if existing?.hasPin == true {
                            HStack(spacing: 14) {
                                PinField(pin: $currentPin, placeholder: "Current")
                                Text("The current PIN is needed to change or remove this profile.").font(.system(size: 12)).foregroundStyle(Theme.textSecondary)
                            }
                        }
                    }

                    if let message { Text(message).font(.system(size: 14)).foregroundStyle(Theme.coralText) }

                    HStack(spacing: 12) {
                        Button(busy ? "Saving…" : "Save", action: save).buttonStyle(BrandButtonStyle()).disabled(busy)
                        Button("Cancel", action: close).buttonStyle(GlassButtonStyle())
                        Spacer()
                        if let existing, !existing.isDefault {
                            Button("Remove profile") { confirmingRemove = true }
                                .buttonStyle(.plain)
                                .foregroundStyle(Theme.coralText)
                        }
                    }
                }
                .padding(28)
            }
            .frame(width: 560)
            .frame(maxHeight: 640)
            .fixedSize(horizontal: false, vertical: true)
            .background(RoundedRectangle(cornerRadius: 20).fill(Theme.elevated))
            .overlay(RoundedRectangle(cornerRadius: 20).stroke(Theme.divider, lineWidth: 1))
        }
        .onAppear {
            if let existing {
                name = existing.name
                avatar = Avatars.resolve(existing.avatar)
                kids = existing.isKids
                lock = existing.hasPin
            }
        }
        .alert("Remove this profile?", isPresented: $confirmingRemove) {
            Button("Remove", role: .destructive) { remove() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Its My List, Continue Watching, settings and Likes are deleted with it.")
        }
    }

    private func save() {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty { return message = "Give the profile a name." }
        if lock, !newPin.isEmpty, !Profile.isValidPin(newPin) { return message = "A PIN is 4 digits." }
        if lock, existing?.hasPin != true, newPin.isEmpty { return message = "Enter a 4-digit PIN, or turn the lock off." }
        if existing?.hasPin == true, !Profile.isValidPin(currentPin) { return message = "Enter the profile's current PIN to change it." }
        busy = true
        message = nil
        Task {
            do {
                if let existing {
                    var pin: String??
                    if !lock { pin = existing.hasPin ? .some(nil) : nil } else if !newPin.isEmpty { pin = .some(newPin) }
                    try await model.updateProfile(existing, name: trimmed, avatar: avatar, kind: kids ? "kids" : "adult", pin: pin, currentPin: existing.hasPin ? currentPin : nil)
                } else {
                    try await model.createProfile(name: trimmed, avatar: avatar, kind: kids ? "kids" : "adult", pin: lock ? newPin : nil)
                }
                close()
            } catch {
                message = (error as? APIError)?.errorDescription ?? "Something went wrong. Please try again."
            }
            busy = false
        }
    }

    private func remove() {
        guard let existing else { return }
        if existing.hasPin, !Profile.isValidPin(currentPin) {
            message = "Enter the profile's current PIN to remove it."
            return
        }
        busy = true
        Task {
            do {
                try await model.deleteProfile(existing, currentPin: existing.hasPin ? currentPin : nil)
                close()
            } catch {
                message = (error as? APIError)?.errorDescription ?? "Something went wrong. Please try again."
            }
            busy = false
        }
    }
}
