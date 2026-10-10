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
        // A small C face on libtorrent (the torrent engine), which Homebrew supplies: `brew install libtorrent-rasterbar`. The flags are what
        // `pkg-config --cflags libtorrent-rasterbar` prints, with Homebrew's Apple Silicon paths. scripts/package-app.sh copies the libraries into the app.
        .target(
            name: "CTorrent",
            cxxSettings: [
                .unsafeFlags([
                    "-std=c++17", "-fexceptions",
                    "-I/opt/homebrew/opt/libtorrent-rasterbar/include", "-I/opt/homebrew/opt/boost/include", "-I/opt/homebrew/opt/openssl@3/include",
                    "-DTORRENT_LINKING_SHARED", "-DBOOST_ASIO_ENABLE_CANCELIO", "-DBOOST_ASIO_NO_DEPRECATED", "-DBOOST_SYSTEM_USE_UTF8",
                    "-D_SILENCE_CXX17_ALLOCATOR_VOID_DEPRECATION_WARNING", "-DTORRENT_ABI_VERSION=2", "-DTORRENT_USE_OPENSSL",
                    "-DTORRENT_USE_LIBCRYPTO", "-DTORRENT_SSL_PEERS", "-DOPENSSL_NO_SSL2", "-DOPENSSL_NO_SSL3", "-DOPENSSL_NO_TLS1",
                    "-DOPENSSL_NO_TLS1_1", "-DOPENSSL_NO_DTLS1"
                ])
            ],
            linkerSettings: [
                .unsafeFlags(["-L/opt/homebrew/opt/libtorrent-rasterbar/lib", "-L/opt/homebrew/opt/openssl@3/lib"]),
                .linkedLibrary("torrent-rasterbar")
            ]
        ),
        .executableTarget(name: "ArcTV", dependencies: ["ArcTVCore", "CTorrent", .product(name: "MPVKit", package: "MPVKit")]),
        .testTarget(name: "ArcTVCoreTests", dependencies: ["ArcTVCore"])
    ]
)
