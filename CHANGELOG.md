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

**Follow-up (entry 7, mpv):** the first runs with the mpv libraries failed at "Making the DMG" with "No space left on device" (the app now holds mpv's libraries and is large). `scripts/package-app.sh` now frees the build caches when it runs on a build machine and sizes the disk image explicitly (the app plus a third).

## 9 -- Stage 4a: Settings > Addons and Blocked Genres

**Status:** Written; checked by the Build and test workflow. Not tried against the real account from the app.

**Context:** There was no way to see or change the addons that give the app its streams, and blocked genres (kept on the account by the other apps) had no effect here.

**Changes:**
- Addons tab: lists every addon on the account (switched-off ones too) with its version, description and what it provides; a switch to turn each on or off; remove (with a confirmation); and "Add an addon" from a pasted link (stremio://, a bare host or a full manifest address; the manifest is fetched and checked, then saved on the account with its manifest kept as the addon sent it). Changes reach the source finder at once.
- Blocked Genres tab: the genres as toggles, saved to the account's settings row (`GET`/`PUT /user/settings`, the whole row sent back with only the genre list changed, null languages sent as nulls); blocked genres are hidden from Home (and its banner), Movies, TV Shows and Search.
- The account's addon list now keeps each manifest's raw JSON so toggling does not lose fields the app does not read.

**Tests performed:** the build and the existing tests; no new unit tests for these screens. Not tried on a Mac.

**Issues discovered:** Home Rows (choose and order rows) is not done: this app's row ids differ from the other apps'.

**Issues fixed:** none.

## 10 -- Stage 4b: Like / Not for me, Picked for you and Settings > Recommendations

**Status:** Written; checked by the Build and test workflow (it compiles, all tests pass, the DMG builds). Not tried against the real account from the app.

**Context:** The other apps give Arc TV Plus members a Picked for you row on Home, fed by Like / Not for me, My List and finished titles. The Mac app had none of it.

**Changes:**
- The recommendation engine, ported from the Fire TV app (which is itself the web app's) value for value, as pure functions in the core library: signals (Like 5, Not for me -5, finished 2, saved 1; the strongest applies), preferences split equally across a title's genres, directors and cast, cosine scoring with genre 0.6 / director 0.25 / cast 0.15 (missing categories are left out and the rest renormalised), the shortlist (by overall genre match, per genre by taste share, then round-robin over the profile's own titles; at most 60 detail lookups), composition (the best five stay, the other places follow the genre split by Sainte-Laguë with a seeded weighted draw so a refresh swaps most of the row), the diversity cap (one title explains at most three picks), reasons ("Because you liked X", "More from directors you enjoy") and the popular fallback until there are three signals with one positive. The seeded generator is mulberry32, the same arithmetic as the other apps.
- Features (genres, directors, cast) are looked up through Cinemeta, four at a time, and kept in a cache file (800 titles, 30 days) so a refresh rarely touches the network.
- Account calls: `GET /user/plus`, `GET`/`POST`/`DELETE /user/feedback`, `GET`/`POST /user/picked-dismissals`.
- Home: a Picked for you row after Continue Watching, only for Plus accounts, with the reason under each title; it includes TV shows; a title rated, finished, started or removed leaves it at once. "Remove from Picked for you" (right-click) keeps a title out for five days on every device. The picks are fixed for a launch and change when Home is refreshed (what showed last time is less likely to return).
- Like and Not for me in the poster's right-click menu and on the title page (Plus only); pressing the same one again takes it off.
- Settings > Recommendations (Plus only): Liked / Not for me lists with View and Remove, "What shapes your picks" (points per kind of title, a note when there are not enough signals yet or more than the engine reads), "How it works", and Reset preferences with a confirmation.

**Tests performed:** unit tests ported from the Fire TV app (signals, preferences, scoring, ranking different profiles differently, exclusions, explanations, the cold-start fallback, the lookup bound, a title never picking itself, diversity, TV shows) and new ones for the seeded generator against reference values from the web app's generator, composition, the summary and points wording, the five-day removal window and its merge with the account's list, the Home row, the feature cache and lookup bound, and decoding the account's answers. The sandbox has no Swift, so nothing was compiled here; the Build and test workflow compiled it and ran all the tests, and passed. The screens were not seen. (The first run of the workflow failed at the final link on unrelated libsmbclient symbols from the mpv libraries; running it again passed with no change to the code.)

**Issues discovered:** Ratings are per profile on the account; this app only has the main profile until profiles are added. A title rated on another device has no poster in the Recommendations list until it is rated here.

**Issues fixed:** none.

## 11 -- Parity with the web app: top bar, poster menu, Home rows, My List, title page

**Status:** Written; checked by the Build and test workflow. Not seen on a Mac.

**Context:** The Mac app had its own layout instead of the web app's: Settings off to the side, a plain right-click menu, five fixed Home rows, a plain My List and a text-only title page.

**Changes:**
- Top bar: Settings is the last place in the pill, as on the web; the account-name button is gone.
- Poster menu: right-click (or control-click) a poster or a Continue Watching card opens the web app's popup: the title's wide picture with its logo, a big Play or "Resume from", a two-by-two grid of My List / Watched / Like / Not for me that stays open and shows a tick, then View details, Remove from Picked for you, Remove from Continue Watching and Choose source. (The menu is a custom view because SwiftUI's own menu cannot look like this.)
- Posters: a green tick on every watched title and the rating on hover.
- My List: All / Watched and the sorts Recently Added, A-Z, Highest Rated and Newest.
- Home rows are now built the way the web app builds them (a port of `StremioAddonProvider.getHomeSections`, `homeVariety.ts` and `homeRows.ts`): from every enabled addon that offers catalogues (Cinemeta when there is none). A Cinemeta-shaped addon gets Popular, New and Top rated (movies and shows together; each reads page 1, 2 or 3 chosen by account and day, then a gentle seeded shuffle) and then Action, Comedy, Drama, Thriller, Horror, Sci-Fi, Crime, Animation and Documentary; any other addon gets its base catalogue and every genre it declares. Titles you have watched, saved or rated are left out, each title shows once, blocked genres are hidden, and the order and hidden rows from the account's settings are used (row ids are now the web app's, so they match). Changing an addon refreshes Home.
- Banner: ten random titles from the rows that are switched on, picked once per launch, rotating every 5 seconds with a slide, dots, a pause button (it also waits while the pointer is over it), and Play (white, as on the web), Trailer (from the account's trailer lookup, opens YouTube), My List and Info.
- Title page: the web layout: logo, release date (from the account's release-date lookup) and length, genres, description, white Play (Resume S1E3 for a show), Trailer and a "more" button that opens Watched / My List / Like / Not for me, the IMDb rating in the corner, a Seasons strip with round season buttons and episode cards (season 0 is left out, as on the web), the cast with photos (filled in from the account's cast lookup when the addon has none) and, for a movie, You May Also Like.
- Build: the final link of the app sometimes failed on libsmbclient symbols in roughly half of the builds, with identical code. The build and packaging steps now try the build up to five times (only the link is redone, so it is cheap).

**Tests performed:** unit tests for My List sorting, the seeds, pages and shuffle checked against the web app's own functions run on the same inputs, row ordering and one-row-per-title, the banner's pool, runtime and date wording, and cast merging. The sandbox cannot compile Swift, so the Build and test workflow is the check; none of the screens were seen.

**Follow-up (from the first look at it on a Mac):** the top bar wrapped its names onto two lines when the window was resized (it now drops the logo, then tightens the pills, and never wraps); the title page was wider than the window because its picture was not cropped (it is now cropped to the window); banner logos popped in after the slide (the banner now loads all its pictures ahead and keeps them in memory); My List was in the opposite order to the other apps (the account sends the oldest first and every order now starts from newest-added first); cast names showed HTML entities such as &apos; (now decoded). Second look: the title page and the Home banner sat too low (the web app makes the hero three quarters of the window, at least 620 high, with its text in the middle; the Mac now does the same), the top bar had no line under the place you are on (it now has the logo-coloured line the web app draws), and a runtime under an hour read "0h 49m" (now "49m").

**Issues discovered:** the web top bar also shows a profile picture (comes with profiles) and hides on scroll (not done). Home does not keep the last session's rows for an instant first paint. The web app's "Choose source" and "Play" differ (Play goes straight to the last source); here both open the source list.

**Issues fixed:** the intermittent link failure is worked around, not diagnosed: the build is tried up to five times. A retry from a clean build directory was tried and failed once, so it was dropped.

