import SwiftUI

/// The app's colours, matching the other Arc TV apps (dark, with the cyan accent).
enum Theme {
    static let background = Color(red: 0.043, green: 0.043, blue: 0.051)
    static let elevated = Color(red: 0.078, green: 0.078, blue: 0.09)
    static let surface = Color(red: 0.12, green: 0.12, blue: 0.14)
    static let accent = Color(red: 0.0, green: 0.88, blue: 1.0)
    static let textPrimary = Color.white
    static let textSecondary = Color.white.opacity(0.68)
    static let textTertiary = Color.white.opacity(0.45)
}
