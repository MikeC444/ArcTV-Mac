import Foundation

public enum AppInfo {
    /// The version this build was packaged as (the release workflow writes it into the app's Info.plist); "dev" when run from the command line.
    public static var version: String {
        (Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String) ?? "dev"
    }

    /// The backend address baked in at build time (the release workflow's API_BASE_URL secret), or empty.
    public static var bundledAPIBaseURL: String {
        (Bundle.main.object(forInfoDictionaryKey: "ArcTVAPIBaseURL") as? String) ?? ""
    }

    /// The same Cinemeta addon the other apps start with, so Home always has something to show.
    public static let cinemetaManifestURL = "https://v3-cinemeta.strem.io/manifest.json"
}
