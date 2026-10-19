import AppKit
import ArcTVCore
import SwiftUI

/// Finds the colour of a title's banner picture for the soft light behind Home (see `WashColor`). Answers are kept, so a slide seen once is instant.
@MainActor
enum HeroWash {
    private static var known: [URL: WashRGB?] = [:]

    static func color(for url: URL) async -> WashRGB? {
        if let hit = known[url] { return hit }
        guard let image = await ImageCache.load(url) else { return nil }
        let result = WashColor.compute(rgba: sample(image))
        known[url] = .some(result)
        return result
    }

    /// The picture drawn small (32 by 18) as red, green, blue, alpha bytes.
    private static func sample(_ image: NSImage) -> [UInt8] {
        let width = 32
        let height = 18
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        guard let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return [] }
        let drawn = bytes.withUnsafeMutableBytes { raw -> Bool in
            guard let context = CGContext(
                data: raw.baseAddress, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ) else { return false }
            context.interpolationQuality = .medium
            context.draw(cg, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        return drawn ? bytes : []
    }
}

/// A wide, soft pool of the banner's colour that sits below it and lights the first rows (like the web and Fire TV apps). It fades from one colour
/// to the next as the banner changes.
struct HeroWashLayer: View {
    let color: WashRGB?

    var body: some View {
        ZStack {
            if let color {
                // A circle squashed into a wide ellipse; the stops follow exp(-3t²) so the edge melts away rather than ending in a line.
                let tint = Color(red: color.r / 255, green: color.g / 255, blue: color.b / 255)
                let stops: [Gradient.Stop] = (0...9).map { step in
                    let t = Double(step) / 9
                    return Gradient.Stop(color: tint.opacity(0.3 * exp(-3 * t * t)), location: t)
                }
                GeometryReader { geo in
                    let radius = geo.size.width * 0.8
                    RadialGradient(stops: stops, center: .center, startRadius: 0, endRadius: radius)
                        .frame(width: radius * 2, height: radius * 2)
                        .scaleEffect(x: 1, y: (geo.size.height / 2) / radius, anchor: .center)
                        .position(x: geo.size.width / 2, y: geo.size.height / 2)
                }
                .id("\(Int(color.r)),\(Int(color.g)),\(Int(color.b))")
                .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.9), value: color)
        .allowsHitTesting(false)
    }
}
