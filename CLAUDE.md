# Working notes for Claude Code

- This is the native **Mac** app for Arc TV (Swift, SwiftUI, Swift Package Manager; unsigned DMG). It follows the Fire TV app (`MikeC444/ArcTV-AndroidTV`,
  which also holds the backend in `server/`) for what it does, and the web app (`MikeC444/ArcTV-Web`, see `docs/PARITY.md` there) for how it looks.
  The phone app (`MikeC444/arctv-mobileapk`) is the third reference. A change made on web is recorded in the web repo's `docs/PARITY.md`; say what is
  still open for the Mac app.
- Add each user-visible change as a bullet under `## Unreleased` in `RELEASE_NOTES.md` (plain, short, upbeat, no file names: it is what the update
  pop-up shows). Log engineering work in `CHANGELOG.md` as `## <N> -- <title>` with Status, Context, Changes, Tests performed, Issues discovered,
  Issues fixed. Update an existing unreleased bullet/entry in place when refining the same feature. Cutting a release is a separate, explicit request.
- This sandbox is Linux with no Swift or Xcode: code here can't be compiled or run. Builds are checked by pushing to a branch and reading the
  **Build and test (Arc TV Mac)** workflow run on GitHub (a macOS runner). Say plainly what was and was not built or run, and never imply a screen
  was seen when it was not.
