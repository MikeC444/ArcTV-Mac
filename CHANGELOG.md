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
- Build: the final link of the app sometimes failed on libsmbclient symbols in roughly half of the builds, with identical code. The build step now builds the tests (trying up to five times; only the link is redone, so it is cheap) and the test step runs them without building again (`swift test --skip-build`), because in one run the build step succeeded and the relink inside `swift test` was what failed.

**Tests performed:** unit tests for My List sorting, the seeds, pages and shuffle checked against the web app's own functions run on the same inputs, row ordering and one-row-per-title, the banner's pool, runtime and date wording, and cast merging. The sandbox cannot compile Swift, so the Build and test workflow is the check; none of the screens were seen.

**Follow-up (from the first look at it on a Mac):** the top bar wrapped its names onto two lines when the window was resized (it now drops the logo, then tightens the pills, and never wraps); the title page was wider than the window because its picture was not cropped (it is now cropped to the window); banner logos popped in after the slide (the banner now loads all its pictures ahead and keeps them in memory); My List was in the opposite order to the other apps (the account sends the oldest first and every order now starts from newest-added first); cast names showed HTML entities such as &apos; (now decoded). Second look: the title page and the Home banner sat too low (the web app makes the hero three quarters of the window, at least 620 high, with its text in the middle; the Mac now does the same), the top bar had no line under the place you are on (it now has the logo-coloured line the web app draws), and (third look) the title page now starts below the top bar with the IMDb rating at the end of the Play / Trailer row and the seasons straight after it, and Home's first row rides up over the bottom of the banner by 44 points; a runtime under an hour read "0h 49m" (now "49m").

**Issues discovered:** the web top bar also shows a profile picture (comes with profiles) and hides on scroll (not done). Home does not keep the last session's rows for an instant first paint. The web app's "Choose source" and "Play" differ (Play goes straight to the last source); here both open the source list.

**Issues fixed:** the intermittent link failure is worked around, not diagnosed: the build is tried up to five times. A retry from a clean build directory was tried and failed once, so it was dropped.

## 12 -- Parity with the web app, part 2: Movies / TV Shows, Search, Home loading, sources, player memory, sign-in

**Status:** Written; checked by the Build and test workflow (see below). Not seen on a Mac.

**Context:** The remaining differences from the web app that were listed: Search, Movies and TV Shows, the top bar, Home's loading, the sources page, the player and the sign-in screen.

**Changes:**
- Movies and TV Shows: the title with a genre drop-down beside it (the Cinemeta genre lists, blocked genres left out), Featured / Highest Rated / Newest, and pages of titles from every addon on the account (not only Cinemeta), shuffled, loaded as you scroll and kept so Back finds the same list; grey placeholders while the first page loads. The selected pill is now the web's solid cyan.
- Search: a round box that searches as you type (a short pause, never one letter), up to five matching titles under it (poster, name, "Movie · 2024"), recent searches (kept per account, with Clear and a remove button on each), Movies and TV Shows as separate grids with their counts, "Still checking other addons…", "No results". Every addon is searched at once (each with a 6 second limit); one that can search is asked for real, otherwise its catalogues are filtered by title. Not done: the arrow keys for the suggestion list.
- Home: the last session's rows (up to 30 per row, kept for 7 days, per account) are shown at once and replaced as soon as the first fresh ones arrive; grey placeholders in the shape of Home while nothing is known yet; an offline banner along the bottom while the Mac has no network.
- Top bar: slides away as you scroll down a page and returns when you scroll up or move the pointer to the top (done by watching scroll events, so it follows the amount scrolled only approximately).
- Sources: the source list is skipped when the title (or episode) was watched before on a source that is still there (matched by torrent hash, then by addon and release name, then by release name); "Choose source" in the poster menu always shows the list. The empty page now says "No sources found" with the reasons, Try Again, Manage Addons (opens Settings > Addons) and the web app's step-by-step guide to setting up a debrid service and Torrentio.
- Player: the volume and a new speed menu (0.5x to 2x) are remembered for every title on this Mac.
- Sign-in: the web layout: the living-room photo on the right fading into the page, "Your Entertainment, Your Way", Log In and Sign Up, the email form (with a display name when signing up, show or hide password, the same checks as the web app, a countdown after "too many attempts"), and the server address behind a small link. Creating an account is new (`POST /auth/register`).

**Tests performed:** unit tests for recent searches, the genre lists, the cached Home rows (same account only, only while fresh), remembered sources (hash match, same addon and release, never a source that cannot play, per account and per episode). The sandbox cannot compile Swift; the workflow is the check, and nothing was seen on screen.

**Issues discovered:** the web app has no "Pick up where you left off?" prompt: the web player code and the Home and Detail pages have none, and what the web does is the "skip the list for a remembered source" behaviour above (the parity notes said otherwise). Signing in by scanning a QR code is not built. The profile picture in the top bar comes with profiles.

**Issues fixed:** none.

## 13 -- Profiles (Arc TV Plus)

**Status:** Written; see the build result below. Not tried against a real account with several profiles.

**Context:** Stage 4c. An account with Plus can have up to five profiles, each with its own My List, Continue Watching, history, settings (Home Rows, Blocked Genres...), addons and Likes. The Mac app only knew the account's own profile.

**Changes:**
- Backend calls: `GET`/`POST /user/profiles`, `PUT`/`DELETE /user/profiles/:id` (a locked profile needs its current PIN in `X-ArcTV-Pin`), `POST /user/profiles/:id/verify-pin` (204 right, 403 wrong, 429 locked out). Every library call now carries `X-ArcTV-Profile` for a profile that is not the account's own; the account-level calls (`/user/plus`, `/user/profiles`, trailers, release dates, cast) do not.
- "Who's watching?" opens at launch for a Plus account with more than one profile (and from the picture and name at the top right of the top bar): tiles with the picture, a lock for a PIN, "Kids"; Add profile (up to five); Manage profiles; Switch account (signs out). A locked profile asks for its PIN first, with the reason when it is wrong or locked.
- Add / edit a profile: name (24), one of the sixteen pictures (embedded from the web app; old colour-tile ids show as the nearest picture), Adult or Kids (not for the account's own profile), a four-digit PIN (on, change, off; the current PIN is asked for before changing or removing a locked profile) and Remove (not for the account's own profile).
- Choosing a profile starts over on its library: nothing of the last profile stays in memory. What the Mac keeps for itself is kept per profile too (the last Home rows, recent searches, remembered sources, picks taken out of Picked for you); the account's own profile keeps the names it always had.
- A kids profile has no Settings and hides Horror, Thriller, Crime, War, Mystery, Film-Noir and Adult everywhere blocked genres apply, on top of its own list. Without Plus, or when the backend has no profiles, there is just the account's own profile and no picker.

**Tests performed:** unit tests for PIN rules, the avatar ids, which calls go without the profile header, decoding a profile, and how an update sends a PIN (left alone, removed with null, set). The Mac code could not be compiled here; the Build and test workflow is the check. The screens and the real backend were not tried.

**Issues discovered:** Settings > Account does not yet say "Watching as ...". A title page that a kids profile should not open (by a link) is not blocked, only hidden from the lists. Likes of a profile are still read through the profile header, which the backend treats as the authority.

**Issues fixed:** none.

## 14 -- Arc TV Plus: the Plus tab, Plus settings, Your stats and the Plus popups

**Status:** Written; see the build result below. Not tried against the real account, Stripe or a paywall that is switched on.

**Context:** Stage 4d. These Settings tabs showed "coming in a later update".

**Changes:**
- Settings > Arc TV Plus: the status (Early access while the paywall is off, "You have Arc TV Plus (Yearly). Your current period runs to ...", or the free plan), for a monthly or yearly subscriber when it renews and Cancel subscription with a confirmation (`POST /user/plus/cancel`: it stops at the end of the period paid for), what Plus adds (Picked for you, Profiles, Smart source picking, Your stats; Parental controls marked Coming soon), and, with the paywall on and no Plus, the three plans. A plan opens Stripe's checkout page in the browser (`POST /user/plus/checkout`, https only) and the app then asks `GET /user/plus` every four seconds for ten minutes, so Plus switches on by itself. The yearly plan says how many free days the account is offered. Prices are shown on Stripe's page ("Price at checkout"), as on the web.
- Settings > Plus settings: Smart source picking (kept on this Mac). When on, a title with no remembered source skips the source list and plays the best source that can play here (the list is best-first and playable first); "Choose source" always shows the list. The tabs that need Plus (Plus settings, Recommendations, Your stats) are greyed with a Plus tag without it, and say so if reached.
- Settings > Your stats: the web app's stats from the profile's watch history (`GET /user/history`, read 200 rows at a time, up to 5,000): total time and how this week compares, last 7 and 30 days, day streak (and the best), time per day you watch, movies finished, episodes watched, the movies-or-shows split, a 13-week activity grid and a busiest-weekday chart.
- Plus popups, a few seconds after landing on Home, never on a kids profile and never twice in one launch: for members "Everything in Arc TV Plus", once ever (Close and "See my Plus settings" both count as seen); for everyone else once Plus is paid, the invitation, which comes back five days after it was closed or followed ("Take me there") and never after "Don't show me again". Both are remembered per account on this Mac.

**Tests performed:** unit tests for when each popup is due (including the five days), what counts as watched, how durations are written, the week-on-week change, the stats from a small history (totals, last seven days, the split, streak, busiest weekday), the activity grid's padding to a Monday and its shading, and the plan and perk lists. The Mac code could not be compiled here; the workflow is the check. Nothing was seen on screen and no payment was made.

**Issues discovered:** the web app snoozes the invitation for a week; this app uses five days, as asked. The popups are kept per account on this Mac, not on the account.

**Issues fixed:** none.

**Follow-up to 14 (first look):** the "What Plus adds" cards were different heights (now all the same); only the text of a Settings tab was clickable (the whole row is now); and the white outline when the pointer is over a poster had gone since the right-click menu was added (the menu used a view laid over each poster, which looks like what got in the way; it now uses one event monitor and each poster only reports whether the pointer is over it).

**Build, again:** one run failed to link five times in a row, so a retry in the same job does not help (a retry from a clean build folder did not either, once). When it fails, the retry now also deletes the downloaded libraries (SwiftPM's cache) so they are fetched again, in case one of them is bad on that machine. This is a guess: runs on a new machine have always gone through.

**Follow-up to 14 (second look):** the poster outline only showed while scrolling, which means the pointer's movement was not being reported. The likely cause is the top bar having told the window to deliver every mouse movement (to bring the bar back when the pointer reaches the top); that is gone. The bar now comes back through an invisible strip along the top that only exists while the bar is hidden, and scrolling still hides it. The top bar is bigger too (logo 42 points, pills at 17 points, a 46 point profile picture) and shrinks only when the window is narrow.


## 15 -- The remaining Settings tabs: Home Rows, Subtitles, Audio, Updates

**Status:** Written; see the build result below. Not tried against the real account or on screen.

**Context:** These Settings tabs showed "coming in a later update" (Updates showed only the version).

**Changes:**
- Settings > Home Rows: every row Home can build, in the chosen order, each with a switch and "N titles" and up and down arrows (the web app's `moveRow`, as `HomeRowOrder.move`). Changes show at once and are saved to the account's settings row (whole-row PUT, as for Blocked Genres), and put back if the save fails. Switching a row changes the Home banner's pool too.
- Settings > Subtitles: a Subtitles switch and the default language (the web app's list, System Default first). Settings > Audio: the preferred audio language (Automatic first). Both are kept on the account. The mpv player reads them when a video starts (`alang`, `slang`, and no subtitle track chosen unless the switch is on; the player's own menu still switches tracks). The Mac built-in player does not use them.
- Settings > Updates: asks GitHub for the latest release of `MikeC444/ArcTV-Mac`, compares it with the running version and, if newer, shows the notes with Download (the .dmg) and Release page links. Until a release is published GitHub answers 404, which reads as "You're up to date".
- Sounds is removed from the sidebar: the Mac app has no interface sounds.

**Tests performed:** unit tests for moving a row (including the ends and an unknown id), the language lists, comparing versions, and reading a GitHub release reply (notes, download link, newer, same, no release, server error). The Mac code could not be compiled here; the Build and test workflow is the check. Nothing was seen on screen and the update check was not run against a real release.

**Issues discovered:** the repository's releases endpoint answered 404 from this sandbox, so how the check behaves on a published release is untested. The app does not install updates itself; it links to the download.

**Issues fixed:** none.

**Follow-up to 15 (first look):** the first Home row sat too far below the banner, with empty picture under the buttons. The banner is shorter (62% of the window, at least 500 points, was 74% and 620) and the first row overlaps it more (70 points, was 44). Not seen on screen.

**Follow-up to 15 (title bar):** a black strip showed above the Home banner, where the window's title bar sits. The Home page now ignores the top safe area, so the banner picture runs to the top edge of the window under the traffic-light buttons. Only Home was changed; not seen on screen.

## 16 -- A built-in torrent engine

**Status:** Written; see the build result below. Never run: no torrent has been streamed, and the app was not opened.

**Context:** Torrent-only streams (no web link, just a hash, which is what Torrentio gives without a debrid service) were listed greyed out ("not supported in this app yet"). The Fire TV app plays them with libtorrent (libtorrent4j); this does the same on the Mac.

**Changes:**
- `Sources/CTorrent`: a small C face on libtorrent 2.1 (`ctorrent.h`, `ctorrent.cpp`): start a magnet link, read the file list, choose the file (only that file downloads, in order), ask whether a byte range has arrived, and ask for the pieces from a byte on first (piece deadlines, used when the player seeks). Built with the flags `pkg-config --cflags libtorrent-rasterbar` prints. Homebrew supplies the library (`brew install libtorrent-rasterbar`, added to both workflows).
- `TorrentEngine`: gets the file list (gives up after two minutes with "No one is sharing this torrent..."), picks the video (the addon's file index if it is a video; for an episode the file that names S01E02 or 1x02; else the biggest video), starts a local web server, and waits for the first 6 MB (gives up after three minutes). `TorrentStreamServer` listens on 127.0.0.1 only and answers GET/HEAD with byte ranges; each range waits until its pieces have arrived. The player is simply handed that address, so mpv and the built-in player need no changes. The files are deleted when playback stops, the source page is left, or the next torrent starts.
- Sources page: torrents are clickable ("Torrent · streams inside Arc TV"), with a progress screen (finding peers, connected peers, speed) and Cancel; a failure is shown at the top. Direct links still sort first, and Smart source picking still only picks direct links, which surely play. Remembering the last source now includes torrents (matched by hash).
- The magnet link is built from the stream's hash, name and the trackers the addon lists (`sources`, "tracker:" entries).
- Packaging: the app now copies libtorrent, libssl and libcrypto into `Contents/Frameworks`, points the program at them (`install_name_tool`), and fails if any Homebrew path is left.
- **Cost:** Homebrew's libtorrent is Apple Silicon only and built for macOS 14, so the app is no longer a universal build and now needs macOS 14 or later (`LSMinimumSystemVersion` 14.0, README and release notes say so). Intel Macs and macOS 13 are no longer supported. Building libtorrent and OpenSSL for both chips ourselves would bring them back, at the cost of a much longer build.

**Tests performed:** unit tests for the magnet link (hash, name, de-duplicated trackers), which sources count as torrents, choosing the file (hint, episode, biggest, none) and reading `Range` headers. The Mac code, the C++ and the packaging script could not be compiled or run here; the Build and test workflow is the check. No torrent was streamed and nothing was seen on screen.

**Issues discovered:** the C++ and Swift built on the CI Mac (the first build failed on a Swift concurrency error in the server, now fixed). One existing test assumed a torrent can never be picked as the remembered source; it now checks that only a source with neither a link nor a hash is skipped. Open questions that only a real run answers: whether the copied libraries load inside the app, how quickly a popular and an unpopular torrent start, and whether seeking inside an MKV is quick enough. Two players asking for different ranges at once (a start and the end of an MP4) share one set of piece deadlines, so the last request wins.

**Issues fixed:** none.

## 17 -- Select a source matches the web app; the torrent loading screen

**Status:** Written; see the build result below. Not seen on screen.

**Context:** Asked for the source page to look like the web app (artwork behind it, the title's details and poster on the left, filters) and for a torrent to open a player-like screen at once with the artwork, the logo and the progress.

**Changes:**
- Select a source: the title's artwork darkened behind the page; on the left the Back button, poster, year, logo (or name), genres and length, description and "What are sources?"; on the right the heading, quality pills (All Sources, 4K, 1080p, 720p, Other), "Sort by" (Quality, Seeders, Size; one tap goes to the next), and the sources as cards: a quality badge in its colour with REMUX/BluRay/WEB-DL/etc. beneath, the release name, the video format and HDR, seeders and sound, the size and addon, a play button, and "Recommended" on the best direct source. The web app's page also has "MP4 & web formats" / "Plays on this device" switches, device-support notes and a safety footer; those are about what a browser can play and are not copied.
- The release-name reading (seeders from the "👤" line, source tag, codec and HDR, sound, size) and the filter and sort rules are in ArcTVCore (`SourceListing`) with tests.
- Torrent loading: choosing a torrent now covers the window at once with the title's artwork, its logo (or name) and, centred under it, the status (finding people, connections and speed) with Cancel. It is drawn by the source page, not by the player itself, so there is no player until the first part has arrived.

**Tests performed:** unit tests for reading release names and for the filters and sorts. The Mac code could not be compiled here; the Build and test workflow is the check. Nothing was seen on screen.

**Issues discovered:** none yet.

**Issues fixed:** none.

**Follow-up to 17 (first look):** the list sat too close to the poster panel and the artwork was too dark. The list is moved right (the left panel is 340 points wide and the list starts 90 points further in) and the darkening over the artwork is lighter (strongest on the left, where the text is). Not seen on screen.

**Follow-up to 17 (matching the web layout):** the source list now runs to the right edge (the left panel is 37% of the window wide, the list fills the rest less a 22 point gutter, as on the web app), and "What are sources?" sits in a box. A movie's page is laid out like the web app's: the artwork covers the whole window (the dark fade at the bottom is lighter), the heading block is unchanged, the cast sits bottom left, and from about a third of the way across the IMDb rating sits above "You May Also Like". Shows keep their seasons and episodes below the buttons. Not seen on screen.

**Follow-up to 17 (You May Also Like):** a movie's "You May Also Like" now sits under the cast and runs the whole width of the window (the rating stays at the top right), and its cards are bigger (250 by 150 points, were 176 by 106). Shows are unchanged. Not seen on screen.

## 18 -- Smaller gaps: update pop-up, QR sign-in, search arrow keys, blocked titles, "Watching as"

**Status:** Written; see the build result below. Not seen on screen, and the QR flow was not tried against the real server.

**Context:** The list of what was still missing from the Mac app compared with the web and Fire TV apps.

**Changes:**
- Update pop-up: six seconds after Home has loaded, once per launch, the app asks GitHub for the latest release (`UpdateCheck`) and, if it is newer, shows its notes with Download (the .dmg, else the release page), Later and "Skip this version" (remembered by version). Quiet when offline or when there is no release.
- QR sign-in: "Scan a QR code to sign in from your phone" on the start page. The app asks the server for a code (`POST /auth/qr/create` with this Mac's device id), draws the activation link as a QR code (Core Image), and asks `GET /auth/qr/status` every two seconds until the phone has signed in (the tokens come back once and are kept like a normal sign-in), the code runs out ("New code") or the person goes Back.
- Search: Up and Down move through the suggestions, Return opens the marked one (or searches, with none marked), Escape closes the list. Done with a key monitor because the SwiftUI key handler needs macOS 14.
- Settings > Account: "Watching as <profile>" (with "(kids)") when the account has more than one profile.

**Not done, and why:**
- Blocked titles on a title page: this was built (a "Not available on this profile" page) and then taken out again on request: blocked genres only keep a title out of Home, Movies and TV Shows, and a search still finds it and opens it.
- Parental controls: the web app's Plus list also says "Coming soon" (locks on genres and titles); there is nothing defined to match yet.
- The black strip on Movies, TV Shows, Search and My List: those pages have no picture at the top, so the strip is the page's own colour and I saw no reason to change them. If it shows, a screenshot would settle it.

**Tests performed:** unit tests for reading the QR status answers (pending, expired, completed with the tokens, garbage) and for a title being blocked by genre. The Mac code could not be compiled or run here; the Build and test workflow is the check. Nothing was seen on screen.

**Issues discovered:** none yet.

**Issues fixed:** none.

**Follow-up to 18 (first look):** the sign-in page was pushed off the left edge of a tall window: the filled picture reported its own, larger size, which made the page wider than the window. The picture is now sized from the window. Search results no longer leave out blocked genres, and the "Not available on this profile" page is gone (see above). (A "Preview the update pop-up" button was added to Settings > Updates for a look and then removed on request.) Not seen on screen.

## 19 -- Downloads (Arc TV Plus) and the revised Plus popups

**Status:** Written; see the build result below. Nothing was downloaded and nothing was seen on screen.

**Context:** The web app has a Plus Download button (web only so far). It was asked for on the Mac app too, with the Plus popups updated to list it.

**Changes:**
- A Download button on a title's page (Plus members): a panel lists the files the account's addons give as plain web links (what a debrid service gives; torrents can't be saved this way), best quality first and the smallest file first within a quality (`DownloadChoices`). A movie downloads the movie; a show downloads the episode Play would start. Choosing a file saves it to the Downloads folder (`DownloadManager`, a URLSession download with progress, Cancel, "Show in Finder"; names are made safe and never overwrite an existing file). The panel also lists what is being saved.
- Settings > Arc TV Plus lists "Download" with a "Web and Mac only" tag. Both Plus popups list Downloads; the welcome tour has a new id, so members see the revised tour once more.
- Settings > Updates has "Preview the Plus invitation" and "Preview the Plus welcome"; closing a preview is not counted as seeing it. A demo switch (`AppModel.plusPopupDemo`, now off) also shows the invitation by itself three seconds after Home loads, and also skips the update check while it is on.

**Tests performed:** unit tests for the order of choices (quality, then size; torrents left out) and for file names. The Mac code could not be compiled or run here; the Build and test workflow is the check.

**Issues discovered:** the web app's wording says "web only" in its Plus popups and perk list; it still needs changing there (a separate repository).

**Issues fixed:** none.

## 20 -- The player laid out like the Fire TV app's VLC player; a spinner while seeking

**Status:** Written; see the build result below. Not seen on screen.

**Context:** Asked for a loading symbol in the middle of the player while scrubbing, and for the player to copy the Fire TV app's VLC player layout (`VlcControlsNetflix.kt`).

**Changes:**
- Layout (from the Kotlin file): a 170 point fade at the top and a 250 point fade at the bottom; top left a row of round outlined icons (Back, back 10 seconds, forward 10 seconds); top right the title's logo (up to 280 by 56 points, else the name) with "S1 E2 • title" for an episode; along the bottom a 48 point round white Play / Pause button, the time played, a thin timeline and the time left (with a minus sign), and under it a centred row of grey pills.
- Pills: Audio and Subtitles (shown when the video has tracks), Episodes (shows only: pick a season and episode, its sources open), Player (switch between the Arc TV player and the Mac's, carrying on from the same spot) and Sources (back to the source list), as on the Fire TV. Speed is a pill too, which the Fire TV layout does not have; the volume slider and full-screen button are gone from the bar (Up and Down change the volume, F or a double click goes full screen).
- Spinner: it shows in the middle whenever mpv is waiting for the stream (`paused-for-cache`) or is seeking (`seeking`, new). A jump shows it at once, before mpv answers, and clears it by itself after eight seconds if mpv never reports the seek.
- The timeline is a thin bar that thickens and shows a dot under the pointer; click or drag to jump.

**Tests performed:** none new (this is screen code). The Mac code could not be compiled or run here; the Build and test workflow is the check. Nothing was seen on screen.

**Issues discovered:** none yet. The Mac's built-in player (`BuiltInPlayerView`) still has its old controls.

**Issues fixed:** none.

**Follow-up to 20 (first look):** the Back and 10-second icons at the top left no longer sit in circles. A full-screen button (it flips to "exit full screen") sits at the bottom left, level with the pills. Esc is no longer a back button while a video is on screen: the Back pills of the pages underneath (which stay alive behind the player) only answer Esc when nothing is playing, and in the player Esc only leaves full screen. Not seen on screen.

## 21 -- A faster mpv player; the full-screen button on the right

**Status:** Written; see the build result below. Nothing was timed or seen on screen, so how much faster it is, or whether it still stutters on your files, is not known.

**Context:** "The mpv player is really slow and laggy." Nothing could be measured here. These are the likely causes in the code, fixed without a profiler.

**Changes:**
- The position (sent by mpv with every frame, 24 to 60 times a second) re-drew the whole control bar each time. It is now passed on only when it moves by a quarter of a second, which is as often as the clock and bar can show.
- Pictures were drawn on the main thread once for every frame mpv announced. Requests are now folded together, so at most one is waiting, and the picture is drawn once per refresh.
- The video surface was drawn in full retina pixels (four times the pixels of a plain window). It is now drawn at the window's size in points; video loses nothing visible, since a 1080p or 4K picture is at least as big as the window.
- mpv is told to use the hardware decoder (VideoToolbox) and cheap scaling, with the costly extras off (fancy scalers, debanding, dithering, interpolation, HDR peak search), a 300 MB read-ahead (60 seconds) and a 100 MB buffer behind, and to drop late frames rather than fall behind. Option names this mpv doesn't know are ignored.
- Mouse movement over the player restarts the hide timer at most twice a second.
- The full-screen button moved from the bottom left to the bottom right.

**Tests performed:** none (player code). The Mac code could not be compiled or run here; the Build and test workflow is the check.

**Issues discovered:** the cause of the lag was not measured. If it is still slow, the next step is to time it on your Mac (which file, which Mac, how much CPU and GPU).

**Issues fixed:** none confirmed.

## 22 -- Player menus, next episode and autoplay, torrent buffer and storage settings, the app icon

**Status:** Written; see the build result below. Nothing was seen on screen or run.

**Context:** The system pop-up lists for Audio and Subtitles looked plain; Next episode, the torrent buffer and storage settings (from the Fire TV app) and an app icon were asked for.

**Changes:**
- Player menus: Audio, Subtitles, Speed, Episodes and Player now open a dark card above their pill (title, a tick on the chosen row, the language as a small tag at the right, a highlight under the pointer). Subtitles starts with Off. Episodes shows the seasons as numbers with the chosen season's episodes under them. A click anywhere else closes it; the controls stay up while one is open.
- Next episode: for a show, a white "Next episode" button (with its S/E and title) shows in the last minute and starts it; when an episode ends, the next one starts by itself if Settings > Player > Auto play next episode is on (it is by default, and is the account's `autoplayNextEpisode`), else the player goes back. The next episode takes the best source that plays at once (a direct link) without asking, and shows the list only when there is none (`PlayTarget.autoPick`). Next is the following episode of the season, else the first of the next season (`MetaDetail.episode(after:)`).
- Torrent buffer (Small, Normal, Large) sets how much must arrive before the video starts (3, 6 or 16 MB) and how many pieces ahead are asked for first (12, 24 or 64). Torrent storage limit (5, 10, 20, 50 GB or no limit, 50 by default): a file bigger than the limit won't start, and says so. Both are in Settings > Player and kept on this Mac. `ct_stream_from` takes the number of pieces.
- App icon: the logo's mark on a dark rounded square (`Resources/AppIcon-1024.png`, `AppIcon.icns` built from it, 16 to 1024 points); the package script copies it in and names it in the Info file.

**Tests performed:** unit tests for the next episode (same season, next season, none, specials skipped) and the torrent settings. The Mac code could not be compiled or run here; the Build and test workflow is the check. The icon was looked at as an image only, not in the Dock or Finder.

**Issues discovered:** the logo file is small (121 pixels high), so the mark is enlarged in the icon and its edges are a little soft at the largest sizes. A sharper copy of the logo would fix that.

**Issues fixed:** none.

## 23 -- Loading placeholders and the player's loading picture

**Status:** Written; see the build result below. Nothing was seen on screen.

**Context:** The player showed a black screen and a spinner while it started, and several pages showed a lone spinner while they loaded.

**Changes:**
- Player: until the first picture plays, the title's artwork (darkened) and its logo (or name) fill the window with the spinner below, then fade out.
- Select a source: while the addons answer, the quality pills and sort button and eight source cards are drawn in grey in the same places and sizes as the real ones (78 point cards, 70 by 46 badge, 34 point pills), under the real heading; the poster and details on the left were already real.
- A title's page: grey placeholders for the cast (round photos with names) and, for a show, the seasons and episode cards, until the full details come back.
- My List and search: the grid of grey posters instead of a spinner; stats: grey tiles. Home, Movies and TV Shows already had them.

**Tests performed:** none (screen code). The Mac code could not be compiled or run here; the Build and test workflow is the check. The placeholders' sizes were taken from the real views' sizes in the code, not measured on screen.

**Issues discovered:** none yet.

**Issues fixed:** none.

**Follow-up to 21 (full screen):** going full screen while a video was playing left the picture at its old, smaller size with black all around it. The picture was sized from OpenGL's last viewport, which does not change when the window does. It is now sized from the view itself on every draw, the OpenGL surface is told when the view is resized (`reshape`), and a new picture is drawn after a resize. Not seen on screen.

**Follow-up to 22 (app icon):** the icon did not show on the app. The packaged app has the icon file and names it in its Info file (checked in the script), so the likely case is a run from Xcode or `swift run`, where there is no app bundle to carry an icon. The icon is now also embedded in the program (512 pixels) and set as the Dock icon when the app starts, so it shows either way. Not seen in the Dock; if it still doesn't show on the packaged app from the DMG, macOS may be holding an old icon: moving the app out of Applications and back, or `killall Dock Finder`, refreshes it.

## 24 -- The three-dots animation and the logo on the profile picker

**Status:** Written; see the build result below. Nothing was seen on screen.

**Changes:**
- Who's watching: the Arc TV logo (48 points) now sits centred above the heading, in the same column as the profiles, so it shows with them at any window size. (It was in the top left corner before, apart from them.)
- The three dots on a title's page: the dots turn a quarter turn and swell with a bounce; a ring spreads from them and fades; the buttons (Watched, My List, and for Plus Like and Not for me) then fly out one after another from the dots' side, each growing from a small spot with a spring and a 0.065 second step between them. Closing them is quicker, in the reverse order.

**Tests performed:** none (animation). The Mac code could not be compiled or run here; the Build and test workflow is the check. The animation was not seen.

**Issues discovered:** none yet.

**Issues fixed:** none.

**Follow-up to 24 (episodes):** the episode cards on a show's page were cut off: the row showed the pictures with their bottoms sliced and no titles or descriptions. The sideways scroll view settled on too small a height for its lazily built cards. The row now has a fixed height (252 points) that holds the picture, the title and two lines of description. Not seen on screen.
