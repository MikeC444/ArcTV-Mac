# Changelog

Engineering log for the Arc TV Mac app, one entry per unit of work, newest last.

## 1 -- Stage 1: project, build workflows, sign-in and Home

**Status:** Written, not yet built: this sandbox has no Swift toolchain, so nothing here has been compiled or run. The first check is the **Build and
test (Arc TV Mac)** workflow on a macOS runner.

**Context:** A native Mac app for Arc TV, shipped as an unsigned DMG. It reuses no Android code; it follows the Fire TV app's behaviour and the web
app's look, and talks to the same backend and Stremio addons.

**Changes:**
- Swift package: `ArcTVCore` (addon manifest and catalogue models and client, addon URL rules, account login/refresh/logout client, Keychain session
  store, device id, Home rows) and the SwiftUI app `ArcTV` (sign-in screen, Home with poster rows, refresh, sign out).
- `scripts/package-app.sh`: universal (arm64 + x86_64) build, `ArcTV.app` with an Info.plist, ad-hoc signature, DMG with an Applications shortcut.
- `build.yml` (build, test, keep the DMG as an artifact on every push) and `release.yml` (tag or manual run: build, publish the release with the notes
  from `RELEASE_NOTES.md`, file them under the version).

**Tests performed:** none run. Unit tests exist for the addon URL rules, the models' decoding and the Home rows (`swift test`).

**Issues discovered:** none yet.

**Issues fixed:** none.
