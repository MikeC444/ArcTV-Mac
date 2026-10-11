import Foundation

/// How big subtitles are drawn (Settings > Subtitles > Size). `mpvFontSize` is mpv's `sub-font-size` (pixels at a 720-high picture; its default is 55);
/// `fraction` is the share of the picture's height the preview draws a line of text at, so the preview matches playback.
public enum SubtitleSize: String, CaseIterable, Identifiable, Sendable {
    case small, medium, large, extraLarge

    public var id: String { rawValue }
    public static let `default` = SubtitleSize.medium

    public var label: String {
        switch self {
        case .small: return "Small"
        case .medium: return "Medium"
        case .large: return "Large"
        case .extraLarge: return "Extra large"
        }
    }

    public var mpvFontSize: Int {
        switch self {
        case .small: return 40
        case .medium: return 55
        case .large: return 75
        case .extraLarge: return 100
        }
    }

    public var fraction: Double { Double(mpvFontSize) / 720 }

    public static func from(_ stored: String?) -> SubtitleSize { stored.flatMap(SubtitleSize.init(rawValue:)) ?? .default }
}

/// The colour of subtitle text (Settings > Subtitles > Colour). `hex` is what mpv's `sub-color` takes; the red, green and blue parts are 0 to 1 for the preview.
public enum SubtitleColor: String, CaseIterable, Identifiable, Sendable {
    case white, yellow, cyan, green

    public var id: String { rawValue }
    public static let `default` = SubtitleColor.white

    public var label: String {
        switch self {
        case .white: return "White"
        case .yellow: return "Yellow"
        case .cyan: return "Cyan"
        case .green: return "Green"
        }
    }

    public var hex: String {
        switch self {
        case .white: return "#FFFFFF"
        case .yellow: return "#FFFF00"
        case .cyan: return "#00FFFF"
        case .green: return "#00FF00"
        }
    }

    public var rgb: (red: Double, green: Double, blue: Double) {
        switch self {
        case .white: return (1, 1, 1)
        case .yellow: return (1, 1, 0)
        case .cyan: return (0, 1, 1)
        case .green: return (0, 1, 0)
        }
    }

    public static func from(_ stored: String?) -> SubtitleColor { stored.flatMap(SubtitleColor.init(rawValue:)) ?? .default }
}

/// The two choices, kept on this Mac (not synced: a Mac and a TV want different sizes) and read when the player starts.
public enum SubtitleStyleStore {
    public static let sizeKey = "ArcTVSubtitleSize"
    public static let colorKey = "ArcTVSubtitleColor"

    public static func size(_ defaults: UserDefaults = .standard) -> SubtitleSize { .from(defaults.string(forKey: sizeKey)) }
    public static func color(_ defaults: UserDefaults = .standard) -> SubtitleColor { .from(defaults.string(forKey: colorKey)) }
    public static func setSize(_ size: SubtitleSize, _ defaults: UserDefaults = .standard) { defaults.set(size.rawValue, forKey: sizeKey) }
    public static func setColor(_ color: SubtitleColor, _ defaults: UserDefaults = .standard) { defaults.set(color.rawValue, forKey: colorKey) }
}
