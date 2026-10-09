# Arc TV for Mac

A native Mac app (Swift and SwiftUI) for Arc TV, built alongside the Fire TV app (`MikeC444/ArcTV-AndroidTV`, which also holds the backend in
`server/`), the phone app (`MikeC444/arctv-mobileapk`) and the web app (`MikeC444/ArcTV-Web`). It talks to the same account backend and the
same Stremio-protocol addons.

**Status: stage 1.** Sign in with your Arc TV account and browse Home (Popular, New and Top rated rows from Cinemeta). Details pages, playback,
sync, Picked for you and Plus come in later stages.

## Install (unsigned)

Download `ArcTV-<version>.dmg` from the [Releases](../../releases) page, open it and drag Arc TV into Applications.

The app is **not signed with an Apple Developer ID and not notarized**, so macOS warns the first time it is opened:

- **macOS 13 and 14:** right-click Arc TV, choose **Open**, then **Open** again.
- **macOS 15 and later:** try to open it once, then go to **System Settings > Privacy & Security**, scroll down and click **Open Anyway**.
- Or, in Terminal: `xattr -d com.apple.quarantine /Applications/ArcTV.app`

(The exact wording differs between macOS versions.) The app does carry a free ad-hoc signature, which Apple Silicon Macs need to run it at all.

## Build

Needs macOS 13+ with Xcode's command line tools (Swift 5.9+).

```
swift test                              # the tests (ArcTVCore: addon protocol, account API, Home rows)
swift run ArcTV                         # run it from the command line
scripts/package-app.sh 0.1.0            # build/ArcTV.app and build/ArcTV-0.1.0.dmg
```

The backend address is baked in from the `API_BASE_URL` environment variable when packaging (the release workflow reads it from a repository
secret of the same name). It can also be typed on the sign-in screen, so a build without it still works.

## Layout

- `Sources/ArcTVCore`: everything that isn't on screen, so it can be tested on its own.
- `Sources/ArcTV`: the SwiftUI app.
- `Tests/ArcTVCoreTests`: unit tests.
- `.github/workflows/build.yml`: builds and tests every push and keeps an unsigned DMG as a build artifact.
- `.github/workflows/release.yml`: on a version tag or a manual run, builds the DMG and publishes a GitHub Release with the patch notes.

## Releasing

Add each user-visible change as a bullet under `## Unreleased` in `RELEASE_NOTES.md`, then run the **Build and publish release DMG** workflow with
a version (for example `0.1.0`). The notes under Unreleased become the release's notes and are filed under the version afterwards.
