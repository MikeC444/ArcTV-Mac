import AppKit
import SwiftUI

/// Pictures kept in memory once they have been fetched, so one that has been loaded ahead of time shows the moment it is put on screen (the banner
/// loads all its pictures ahead, so a logo slides in with its slide instead of appearing after it).
enum ImageCache {
    private static let cache = NSCache<NSString, NSImage>()

    private static func key(_ url: URL, _ maxPixel: CGFloat?) -> NSString {
        (maxPixel.map { "\(url.absoluteString)#\(Int($0))" } ?? url.absoluteString) as NSString
    }

    static func image(for url: URL, maxPixel: CGFloat? = nil) -> NSImage? { cache.object(forKey: key(url, maxPixel)) }

    /// The picture, fetched once. With `maxPixel` it is made no bigger than that many pixels on its long side, and decoded here, off the main thread:
    /// a full-size backdrop is decoded lazily the first time it is drawn, on the main thread, and a page of them scrolling in is what made scrolling
    /// stutter. Pass the size it will be shown at (twice the points, for a sharp picture on a Retina screen).
    static func load(_ url: URL, maxPixel: CGFloat? = nil) async -> NSImage? {
        if let known = image(for: url, maxPixel: maxPixel) { return known }
        guard let (data, _) = try? await URLSession.shared.data(from: url) else { return nil }
        let image: NSImage?
        if let maxPixel, let source = CGImageSourceCreateWithData(data as CFData, nil) {
            let options: [CFString: Any] = [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceShouldCacheImmediately: true,
                kCGImageSourceThumbnailMaxPixelSize: maxPixel
            ]
            image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
                .map { NSImage(cgImage: $0, size: NSSize(width: $0.width, height: $0.height)) } ?? NSImage(data: data)
        } else {
            image = NSImage(data: data)
        }
        guard let image else { return nil }
        cache.setObject(image, forKey: key(url, maxPixel))
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
    /// The size to make the picture (its long side in pixels) when it is shown small: see `ImageCache.load`.
    var maxPixel: CGFloat?
    @ViewBuilder var placeholder: () -> Placeholder
    @State private var image: NSImage?

    init(url: URL?, contentMode: ContentMode = .fill, maxPixel: CGFloat? = nil, @ViewBuilder placeholder: @escaping () -> Placeholder) {
        self.url = url
        self.contentMode = contentMode
        self.maxPixel = maxPixel
        self.placeholder = placeholder
        _image = State(initialValue: url.flatMap { ImageCache.image(for: $0, maxPixel: maxPixel) })
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
            if let cached = ImageCache.image(for: url, maxPixel: maxPixel) {
                image = cached
            } else {
                image = await ImageCache.load(url, maxPixel: maxPixel)
            }
        }
    }
}

extension CachedImage where Placeholder == Color {
    init(url: URL?, contentMode: ContentMode = .fill, maxPixel: CGFloat? = nil) {
        self.init(url: url, contentMode: contentMode, maxPixel: maxPixel) { Color.clear }
    }
}
