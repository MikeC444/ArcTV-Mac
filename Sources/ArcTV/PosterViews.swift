import AppKit
import ArcTVCore
import SwiftUI

/// A poster with its title and year under it. Give it a [width] in a row; in a grid it fills its column.
struct PosterCard: View {
    @EnvironmentObject private var model: AppModel
    let item: MetaPreview
    var width: CGFloat? = nil
    /// Why this title is in Picked for you ("Because you liked ..."), shown under it.
    var reason: String? = nil
    /// True on the Picked for you row, where the menu can take a title out of it.
    var fromPicked = false
    @State private var hovering = false

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Color.clear
                .aspectRatio(2.0 / 3.0, contentMode: .fit)
                .overlay { artwork }
                .background(RoundedRectangle(cornerRadius: 10).fill(Theme.surface))
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .overlay(alignment: .topLeading) {
                    if model.isWatched(item.id) { WatchedTick().padding(6) }
                }
                .overlay(alignment: .bottom) {
                    if hovering, let rating = item.imdbRating, !rating.isEmpty {
                        Text("★ \(rating)")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(8)
                            .background(LinearGradient(colors: [.clear, .black.opacity(0.85)], startPoint: .top, endPoint: .bottom))
                    }
                }
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.white.opacity(hovering ? 0.9 : 0), lineWidth: 2))
                .shadow(color: .black.opacity(hovering ? 0.55 : 0), radius: 14, y: 6)
                .scaleEffect(hovering ? 1.05 : 1)
                .animation(.easeOut(duration: 0.15), value: hovering)

            Text(item.name)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Theme.textPrimary)
                .lineLimit(1)
            if let year = item.releaseInfo {
                Text(year)
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.textTertiary)
                    .lineLimit(1)
            }
            if let reason {
                Text(reason)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Theme.accent.opacity(0.85))
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
            }
        }
        .frame(width: width)
        .onHover { inside in
            hovering = inside
            CardHover.update(CardMenuTarget(item: item, fromPicked: fromPicked), hovering: inside)
        }
        .contentShape(Rectangle())
        .onTapGesture { model.openDetail(item) }
    }

    @ViewBuilder
    private var artwork: some View {
        if let poster = item.poster, let url = URL(string: poster) {
            AsyncImage(url: url) { phase in
                switch phase {
                case let .success(image):
                    image.resizable().aspectRatio(contentMode: .fill)
                default:
                    initial
                }
            }
        } else {
            initial
        }
    }

    private var initial: some View {
        Text(String(item.name.prefix(1)))
            .font(.system(size: 44, weight: .bold))
            .foregroundStyle(Theme.textTertiary)
    }
}

/// The green tick on a title you have watched.
struct WatchedTick: View {
    var size: CGFloat = 20

    var body: some View {
        Image(systemName: "checkmark")
            .font(.system(size: size * 0.55, weight: .heavy))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(Circle().fill(Theme.watched))
    }
}

/// Which poster the pointer is over, so a right-click anywhere can open that poster's menu. (Each poster reports in with `.onHover`; one event
/// monitor, started once, does the rest. This replaced a view laid over every poster, which got in the way of the poster's own hover outline.)
enum CardHover {
    private static let lock = NSLock()
    private static var current: CardMenuTarget?
    private static var monitor: Any?

    static func update(_ target: CardMenuTarget, hovering: Bool) {
        lock.lock()
        defer { lock.unlock() }
        if hovering { current = target } else if current?.item.id == target.item.id { current = nil }
    }

    private static func target() -> CardMenuTarget? {
        lock.lock()
        defer { lock.unlock() }
        return current
    }

    /// Right-click (or control-click) while over a poster opens its menu instead of doing anything else.
    static func start(open: @escaping (CardMenuTarget) -> Void) {
        guard monitor == nil else { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.rightMouseDown, .leftMouseDown]) { event in
            let secondary = event.type == .rightMouseDown || event.modifierFlags.contains(.control)
            guard secondary, let target = target() else { return event }
            DispatchQueue.main.async { open(target) }
            return nil
        }
    }
}

/// The web app's poster grid: as many columns as fit, titles under each poster.
struct PosterGrid: View {
    let items: [MetaPreview]
    var onLastAppear: (() -> Void)? = nil

    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 150, maximum: 210), spacing: 16, alignment: .top)], alignment: .leading, spacing: 22) {
            ForEach(items) { item in
                PosterCard(item: item)
                    .onAppear {
                        if item.id == items.last?.id { onLastAppear?() }
                    }
            }
        }
        .padding(.horizontal, 44)
    }
}

/// A screen's big title, clear of the top bar.
struct PageTitle: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 34, weight: .heavy))
            .foregroundStyle(Theme.textPrimary)
            .padding(.horizontal, 44)
            .padding(.top, 96)
            .padding(.bottom, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// A rounded pill for choices (sort, genre), selected when [selected].
struct ChoicePill: View {
    let label: String
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(label)
                .font(.system(size: 14, weight: selected ? .bold : .medium))
                .foregroundStyle(selected ? Color(hex: 0x04161A) : Theme.textSecondary)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(Capsule().fill(selected ? Theme.accent : Theme.surfaceHigh))
        }
        .buttonStyle(.plain)
    }
}
