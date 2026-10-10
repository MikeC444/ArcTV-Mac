import AppKit
import SwiftUI

/// Pictures kept in memory once they have been fetched, so one that has been loaded ahead of time shows the moment it is put on screen (the banner
/// loads all its pictures ahead, so a logo slides in with its slide instead of appearing after it).
enum ImageCache {
    private static let cache = NSCache<NSString, NSImage>()

    static func image(for url: URL) -> NSImage? { cache.object(forKey: url.absoluteString as NSString) }

    static func load(_ url: URL) async -> NSImage? {
        if let known = image(for: url) { return known }
        guard let (data, _) = try? await URLSession.shared.data(from: url), let image = NSImage(data: data) else { return nil }
        cache.setObject(image, forKey: url.absoluteString as NSString)
        return image
    }

    /// Fetches the pictures one after another in the background (the first is wanted soonest).
    static func preload(_ urls: [URL]) {
        Task.detached(priority: .utility) {
            for url in urls { _ = await load(url) }
        }
    }
}

/// A picture from the web, drawn from the cache when it is already there. `fill` crops to the frame, `fit` shows all of it.
struct CachedImage<Placeholder: View>: View {
    let url: URL?
    var contentMode: ContentMode = .fill
    @ViewBuilder var placeholder: () -> Placeholder
    @State private var image: NSImage?

    init(url: URL?, contentMode: ContentMode = .fill, @ViewBuilder placeholder: @escaping () -> Placeholder) {
        self.url = url
        self.contentMode = contentMode
        self.placeholder = placeholder
        _image = State(initialValue: url.flatMap { ImageCache.image(for: $0) })
    }

    var body: some View {
        Group {
            if let image {
                Image(nsImage: image).resizable().aspectRatio(contentMode: contentMode)
            } else {
                placeholder()
            }
        }
        .task(id: url) {
            guard let url else { return }
            if let cached = ImageCache.image(for: url) {
                image = cached
            } else {
                image = await ImageCache.load(url)
            }
        }
    }
}

extension CachedImage where Placeholder == Color {
    init(url: URL?, contentMode: ContentMode = .fill) {
        self.init(url: url, contentMode: contentMode) { Color.clear }
    }
}
