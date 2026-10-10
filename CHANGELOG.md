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

## 6 -- The sources page says why an addon gave nothing

**Status:** Written; checked by the Build and test workflow.

**Context:** A first try on a title showed only "Your addons had no streams for this title." with no way to tell an empty answer from an error (the Android apps show each addon's reason, such as "Torrentio refused the request (HTTP 403)").

**Changes:** the source finder returns the streams, the addons that failed with why (timed out, refused with the HTTP status, server error, could not be reached), and the addons that do not give streams at all; the page lists failures in amber and the others in grey under the sources, and the empty message says which case it is.

**Tests performed:** a unit test for the wording of each error. Not tried against real addons.

**Issues discovered:** none.

**Issues fixed:** none.

**Follow-up (same entry):** the Stage 2 build failed on the macOS runner with "reference to captured var 'self' in concurrently-executing code" in the player (a closure kept `self` inside `init`); the failure watcher is now set up in `start()`. Xcode on the user's Mac had built the same code, so the compiler versions differ.

## 7 -- The mpv player, and the player choice in Settings

**Status:** Written; whether it compiles and links is checked by the Build and test workflow (this adds a large binary dependency). Not seen playing video: no Mac was available to the author.

**Context:** The Mac's built-in player (AVKit) cannot open MKV files, which is what debrid addons mostly give ("Cannot Open"). The Android apps use VLC; the Mac app uses mpv.

**Changes:**
- New dependency: MPVKit 0.41.0 (libmpv built for Apple platforms, LGPL build) in `Package.swift`.
- `MPVVideoView`: an OpenGL view mpv draws into, adapted from MPVKit's macOS demo (create and set options, render context, wake-up and draw callbacks, an event loop for position, duration, pause, buffering, end and failure, clean shutdown).
- `MPVPlayerModel` and `MPVPlayerScreen`: the app's own controls over the video: play and pause, 10-second skips, a seek bar, volume, audio and subtitle track menus (read from mpv's track list), full screen, auto-hiding controls, tap to pause, double-tap for full screen; space, left and right arrows and F as shortcuts; a failure panel; going back when the video ends.
- The player is chosen in Settings > Player: Arc TV player (mpv) is the default, the Mac built-in player stays as the other choice (the old player view is now `BuiltInPlayerView`).

**Tests performed:** none of the player itself (it cannot run here). Unit tests still cover the core library.

**Issues discovered:** none yet.

**Issues fixed:** none yet.

## 8 -- Stage 3: My List, Watched, Continue Watching and resume

**Status:** Written; checked by the Build and test workflow. Not tried against the real account from the app.

**Context:** The app could show My List but not change it, and forgot where you stopped.

**Changes:**
- Account calls: `GET /user/continue-watching`, `POST /user/watch-progress`, `DELETE /user/continue-watching`, `POST` and `DELETE /user/watchlist` (timestamps are ISO-8601 UTC with milliseconds; a token that has run out is refreshed and the call retried).
- Title pages: My List and Watched toggles beside Play; Play becomes "Resume 12:34" (or "Resume S1 E3 12:34") when Continue Watching has the title, and the episode list resumes the right episode.
- The mpv player starts at the saved position and reports progress every 30 seconds and on leaving; 92% or more counts as finished (a finished movie is marked watched).
- Home: a Continue Watching row (wide cards with a progress bar) above the rows; clicking one opens the title, which offers Resume.
- Right-click on any poster: View details, Add to / Remove from My List, Mark as watched / not watched, and Remove from Continue Watching when it is there.
- My List now keeps the raw account entries so changes show at once and are put back if the account could not be reached.

**Tests performed:** unit tests for timestamps, Continue Watching decoding and progress, the My List entry made from a title (and that empty fields are left out), and the progress report's episode pair. Not tried on a Mac.

**Issues discovered:** none yet. Not done: Like / Not for me, Picked for you, Recommendations, profiles (the next stage); the built-in Apple player does not report progress.

**Issues fixed:** none.
