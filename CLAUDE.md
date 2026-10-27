# WeeklyMovies

iOS, iPadOS and macOS app (SwiftUI, Swift 6, iOS 26.2+ / macOS 26.2+) that lists the current week's theatrical and streaming movie releases for a chosen country, with a watchlist, seen list and ratings. Live on the App Store. Data comes from the TMDb API, using a key each user supplies.

## Workflow

The owner runs Claude Code locally on a Mac, in this folder, and opens the project in Xcode to find the latest changes. The owner does not use Terminal, so do not ask them to run git or shell commands; do the git work yourself. This folder is the only source; `~/Documents/Claude App Notes/WeeklyMovies/` holds the owner's notes and assets and is read-only reference, never code.

- Build from the command line with `xcodebuild -project WeeklyMovies.xcodeproj -scheme WeeklyMovies -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO build` (verified on the owner's Mac, 2026-10-27). Do not report a build as passing unless one actually ran. There is no test target.
- Cloud sessions work on a fresh clone with no Xcode: say plainly that a change is unbuilt, push a `claude/...` branch, and merge it into `main` rather than copying its commits onto `main`.
- Most Swift files sit at the repo root and are listed in `project.pbxproj` by hand; only the `WeeklyMovies/` subfolder is a synchronized group. Adding a file at the root therefore needs a `project.pbxproj` edit; say so when you make one.
- Before committing, review your own diff for regressions. A fix commit is itself worth reviewing: one fix batch here introduced 15 new bugs. Commit and push to `main` when the work is done.

## Layout

- Repo root: `ContentView`, `MoviesViewModel`, `TMDbService`, `Models` (includes the shared `DateFormatter.tmdbDateOnly(timeZone:)`), `CacheService`, `MovieCardView`, `MovieDetailView`, `MyFilmsView`, `RateFilmSheet`, `WatchlistStore`, `UserFilm`, `CountryPickerView`, `APIKeySetupView`, `KeychainHelper`, `AboutView`, `TipJar`, `WeeklyMovies.storekit`, `AppStoreSubmission.md`
- `WeeklyMovies/`: app entry (`WeeklyMoviesApp.swift`) and entitlements
- `AppStoreScreenshots/`, `docs/` (GitHub Pages privacy and support page)

## Conventions and gotchas

- TMDb is the source of truth. Discrepancies against BoxOfficeMojo (missing titles, tiny releases with no votes) are TMDb data, not app bugs; don't add vote or popularity floors.
- Releases come from TMDb discover with `release_date.gte/lte` + `region` + `with_release_type`, not `primary_release_date`. Theatrical is types `1|2|3` (type 1 is needed for day-of-release premieres); streaming is type `4` with both `region` and `watch_region`. All pages are fetched.
- A movie is in the week if any of its releases in the country falls in the window, and the date shown is that in-window, country-specific date. Shorts (40 minutes or less) are dropped. Sorted by vote count, descending.
- TMDb dates are midnight UTC. Format and compare them in UTC with the Gregorian calendar (`DateFormatter.tmdbDateOnly`); local time zones shifted dates a day early west of UTC.
- Detail fetches are paced to TMDb's rate limit (batches of 8, 2 seconds apart). A failed fetch drops only that movie; an error shows only if every fetch failed, and stale cached results show a "Showing saved results" banner.
- The cache is keyed by week start and country code. The app always force-refreshes on open; the cache is only an error fallback.
- The TMDb key is per user (bring-your-own, set up in `APIKeySetupView`), stored in the Keychain and synced through iCloud Keychain. The country syncs through `NSUbiquitousKeyValueStore`. App Review approved the bring-your-own-key onboarding; keep it.
- Tip jar: consumable tips `NickRichards.WeeklyMovies.tip.{small,medium,large}`; the transaction listener runs from the root view in the `App` body. The shared scheme points at the StoreKit file as `../../WeeklyMovies.storekit`.
- Version bumps are their own commits, titled like `Bump to 1.7 (8)`. The owner archives and uploads from Xcode, then creates the version in App Store Connect (uploading a build does not create it).
- The repo is public on purpose (GitHub Pages), so never commit secrets.
