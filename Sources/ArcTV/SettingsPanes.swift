import ArcTVCore
import SwiftUI

/// Settings > Addons: what is installed on the account, switch each on or off, remove it, or add one from a link.
struct AddonsPane: View {
    @EnvironmentObject private var model: AppModel
    @State private var link = ""
    @State private var working = false
    @State private var message: String?
    @State private var messageIsError = false
    @State private var removing: SyncedAddon?

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Addons give Arc TV its streams (and catalogues). They are kept on your account, so they follow you to every device.")
                .font(.system(size: 13))
                .foregroundStyle(Theme.textSecondary)

            VStack(alignment: .leading, spacing: 10) {
                Text("Add an addon").font(.system(size: 15, weight: .bold)).foregroundStyle(Theme.textPrimary)
                HStack(spacing: 10) {
                    TextField("Paste the addon's link (https:// or stremio://)", text: $link)
                        .textFieldStyle(.plain)
                        .font(.system(size: 14))
                        .foregroundStyle(Theme.textPrimary)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 9)
                        .background(RoundedRectangle(cornerRadius: 10).fill(Theme.surface))
                        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Theme.divider, lineWidth: 1))
                        .onSubmit { add() }
                    Button { add() } label: { Text(working ? "Adding…" : "Add") }
                        .buttonStyle(BrandButtonStyle())
                        .disabled(working || link.trimmingCharacters(in: .whitespaces).isEmpty)
                }
                if let message {
                    Text(message).font(.system(size: 13)).foregroundStyle(messageIsError ? Color(hex: 0xFF6B8A) : Theme.accent)
                }
            }
            .padding(16)
            .background(RoundedRectangle(cornerRadius: 14).fill(Theme.elevated))
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(Theme.divider, lineWidth: 1))

            if model.allAddons.isEmpty {
                Text("No addons yet.").foregroundStyle(Theme.textSecondary)
            } else {
                VStack(spacing: 10) {
                    ForEach(model.allAddons, id: \.manifestUrl) { addon in
                        AddonRow(addon: addon, onRemove: { removing = addon })
                    }
                }
            }
        }
        .task { await model.loadAddons() }
        .alert("Remove this addon?", isPresented: Binding(get: { removing != nil }, set: { if !$0 { removing = nil } }), presenting: removing) { addon in
            Button("Remove", role: .destructive) { Task { await model.removeAddon(addon) } }
            Button("Cancel", role: .cancel) {}
        } message: { addon in
            Text("\(addon.name) is taken off your account, so it goes from every device.")
        }
    }

    private func add() {
        let text = link.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !working else { return }
        working = true
        message = nil
        Task {
            do {
                let install = try await AddonInstall.fetch(text)
                try await model.installAddon(install)
                message = "Added \(install.name)."
                messageIsError = false
                link = ""
            } catch {
                message = "That link didn't give an addon. Check it and try again."
                messageIsError = true
            }
            working = false
        }
    }
}

private struct AddonRow: View {
    @EnvironmentObject private var model: AppModel
    let addon: SyncedAddon
    let onRemove: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text(addon.name).font(.system(size: 15, weight: .bold)).foregroundStyle(addon.enabled ? Theme.textPrimary : Theme.textTertiary)
                    if let version = addon.manifestJson?.version {
                        Text("v\(version)").font(.system(size: 12)).foregroundStyle(Theme.textTertiary)
                    }
                }
                if let description = addon.manifestJson?.description {
                    Text(description).font(.system(size: 12)).foregroundStyle(Theme.textSecondary).lineLimit(2)
                }
                Text(provides).font(.system(size: 12)).foregroundStyle(Theme.textTertiary)
            }
            Spacer(minLength: 0)
            Toggle("", isOn: Binding(get: { addon.enabled }, set: { value in Task { await model.setAddon(addon, enabled: value) } }))
                .labelsHidden()
                .toggleStyle(.switch)
                .tint(Theme.accent)
            Button(action: onRemove) {
                Image(systemName: "trash").foregroundStyle(Theme.textSecondary)
            }
            .buttonStyle(.plain)
            .help("Remove this addon")
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 14).fill(Theme.elevated))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Theme.divider, lineWidth: 1))
    }

    /// "Catalogues, Streams" from the manifest's resources.
    private var provides: String {
        let names = (addon.manifestJson?.resources ?? []).map(\.name).filter { !$0.isEmpty }
        let pretty = names.map { $0.prefix(1).uppercased() + $0.dropFirst() + (($0 == "stream" || $0 == "catalog" || $0 == "meta" || $0 == "subtitles") ? "s" : "") }
        return pretty.isEmpty ? "Provides: not stated" : "Provides: " + Array(NSOrderedSet(array: pretty)).compactMap { $0 as? String }.joined(separator: ", ")
    }
}

/// Settings > Blocked Genres: genres hidden everywhere (Home, Movies, TV Shows, Search), kept on the account.
struct BlockedGenresPane: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Pick the genres you never want to see. Titles in them are hidden on every device.")
                .font(.system(size: 13))
                .foregroundStyle(Theme.textSecondary)
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 130), spacing: 10, alignment: .leading)], alignment: .leading, spacing: 10) {
                ForEach(Genres.all, id: \.self) { genre in
                    let blocked = model.blockedGenres.contains { $0.caseInsensitiveCompare(genre) == .orderedSame }
                    Button { Task { await model.setGenre(genre, blocked: !blocked) } } label: {
                        HStack(spacing: 8) {
                            Image(systemName: blocked ? "nosign" : "circle")
                                .foregroundStyle(blocked ? Color(hex: 0xFF6B8A) : Theme.textTertiary)
                            Text(genre).font(.system(size: 14, weight: blocked ? .bold : .medium)).foregroundStyle(blocked ? Theme.textPrimary : Theme.textSecondary)
                            Spacer(minLength: 0)
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 10)
                        .background(RoundedRectangle(cornerRadius: 10).fill(blocked ? Color(hex: 0xFF6B8A).opacity(0.12) : Theme.elevated))
                        .overlay(RoundedRectangle(cornerRadius: 10).stroke(blocked ? Color(hex: 0xFF6B8A).opacity(0.6) : Theme.divider, lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                }
            }
            if model.blockedGenres.isEmpty {
                Text("Nothing is blocked.").font(.system(size: 13)).foregroundStyle(Theme.textTertiary)
            }
        }
        .task { await model.loadSettings() }
    }
}

// MARK: Home Rows

/// Settings > Home Rows: switch each row of Home on or off and move it up or down. Saved to the account as you go.
struct HomeRowsPane: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        let choices = model.homeRowChoices
        VStack(alignment: .leading, spacing: 14) {
            if choices.isEmpty {
                Text(model.homeRaw.isEmpty
                     ? "Home has no rows yet. Install an addon first, then come back to arrange them."
                     : "Loading your rows...")
                    .font(.system(size: 13)).foregroundStyle(Theme.textSecondary)
            } else {
                Text("Choose which rows appear on Home and the order they come in. Changes are saved automatically.")
                    .font(.system(size: 13)).foregroundStyle(Theme.textSecondary)
                VStack(spacing: 8) {
                    ForEach(Array(choices.enumerated()), id: \.element.section.id) { index, choice in
                        HStack(spacing: 12) {
                            Toggle("", isOn: Binding(
                                get: { choice.visible },
                                set: { value in Task { await model.setRowVisible(choice.section.id, visible: value) } }
                            ))
                            .labelsHidden()
                            .toggleStyle(.switch)
                            .tint(Theme.accent)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(choice.section.title).font(.system(size: 15, weight: .semibold)).foregroundStyle(Theme.textPrimary)
                                Text("\(choice.section.items.count) titles").font(.system(size: 12)).foregroundStyle(Theme.textTertiary)
                            }
                            .opacity(choice.visible ? 1 : 0.5)
                            Spacer(minLength: 0)
                            arrow("chevron.up", enabled: index > 0) { Task { await model.moveRow(choice.section.id, delta: -1) } }
                            arrow("chevron.down", enabled: index < choices.count - 1) { Task { await model.moveRow(choice.section.id, delta: 1) } }
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                        .background(RoundedRectangle(cornerRadius: 14).fill(Theme.elevated))
                        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Theme.divider, lineWidth: 1))
                    }
                }
            }
        }
        .task { if model.settings == nil { await model.loadSettings() } }
    }

    private func arrow(_ name: String, enabled: Bool, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: name)
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(Theme.textPrimary)
                .frame(width: 32, height: 32)
                .background(Circle().fill(Color.white.opacity(0.08)))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.3)
    }
}

// MARK: Subtitles and Audio

/// Settings > Subtitles: whether subtitles start on, and the language to look for.
struct SubtitlesPane: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 0) {
                Toggle(isOn: Binding(
                    get: { model.settings?.subtitlesEnabled ?? false },
                    set: { value in Task { await model.updateSettings { $0.subtitlesEnabled = value } } }
                )) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Subtitles").font(.system(size: 15, weight: .semibold)).foregroundStyle(Theme.textPrimary)
                        Text("Start playback with subtitles on. You can still switch them in the player.")
                            .font(.system(size: 12)).foregroundStyle(Theme.textSecondary)
                    }
                }
                .toggleStyle(.switch)
                .tint(Theme.accent)
                .padding(16)
            }
            .background(RoundedRectangle(cornerRadius: 14).fill(Theme.elevated))
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(Theme.divider, lineWidth: 1))

            Text("Default language").font(.system(size: 15, weight: .bold)).foregroundStyle(Theme.textPrimary)
            LanguageList(
                choices: LanguageChoices.subtitles(),
                selected: model.settings?.defaultSubtitleLanguage
            ) { code in Task { await model.updateSettings { $0.defaultSubtitleLanguage = code } } }
        }
        .task { if model.settings == nil { await model.loadSettings() } }
    }
}

/// Settings > Audio: the language to prefer when a video has several audio tracks.
struct AudioPane: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Preferred audio language").font(.system(size: 15, weight: .bold)).foregroundStyle(Theme.textPrimary)
            Text("Used when a video has more than one audio track. Automatic leaves it to the video.")
                .font(.system(size: 13)).foregroundStyle(Theme.textSecondary)
            LanguageList(
                choices: LanguageChoices.audio(),
                selected: model.settings?.defaultAudioLanguage
            ) { code in Task { await model.updateSettings { $0.defaultAudioLanguage = code } } }
        }
        .task { if model.settings == nil { await model.loadSettings() } }
    }
}

private struct LanguageList: View {
    let choices: [LanguageChoice]
    let selected: String?
    let pick: (String?) -> Void

    var body: some View {
        VStack(spacing: 0) {
            ForEach(Array(choices.enumerated()), id: \.element.id) { index, choice in
                if index > 0 { Divider().overlay(Theme.divider) }
                Button { pick(choice.code) } label: {
                    HStack(spacing: 12) {
                        Image(systemName: selected == choice.code ? "largecircle.fill.circle" : "circle")
                            .foregroundStyle(selected == choice.code ? Theme.accent : Theme.textTertiary)
                        Text(choice.name).font(.system(size: 14, weight: .medium)).foregroundStyle(Theme.textPrimary)
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 11)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .background(RoundedRectangle(cornerRadius: 14).fill(Theme.elevated))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Theme.divider, lineWidth: 1))
    }
}

// MARK: Updates

/// Settings > Updates: the running version and a check against the newest published release.
struct UpdatesPane: View {
    @EnvironmentObject private var model: AppModel
    @State private var state: CheckState = .idle

    enum CheckState: Equatable {
        case idle, checking, failed
        case result(UpdateResult)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("Version").foregroundStyle(Theme.textSecondary)
                    Spacer()
                    Text(AppInfo.version).foregroundStyle(Theme.textPrimary)
                }
                .font(.system(size: 14))
                Divider().overlay(Theme.divider)
                status
            }
            .padding(18)
            .background(RoundedRectangle(cornerRadius: 14).fill(Theme.elevated))
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(Theme.divider, lineWidth: 1))

            if case .result(.available(let info)) = state {
                VStack(alignment: .leading, spacing: 10) {
                    Text("What's new in \(info.version)").font(.system(size: 15, weight: .bold)).foregroundStyle(Theme.textPrimary)
                    Text(info.notes.isEmpty ? "No notes for this version." : info.notes)
                        .font(.system(size: 13)).foregroundStyle(Theme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                    HStack(spacing: 12) {
                        if let url = info.downloadURL {
                            Link(destination: url) { Label("Download", systemImage: "arrow.down.circle") }
                        }
                        if let url = info.pageURL {
                            Link(destination: url) { Label("Release page", systemImage: "safari") }
                        }
                    }
                    .font(.system(size: 14, weight: .semibold))
                }
                .padding(18)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 14).fill(Theme.elevated))
                .overlay(RoundedRectangle(cornerRadius: 14).stroke(Theme.divider, lineWidth: 1))
            }

            HStack(spacing: 12) {
                Button { Task { await check() } } label: { Label("Check for updates", systemImage: "arrow.clockwise") }
                    .buttonStyle(GlassButtonStyle())
                    .disabled(state == .checking)
            }
            HStack(spacing: 12) {
                Button { model.previewPlusPopup(.invitation) } label: { Label("Preview the Plus invitation", systemImage: "eye") }
                    .buttonStyle(GlassButtonStyle())
                Button { model.previewPlusPopup(.welcome) } label: { Label("Preview the Plus welcome", systemImage: "eye") }
                    .buttonStyle(GlassButtonStyle())
            }
        }
        .task { if state == .idle { await check() } }
    }

    @ViewBuilder
    private var status: some View {
        switch state {
        case .idle, .checking:
            Text("Checking for updates...").font(.system(size: 13)).foregroundStyle(Theme.textSecondary)
        case .failed:
            Text("Couldn't check for updates. Check your connection and try again.").font(.system(size: 13)).foregroundStyle(Theme.textSecondary)
        case .result(.upToDate):
            Text("You're up to date.").font(.system(size: 13)).foregroundStyle(Theme.textSecondary)
        case .result(.available(let info)):
            Text("Version \(info.version) is available.").font(.system(size: 13, weight: .semibold)).foregroundStyle(Theme.accent)
        }
    }

    private func check() async {
        state = .checking
        do {
            state = .result(try await UpdateCheck.check(current: AppInfo.version))
        } catch {
            state = .failed
        }
    }
}
