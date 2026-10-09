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
- The app asks macOS to treat it as a regular app when it starts, so running it from Xcode or `swift run` (outside an .app) still gives the window keyboard focus.
- `build.yml` (build, test, keep the DMG as an artifact on every push) and `release.yml` (tag or manual run: build, publish the release with the notes
  from `RELEASE_NOTES.md`, file them under the version).

**Tests performed:** none run. Unit tests exist for the addon URL rules, the models' decoding and the Home rows (`swift test`).

**Issues discovered:** none yet.

**Issues fixed:** none.

## 2 -- Restyle to match the web app

**Status:** Written, not yet built (no Swift toolchain here); the first check is the Build and test workflow, then a screenshot from a Mac.

**Context:** Stage 1 was a plain skeleton. Before adding details and playback, the screens are restyled after the web app so everything built later starts out looking right.

**Changes:**
- Design tokens from the web app's `tokens.css` (near-black surfaces, the cyan/blue/violet brand gradient, text greys), the real Arc TV logo embedded in the app, brand-gradient and translucent pill buttons.
- Top bar like the web app's: logo, a translucent pill with Home, Movies, TV Shows, Search and My List, and the account (gear and name) on the right.
- Home: a banner for the first title with its artwork (logo or title, year, rating, genres, description), a Play and More info button (shown disabled: playback is not built yet), then the rows with poster cards that lift and get an outline when the pointer is over them.
- Movies and TV Shows tabs show that kind of title; Search and My List are "coming soon" placeholders; a simple Settings (who is signed in, server, version, refresh, sign out).
- Sign-in screen on a card with the logo and soft corner glows.

**Tests performed:** none yet (see Status). The existing unit tests do not cover the screens.

**Issues discovered:** none.

**Issues fixed:** none.
