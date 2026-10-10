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

## 3 -- The server address is filled in by default

**Status:** Written; built by the Build and test workflow (see the run for this commit).

**Context:** Running from Xcode, or from any build made without the `API_BASE_URL` secret, asked for the server address on every first sign-in. The release secret only reaches builds made by the release workflow.

**Changes:** the sign-in screen's address starts as what the person saved, else the one baked into the build, else the default Arc TV backend (`https://mangotv-live-tv.onrender.com`, the server the other apps use; not a secret). Sign-in waits up to 60 seconds so a server that is waking up does not fail the first attempt.

**Tests performed:** a unit test for the fallback order; the workflow runs the tests and packages the DMG. Not tried against the real server from the app.

**Issues discovered:** none.

**Issues fixed:** none.

## 4 -- Layouts after the web app: Movies and TV Shows grids, Search, My List, Settings; Home banner fix

**Status:** Written; checked by the Build and test workflow (see the run for this commit), not looked at on a screen yet.

**Context:** A screenshot of the restyled app showed the Home banner losing its description and buttons, the window not resizing cleanly, Movies / TV Shows not laid out like the web app, Search and My List placeholders, and Settings unlike the other apps.

**Changes:**
- Home banner is sized to the window with a layout reader (the picture used to set its size, which pushed the text below the cut-off and made resizing break).
- Movies and TV Shows: a title, Featured / Highest Rated / Newest pills, a genre menu, and a poster grid that fills the window's width and keeps loading as you scroll (Stremio `skip` paging), like the web app.
- Search: a search box (searches as you type after a short pause, never one letter) and a grid of matching movies and shows.
- My List: the account's saved titles (`GET /user/watchlist`), read-only for now; a token that has run out is refreshed and the call retried.
- Settings: grouped places on the left (You, Content, Playback & sound, App) and the chosen one on the right; Account and Updates (version) work, the rest say they are coming.
- Poster cards fill their column in grids and keep a fixed width in rows.

**Tests performed:** unit tests for the sorting, year reading, interleaving and the watchlist answer; the workflow builds and runs them. Not seen on a screen.

**Issues discovered:** none.

**Issues fixed:** the banner and resizing problems above (unverified until looked at on a Mac).

## 5 -- Stage 2: details, sources and the player

**Status:** Written; compiled and tested by the Build and test workflow (see the run for this commit). Not tried on a Mac: playback in particular depends on what the Mac's built-in player can open.

**Context:** Home, Movies, TV Shows, Search and My List showed posters that did nothing. This stage makes a poster open its page, then pick a source, then play.

**Changes:**
- The saved sign-in moves from the Keychain to a private file (`~/Library/Application Support/ArcTV/session.json`, owner-only), so rebuilds and updates stop asking for the Mac login password. Anyone signed in before is asked to sign in once more.
- Details page for a title: backdrop, logo or title, year, runtime, rating, genres, description, director, cast, Play; for a show, season menu and an episode list (the page first shows the card's own fields, then the addon's full answer replaces them). Clicking any poster or the Home banner's Play / More info opens it; Esc or Back goes back.
- Sources page: asks every enabled addon on the account (`GET /user/addons`) that lists a `stream` resource for this type and id, all at once; shows quality, release name, size and addon; sources with a direct web link (what a debrid addon gives) come first, best quality first. Torrent-only streams are listed greyed out ("not supported in this app yet"). Manifest `resources` entries are read as names or objects.
- Player: AVKit's own player in a full window. If the built-in player cannot open the source (MKV, for example) a panel says so, with Open in VLC (if VLC is installed), Copy link and Other sources.

**Tests performed:** unit tests for manifest resources and stream eligibility, stream ids, quality, size and playability, and season grouping; the workflow builds and runs them and packages the DMG. NOT done: any of it on a Mac, or against real addons.

**Issues discovered:** the built-in player will fail on many debrid sources because they are MKV; a libVLC or mpv player is the real fix and is a later stage. No progress saving or Continue Watching yet.

**Issues fixed:** the Keychain password prompt.
