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
