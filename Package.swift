// swift-tools-version:5.9
import PackageDescription

// ArcTVCore is everything that is not on screen (the addon protocol, the account API, the Home rows), so it can be tested on its own.
// ArcTV is the SwiftUI app. scripts/package-app.sh turns the built program into ArcTV.app and a DMG.
let package = Package(
    name: "ArcTV",
    platforms: [.macOS(.v13)],
    dependencies: [
        // mpv (libmpv, built for Apple platforms): plays MKV, HEVC, HDR and Dolby Vision, which the Mac's own player cannot. LGPL build.
        .package(url: "https://github.com/mpvkit/MPVKit.git", exact: "0.41.0")
    ],
    targets: [
        .target(name: "ArcTVCore"),
        .executableTarget(name: "ArcTV", dependencies: ["ArcTVCore", .product(name: "MPVKit", package: "MPVKit")]),
        .testTarget(name: "ArcTVCoreTests", dependencies: ["ArcTVCore"])
    ]
)
