import ArcTVCore
import SwiftUI

private struct MenuHeightKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = max(value, nextValue()) }
}

/// What right-clicking a poster opens (the web app's poster menu): the title's artwork, a big Play (or Resume), My List / Watched / Like / Not for me
/// that stay open and show a tick when set, then View details, Choose source and the removals.
struct CardMenuView: View {
    @EnvironmentObject private var model: AppModel
    let target: CardMenuTarget

    private var item: MetaPreview { target.item }
    private var resume: ContinueItem? { model.continueItems.first { $0.contentId == item.id } }
    private let panelWidth: CGFloat = 500
    @State private var contentHeight: CGFloat = 640

    var body: some View {
        GeometryReader { geo in
            ZStack {
                Color.black.opacity(0.62)
                    .ignoresSafeArea()
                    .onTapGesture { close() }
                panel
                    .frame(width: panelWidth, height: min(contentHeight, geo.size.height - 60))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private var panel: some View {
        ScrollView {
            VStack(spacing: 16) {
                banner
                VStack(spacing: 16) {
                    playButton
                    toggles
                    rows
                }
                .padding(.horizontal, 26)
                .padding(.bottom, 22)
            }
            .background(GeometryReader { proxy in Color.clear.preference(key: MenuHeightKey.self, value: proxy.size.height) })
        }
        .onPreferenceChange(MenuHeightKey.self) { contentHeight = $0 }
        .scrollIndicators(.hidden)
            .background(RoundedRectangle(cornerRadius: 24).fill(Theme.elevated))
            .clipShape(RoundedRectangle(cornerRadius: 24))
            .overlay(RoundedRectangle(cornerRadius: 24).stroke(Theme.divider, lineWidth: 1))
            .overlay(alignment: .topTrailing) {
                Button(action: close) {
                    Image(systemName: "xmark")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(Theme.textPrimary)
                        .frame(width: 34, height: 34)
                        .background(Circle().fill(Color.black.opacity(0.55)))
                }
                .buttonStyle(.plain)
                .keyboardShortcut(.cancelAction)
                .padding(14)
            }
        .shadow(color: .black.opacity(0.6), radius: 40, y: 20)
    }

    private func close() { model.cardMenu = nil }

    // MARK: Top

    @ViewBuilder
    private var banner: some View {
        if let background = item.background, let url = URL(string: background) {
            ZStack(alignment: .bottomLeading) {
                Theme.surfaceHigh
                AsyncImage(url: url) { phase in
                    if case let .success(image) = phase { image.resizable().aspectRatio(contentMode: .fill) }
                }
                .frame(width: panelWidth, height: 230)
                .clipped()
                LinearGradient(colors: [Theme.elevated, Theme.elevated.opacity(0.55), .clear], startPoint: .bottom, endPoint: .top)
                    .frame(height: 230)
                bannerTitle
                    .padding(.horizontal, 26)
                    .padding(.bottom, 18)
            }
            .frame(width: panelWidth, height: 230)
            .clipped()
        } else {
            HStack(spacing: 20) {
                Color.clear
                    .frame(width: 100, height: 150)
                    .overlay {
                        if let poster = item.poster, let url = URL(string: poster) {
                            AsyncImage(url: url) { phase in
                                if case let .success(image) = phase { image.resizable().aspectRatio(contentMode: .fill) }
                            }
                        }
                    }
                    .background(Theme.surfaceHigh)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                Text(item.name)
                    .font(.system(size: 26, weight: .bold))
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(3)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 26)
            .padding(.top, 34)
        }
    }

    @ViewBuilder
    private var bannerTitle: some View {
        if let logo = item.logo, let url = URL(string: logo) {
            AsyncImage(url: url) { phase in
                switch phase {
                case let .success(image): image.resizable().aspectRatio(contentMode: .fit)
                default: bannerText
                }
            }
            .frame(maxWidth: 320, maxHeight: 100, alignment: .bottomLeading)
            .shadow(color: .black.opacity(0.7), radius: 8, y: 3)
        } else {
            bannerText
        }
    }

    private var bannerText: some View {
        Text(item.name)
            .font(.system(size: 32, weight: .heavy))
            .foregroundStyle(Theme.textPrimary)
            .lineLimit(2)
            .shadow(color: .black.opacity(0.8), radius: 8, y: 2)
    }

    // MARK: Play

    private var playButton: some View {
        Button(action: play) {
            HStack(spacing: 10) {
                Image(systemName: "play.fill").font(.system(size: 22))
                Text(resume.map { "Resume from \(MPVPlayerModel.clock($0.positionSeconds))" } ?? "Play")
                    .font(.system(size: 20, weight: .bold))
            }
            .foregroundStyle(Color(hex: 0x04161A))
            .frame(maxWidth: .infinity, minHeight: 58)
            .background(RoundedRectangle(cornerRadius: 12).fill(Color(hex: 0x70EFFF)))
        }
        .buttonStyle(.plain)
    }

    // MARK: My List / Watched / Like / Not for me

    private var toggles: some View {
        let saved = model.isSaved(item.id)
        let watched = model.isWatched(item.id)
        let rating = model.rating(of: item.id)
        return LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
            toggle(on: saved, onIcon: "checkmark", offIcon: "plus", onText: "In My List", offText: "Add to My List") {
                await model.toggleSaved(item.asDetail)
            }
            toggle(on: watched, onIcon: "checkmark", offIcon: "checkmark.circle", onText: "Watched", offText: "Mark as watched") {
                await model.toggleWatched(item.asDetail)
            }
            if model.plus.active {
                toggle(on: rating == .like, onIcon: "hand.thumbsup.fill", offIcon: "hand.thumbsup", onText: "Like", offText: "Like") {
                    await model.rate(item, .like)
                }
                toggle(on: rating == .dislike, onIcon: "hand.thumbsdown.fill", offIcon: "hand.thumbsdown", onText: "Not for me", offText: "Not for me") {
                    await model.rate(item, .dislike)
                }
            }
        }
    }

    private func toggle(on: Bool, onIcon: String, offIcon: String, onText: String, offText: String, action: @escaping () async -> Void) -> some View {
        Button { Task { await action() } } label: {
            HStack(spacing: 10) {
                Image(systemName: on ? onIcon : offIcon)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(on ? Color.white : Theme.cyan)
                Text(on ? onText : offText)
                    .font(.system(size: 15, weight: on ? .bold : .medium))
                    .foregroundStyle(on ? Color(hex: 0xD8FBFF) : Theme.textPrimary)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, minHeight: 54)
            .background(RoundedRectangle(cornerRadius: 12).fill(on ? Theme.cyan.opacity(0.2) : Theme.surface))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(on ? Theme.cyan : Theme.divider, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .animation(.easeOut(duration: 0.2), value: on)
    }

    // MARK: Rows

    private var rows: some View {
        VStack(spacing: 0) {
            Divider().overlay(Theme.divider)
            if model.plus.active, target.fromPicked {
                row("eye.slash", "Remove from Picked for you") {
                    Task { await model.removeFromPicked(item.id) }
                    close()
                }
            }
            row("info.circle", "View details", chevron: true) {
                close()
                model.openDetail(item)
            }
            if let resume {
                row("trash", "Remove from Continue Watching", destructive: true) {
                    Task { await model.removeFromContinueWatching(resume) }
                    close()
                }
            }
            row("list.bullet", "Choose source", chevron: true, last: true) { chooseSource() }
        }
    }

    private func row(_ icon: String, _ text: String, chevron: Bool = false, destructive: Bool = false, last: Bool = false, action: @escaping () -> Void) -> some View {
        VStack(spacing: 0) {
            Button(action: action) {
                HStack(spacing: 18) {
                    Image(systemName: icon).font(.system(size: 18)).frame(width: 26)
                    Text(text).font(.system(size: 16, weight: .medium))
                    Spacer(minLength: 0)
                    if chevron { Image(systemName: "chevron.right").font(.system(size: 14, weight: .semibold)).foregroundStyle(Theme.textSecondary) }
                }
                .foregroundStyle(destructive ? Theme.coralText : Theme.textPrimary)
                .padding(.horizontal, 12)
                .frame(maxWidth: .infinity, minHeight: 50, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            if !last { Divider().overlay(Theme.divider) }
        }
    }

    // MARK: Actions

    /// Play: pick up where it was left, play a movie, or (a show not started) open its page, which knows the first episode.
    private func play() {
        close()
        let detail = item.asDetail
        if let resume {
            model.openSources(PlayTarget(
                title: detail, season: resume.seasonNumber, episode: resume.episodeNumber, episodeTitle: resume.episodeTitle,
                startAt: resume.positionSeconds
            ))
        } else if item.type == "series" {
            model.openDetail(item)
        } else {
            model.openSources(PlayTarget(title: detail))
        }
    }

    /// The source list from the start (or the episode in progress), whatever was last used.
    private func chooseSource() {
        close()
        if item.type == "series", resume == nil {
            model.openDetail(item)
        } else {
            model.openSources(PlayTarget(title: item.asDetail, season: resume?.seasonNumber, episode: resume?.episodeNumber, episodeTitle: resume?.episodeTitle))
        }
    }
}
