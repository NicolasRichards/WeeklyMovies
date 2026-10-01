import Foundation
import SwiftUI
import Observation

@Observable
@MainActor
class MoviesViewModel {
    var movies: [Movie] = []
    var isLoading = false
    var errorMessage: String?
    var currentWeekOffset = 0
    var filter: MovieFilter = .theatrical
    var wideOnly: Bool = UserDefaults.standard.object(forKey: "wideOnly") as? Bool ?? true {
        didSet { UserDefaults.standard.set(wideOnly, forKey: "wideOnly") }
    }
    var countryCode: String {
        didSet {
            UserDefaults.standard.set(countryCode, forKey: "selectedCountryCode")
            NSUbiquitousKeyValueStore.default.set(countryCode, forKey: "selectedCountryCode")
        }
    }

    init() {
        let kvStore = NSUbiquitousKeyValueStore.default
        kvStore.synchronize()
        // Captured before countryCode's own didSet (which doesn't fire for this
        // initial assignment) can overwrite it, so a change picked up here can
        // still be detected below.
        let previousCountryCode = UserDefaults.standard.string(forKey: "selectedCountryCode")
        countryCode = kvStore.string(forKey: "selectedCountryCode")
                      ?? previousCountryCode
                      ?? Locale.current.region?.identifier
                      ?? "US"
        if let previousCountryCode, previousCountryCode != countryCode {
            // A country change synced via iCloud while the app was fully
            // closed is picked up directly here rather than through
            // setCountry(), which is the only other place that clears the
            // (now per-country) cache — do it here too so the old country's
            // cache files don't accumulate forever.
            CacheService.shared.clearCache()
        }
        UserDefaults.standard.set(countryCode, forKey: "selectedCountryCode")
        NotificationCenter.default.addObserver(
            forName: NSUbiquitousKeyValueStore.didChangeExternallyNotification,
            object: kvStore,
            queue: .main
        ) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in
                self.applyExternalCountryChange()
            }
        }
    }

    /// Apply a country change synced from another device.
    private func applyExternalCountryChange() {
        guard let newCode = NSUbiquitousKeyValueStore.default.string(forKey: "selectedCountryCode"),
              newCode != countryCode else { return }
        setCountry(newCode)
    }

    /// Flag emoji for the current country code.
    var countryFlag: String {
        countryCode.uppercased().unicodeScalars
            .compactMap { UnicodeScalar(127397 + $0.value) }
            .reduce("") { $0 + String($1) }
    }

    /// Switch to a new country, wipe the cache, and reload.
    func setCountry(_ code: String) {
        countryCode = code
        CacheService.shared.clearCache()
        Task { await loadMovies(forceRefresh: true) }
    }

    enum MovieFilter: String, CaseIterable {
        case theatrical = "Theater"
        case streaming = "Streaming"
    }

    var filteredMovies: [Movie] {
        switch filter {
        case .theatrical:
            return movies.filter { $0.isTheatrical && (!wideOnly || $0.isWideRelease) }
        case .streaming:
            return movies.filter { !$0.streamingProviders.isEmpty }
        }
    }

    var weekTitle: String {
        switch currentWeekOffset {
        case 0:  return "This Week"
        case -1: return "Last Week"
        case 1:  return "Next Week"
        case 2:  return "In Two Weeks"
        case 3:  return "In Three Weeks"
        case 4:  return "In Four Weeks"
        default: return "\(abs(currentWeekOffset)) Weeks Ago"
        }
    }

    var weekDateRange: String {
        let dates = weekDates(for: currentWeekOffset)
        let style = Date.FormatStyle.dateTime.month(.abbreviated).day()
        return "\(dates.start.formatted(style)) – \(dates.end.formatted(style))"
    }

    var canGoToNextWeek: Bool { currentWeekOffset < 4 }
    var canGoToPreviousWeek: Bool { currentWeekOffset > -4 }

    // MARK: - Actions

    // Incremented on every load; in-flight loads bail out when a newer one starts,
    // so rapid week navigation can't mix two weeks' results or poison the cache.
    private var loadGeneration = 0

    func loadMovies(forceRefresh: Bool = false) async {
        loadGeneration += 1
        let generation = loadGeneration
        let dates = weekDates(for: currentWeekOffset)
        let pastWeek = currentWeekOffset < 0

        if !forceRefresh, let cached = CacheService.shared.loadMovies(forWeekStart: dates.start, countryCode: countryCode) {
            movies = cached
            // A load already in flight bails out on its generation check without
            // clearing isLoading, so this newest load has to own the flag even
            // when it returns early. Otherwise the spinner never goes away.
            isLoading = false
            errorMessage = nil
            return
        }

        isLoading = true
        errorMessage = nil
        movies = []

        do {
            async let theatricalOutcome = fetchOutcome {
                try await TMDbService.shared.fetchTheatricalReleases(
                    weekStart: dates.start, weekEnd: dates.end, countryCode: countryCode)
            }
            async let streamingOutcome = fetchOutcome {
                try await TMDbService.shared.fetchStreamingReleases(
                    weekStart: dates.start, weekEnd: dates.end, countryCode: countryCode)
            }

            // Each fetch's outcome is captured independently so one failing
            // doesn't discard a result the other already completed — unless
            // that failure is a cancellation, which always propagates rather
            // than being treated as a tolerable partial failure.
            let (theatricalResult, streamingResult) = await (theatricalOutcome, streamingOutcome)
            guard generation == loadGeneration else { return }

            let theatricalResults: [TMDbMovieResult]
            let streamingResults: [TMDbMovieResult]
            // Set only when exactly one side failed — tolerated so the other
            // side's good results aren't discarded, but still surfaced below
            // so a missing category (e.g. every streaming-only release) isn't
            // silently absent with no explanation.
            var listFetchError: Error?
            switch (theatricalResult, streamingResult) {
            case (.failure(let error), _) where error is CancellationError:
                throw error
            case (_, .failure(let error)) where error is CancellationError:
                throw error
            case (.success(let t), .success(let s)):
                (theatricalResults, streamingResults) = (t, s)
            case (.success(let t), .failure(let error)):
                (theatricalResults, streamingResults) = (t, [])
                listFetchError = error
            case (.failure(let error), .success(let s)):
                (theatricalResults, streamingResults) = ([], s)
                listFetchError = error
            case (.failure(let error), .failure):
                throw error
            }

            // Deduplicate: streaming first, theatrical overwrites (so isTheatrical is accurate)
            var movieMap: [Int: (TMDbMovieResult, Bool)] = [:]
            for m in streamingResults  { movieMap[m.id] = (m, false) }
            for m in theatricalResults { movieMap[m.id] = (m, true) }

            let allEntries = Array(movieMap.values)

            // Pre-compute date bounds used in the per-batch filter.
            let weekEnd1Day = Calendar.current.date(byAdding: .day, value: 1, to: dates.end)!
            // Secondary staleness guard: TMDb's release_dates data is incomplete
            // for smaller markets, so old movies can appear if their only recorded
            // country entry is a recent re-release. Requiring the movie's global
            // primary release to be within the past month blocks those false positives
            // while still allowing legitimate delayed international rollouts.
            let oneMonthAgo = Calendar.current.date(byAdding: .month, value: -1, to: Date())!
            // No explicit time zone: this is compared against dates.start/weekEnd1Day,
            // which are themselves device-local-midnight values, so it must stay
            // on the device default to match that grid.
            let primaryDateFmt = DateFormatter.tmdbDateOnly()

            // Fetch details in batches to stay under the 40 req/10s rate limit.
            // Task group returns raw TMDbMovieDetails; toMovie() is called after
            // the group completes so it runs on the main actor (Swift 6 safe).
            // Each child task catches its own error (a dropped connection, a
            // timeout, a decode failure) and returns nil instead of throwing —
            // a throwing task group aborts the whole group on the first error,
            // which used to discard every other movie already fetched in that
            // batch and skip every batch after it, with nothing shown to the user.
            // 8 concurrent requests every 2s works out to exactly 4 req/s — the
            // 40 req/10s budget above — regardless of how many batches a busy
            // week needs. The previous 15-per-batch/0.5s pacing only bounded the
            // gap *between* batches: a week with several batches of fast-returning
            // requests could burst well past 40 req/10s and get rate-limited.
            let batches = allEntries.chunked(into: 8)
            var detailFetchFailures = 0
            var lastDetailFetchError: Error?
            for (batchIndex, batch) in batches.enumerated() {
                let (batchDetails, batchOutcomes) = await withTaskGroup(
                    of: Result<(TMDbMovieDetails, Bool), Error>.self
                ) { group in
                    for (result, isTheatrical) in batch {
                        group.addTask {
                            do {
                                let details = try await TMDbService.shared.fetchMovieDetails(id: result.id)
                                return .success((details, isTheatrical))
                            } catch {
                                return .failure(error)
                            }
                        }
                    }
                    var pairs: [(TMDbMovieDetails, Bool)] = []
                    var outcomes: [Result<(TMDbMovieDetails, Bool), Error>] = []
                    for await outcome in group {
                        outcomes.append(outcome)
                        if case .success(let pair) = outcome { pairs.append(pair) }
                    }
                    return (pairs, outcomes)
                }
                guard generation == loadGeneration else { return }
                // A cancellation checkpoint on every batch, not just non-last
                // ones — the inter-batch sleep below is skipped for the last
                // batch, so without this a cancellation during the final batch
                // had no checkpoint before falling through as if the load had
                // completed normally.
                try Task.checkCancellation()
                detailFetchFailures += batch.count - batchDetails.count
                for outcome in batchOutcomes {
                    if case .failure(let error) = outcome, !(error is CancellationError), lastDetailFetchError == nil {
                        lastDetailFetchError = error
                    }
                }
                // Two-pass filter:
                // 1. The movie's FIRST-EVER release in the selected country must
                //    fall within the displayed week.
                // 2. The movie's global primary release must be within the past month.
                //    This is a safety net for markets where TMDb's historical
                //    release_dates data is sparse — it prevents old movies with a
                //    new re-release event this week from slipping through.
                let firstReleaseThisWeek = batchDetails.filter { (details, _) in
                    // Drop shorts (≤ 40 min runtime, matching IMDB's definition).
                    // A nil runtime means TMDb doesn't have it yet — let it through.
                    if let runtime = details.runtime, runtime <= 40 { return false }
                    // Accept if ANY release in the country falls within the week —
                    // using the minimum date would drop movies that had a premiere
                    // the week before their wide theatrical release.
                    // Fall back to global primary release date if no country entry exists.
                    let inWindow = details.hasRelease(for: countryCode, from: dates.start, to: weekEnd1Day)
                        || primaryDateFmt.date(from: details.releaseDate).map { $0 >= dates.start && $0 < weekEnd1Day } ?? false
                    guard inWindow else { return false }
                    // For past weeks, require the global primary release to be recent
                    // to block old movies with sparse re-release data slipping through.
                    // For current/future weeks, skip this guard so upcoming films appear.
                    if pastWeek,
                       let globalDate = primaryDateFmt.date(from: details.releaseDate),
                       globalDate < oneMonthAgo { return false }
                    return true
                }
                let newMovies = firstReleaseThisWeek.map { (details, isTheatrical) in
                    details.toMovie(
                        isTheatrical: isTheatrical,
                        isWideRelease: details.hasWideRelease(for: countryCode, from: dates.start, to: weekEnd1Day),
                        countryCode: countryCode,
                        weekStart: dates.start,
                        weekEnd: weekEnd1Day
                    )
                }
                // Append each batch immediately so the list populates progressively.
                movies = (movies + newMovies).sorted { $0.voteCount > $1.voteCount }

                if batchIndex < batches.count - 1 {
                    try await Task.sleep(nanoseconds: 2_000_000_000) // 2s between batches
                }
            }

            // Every single detail fetch failed (e.g. the connection dropped
            // mid-load) — don't let an empty list read as "no releases this week"
            // with no explanation, and don't let it overwrite a previously-good
            // cache with this empty result either.
            let totalFailure = !allEntries.isEmpty && detailFetchFailures == allEntries.count
            if !totalFailure {
                CacheService.shared.saveMovies(movies, forWeekStart: dates.start, countryCode: countryCode)
            }
            if totalFailure {
                errorMessage = lastDetailFetchError?.localizedDescription
                    ?? "Couldn't load this week's movies. Please try again."
            } else if detailFetchFailures > 0 {
                // A partial failure used to be completely silent, with the
                // incomplete list cached and shown as if the week were complete.
                errorMessage = "Showing \(movies.count) of \(allEntries.count) movies — some failed to load."
            } else if let listFetchError {
                errorMessage = listFetchError.localizedDescription
            }

        } catch {
            guard generation == loadGeneration else { return }
            // A forced refresh's own `movies = []` above can tear down the view
            // hosting the in-flight .refreshable/.task that started this very
            // load, cancelling it — that's benign and shouldn't read as a
            // real failure the way a genuine network error should.
            if error is CancellationError {
                if generation == loadGeneration { isLoading = false }
                return
            }
            errorMessage = error.localizedDescription
            // Fall back to a stale cache so the screen isn't empty, but keep
            // errorMessage set — ContentView shows it as a small "offline" banner
            // over the list rather than presenting old data as if it just loaded.
            if let cached = CacheService.shared.loadMovies(forWeekStart: dates.start, countryCode: countryCode) {
                movies = cached
            }
        }

        if generation == loadGeneration {
            isLoading = false
        }
    }

    func goToPreviousWeek() {
        currentWeekOffset -= 1
        Task { await loadMovies() }
    }

    func goToNextWeek() {
        guard canGoToNextWeek else { return }
        currentWeekOffset += 1
        Task { await loadMovies() }
    }

    func goToCurrentWeek() {
        currentWeekOffset = 0
        Task { await loadMovies() }
    }

    // MARK: - Helpers

    private func fetchOutcome<T>(_ operation: @Sendable () async throws -> T) async -> Result<T, Error> {
        do { return .success(try await operation()) }
        catch { return .failure(error) }
    }

    func weekDates(for offset: Int) -> (start: Date, end: Date) {
        var calendar = Calendar(identifier: .gregorian)
        calendar.firstWeekday = 2 // Monday
        let baseDate = Calendar.current.date(byAdding: .weekOfYear, value: offset, to: Date())!
        let comps = calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: baseDate)
        let start = calendar.date(from: comps)!
        let end = calendar.date(byAdding: .day, value: 6, to: start)!
        return (start, end)
    }
}

extension Array {
    func chunked(into size: Int) -> [[Element]] {
        stride(from: 0, to: count, by: size).map {
            Array(self[$0 ..< Swift.min($0 + size, count)])
        }
    }
}
