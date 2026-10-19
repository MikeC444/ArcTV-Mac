import Foundation

/// A colour as red, green and blue from 0 to 255.
public struct WashRGB: Equatable, Sendable {
    public var r: Double
    public var g: Double
    public var b: Double

    public init(r: Double, g: Double, b: Double) {
        self.r = r
        self.g = g
        self.b = b
    }
}

/// The colour of the soft light behind the Home banner: the title's own artwork, boiled down to one colour (the web app's `lib/washColor.ts` and the
/// Fire TV app's `WashColor.kt`). Dark corners and white text carry no colour, so pixels are weighted by how saturated and how bright they are; a
/// picture with no real colour (black and white, mostly dark) gives nil and Home stays neutral.
public enum WashColor {
    static let minShare = 0.04

    /// `rgba` is a small sample of the picture, four bytes a pixel (red, green, blue, alpha).
    public static func compute(rgba: [UInt8]) -> WashRGB? {
        var r = 0.0
        var g = 0.0
        var b = 0.0
        var weight = 0.0
        var counted = 0
        var at = 0
        while at + 3 < rgba.count {
            defer { at += 4 }
            if rgba[at + 3] < 200 { continue } // see-through
            let pr = Int(rgba[at])
            let pg = Int(rgba[at + 1])
            let pb = Int(rgba[at + 2])
            counted += 1
            let high = max(pr, pg, pb)
            let low = min(pr, pg, pb)
            if high < 40 || low > 225 { continue } // near black or near white
            let saturation = Double(high - low) / Double(high)
            let w = saturation * saturation * (Double(high) / 255)
            r += Double(pr) * w
            g += Double(pg) * w
            b += Double(pb) * w
            weight += w
        }
        if counted == 0 || weight / Double(counted) < minShare * 0.25 { return nil }
        let mr = r / weight
        let mg = g / weight
        let mb = b / weight
        // lift it to a clear, not muddy, colour: the brightest channel to 200, so a dim picture still gives a visible light
        let top = max(mr, mg, mb)
        if top < 1 { return nil }
        let k = 200 / top
        return WashRGB(r: min(255, mr * k), g: min(255, mg * k), b: min(255, mb * k))
    }
}
