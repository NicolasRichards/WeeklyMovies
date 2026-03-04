# Weekly Movies

A native iOS app (Swift + SwiftUI) that shows movies releasing each week — both theatrical and streaming — powered by [The Movie Database (TMDb) API](https://www.themoviedb.org/documentation/api).

## Requirements

- **Xcode 15+** (Swift 5.9+)
- **iOS 16.0+** deployment target
- iPhone or iPad (simulator or physical device)
- A free **TMDb API key** — get one at [themoviedb.org](https://www.themoviedb.org/settings/api)

## Build & Run

1. Open the project folder in Xcode (open any `.swift` file or add the folder as a package).
2. Select your target device or simulator.
3. Press **⌘R** (or Product → Run).
4. On first launch, tap the **key icon** to enter your TMDb API key.

> If running on a physical device, set your Development Team in *Signing & Capabilities*.

## Usage

- **Week navigation** — Use the left/right arrows to browse previous or upcoming release weeks. Tap *Jump to Current Week* to return.
- **Filter** — Toggle between All, Theatrical, and Streaming releases using the segmented control.
- **Movie detail** — Tap any movie to see the director, cast, reviews, streaming providers, and links to IMDB and YouTube trailers.
- **Refresh** — Pull to refresh or tap the refresh button in the toolbar.

## Features

- Weekly release browsing with date-range navigation
- Theatrical vs. streaming filter
- Movie detail view with cast, director, TMDb rating, and reviews
- Streaming provider availability (US)
- IMDB and YouTube trailer deep links
- API key stored securely in Keychain
- Response caching to minimize API calls

## Project Structure

```
WeeklyMovies/
├── Models.swift              — App + TMDb API data models
├── MoviesViewModel.swift     — @MainActor ObservableObject; week navigation + filtering
├── TMDbService.swift         — TMDb API client (discover, details, watch providers)
├── CacheService.swift        — On-disk response cache
├── KeychainHelper.swift      — Secure API key storage
├── ContentView.swift         — Main list view with week nav and filter
├── MovieCardView.swift       — Compact movie row card
├── MovieDetailView.swift     — Full detail screen
└── APIKeySetupView.swift     — First-launch API key entry sheet
```
