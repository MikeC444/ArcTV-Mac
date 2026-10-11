import Foundation

/// A "not ready yet" slate: debrid addons (AIOStreams on ElfHosted, for one) answer a title that isn't cached yet with a short video that says
/// so, and it plays like any other video. Recognised by being far shorter than the title.
public enum PlaceholderVideo {
    /// A "video" shorter than this, for a title that runs much longer, is not the title.
    public static let maxSeconds = 120.0

    public static let message = "This source isn't ready yet. Its debrid service may still be preparing the file. Try again in a few minutes, or choose another source."

    /// A film or episode with a known runtime of at least 10 minutes that comes back as under two minutes, and under a tenth of that runtime, is a
    /// slate. Without a known runtime nothing is assumed, so a genuinely short film is never turned away.
    public static func isPlaceholder(durationSeconds: Double, runtimeMinutes: Int?) -> Bool {
        guard let runtimeMinutes, runtimeMinutes >= 10, durationSeconds.isFinite, durationSeconds > 0 else { return false }
        return durationSeconds < maxSeconds && durationSeconds < Double(runtimeMinutes * 60) / 10
    }
}
