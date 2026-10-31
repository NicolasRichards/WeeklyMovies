import Foundation
import SwiftUI
import Observation

@Observable
@MainActor
class MoviesViewModel {
    var movies: [Movie] = []
    var isLoading = false
    var errorMessage: String?
    /// With `errorMessage`: the refresh failed and `movies` are saved results,
    /// as opposed to fresh results that are incomplete.
    var showingSavedResults = false
    /// The last load was rejected with a 401: the key is invalid or revoked.
    var apiKeyRejected = false
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
        Task { await loadMovies() }
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
    /// The load in flight, cancelled when a newer one starts so a superseded
    /// week stops sending requests.
    private var loadTask: Task<Void, Never>?
    /// Week start and country that `movies` belongs to; nil until something
    /// for the current selection has loaded.
    private var loadedSelection: String?
    /// The real current week as of the last load, to spot a rollover.
    private var lastLoadedDuringWeekOf: Date?

    /// Whether the list for the current week and country is on screen (possibly empty).
    var hasLoadedSelection: Bool { loadedSelection != nil }

    /// Always fetches fresh; a cached complete week is shown meanwhile and is
    /// the fallback if the fetch fails.
    /// Identifies the week and country a load is for.
    private var currentSelection: String {
        "\(weekDates(for: currentWeekOffset).start.timeIntervalSince1970)_\(countryCode)"
    }
    private var loadingSelection: String?

    func loadMovies() async {
        guard KeychainHelper.shared.hasAPIKey else { return }
        // A refresh while this same week is already loading joins that load
        // rather than restarting it and throwing away what it has fetched.
        if isLoading, let loadTask, loadingSelection == currentSelection {
            await loadTask.value
            return
        }
        loadingSelection = currentSelection
        loadGeneration += 1
        let generation = loadGeneration
        loadTask?.cancel()
        // Unstructured, so it's cancelled only by a newer load — not by the
        // caller's .refreshable or .task going away.
        let task = Task { await performLoad(generation: generation) }
        loadTask = task
        await task.value
    }

    private func performLoad(generation: Int) async {
        guard generation == loadGeneration else { return }
        // Captured once: a country change mid-load must not file this load's
        // results under the new country's cache.
        let country = countryCode
        let dates = weekDates(for: currentWeekOffset)
        let pastWeek = currentWeekOffset < 0
        let selection = "\(dates.start.timeIntervalSince1970)_\(country)"
        lastLoadedDuringWeekOf = weekDates(for: 0).start

        // A refresh keeps the current list up (and its List, whose .refreshable
        // started this load, mounted) until new results arrive. A different week
        // or country shows its cached complete week meanwhile, if there is one.
        if loadedSelection != selection {
            if let cached = CacheService.shared.loadMovies(forWeekStart: dates.start, countryCode: country) {
                movies = cached
                loadedSelection = selection
            } else {
                movies = []
                loadedSelection = nil
            }
        }
        // Only a list started from nothing fills in batch by batch; otherwise
        // the list on screen is replaced once, when the load finishes.
        let showsProgressively = loadedSelection == nil
        isLoading = true
        errorMessage = nil
        showingSavedResults = false
        apiKeyRejected = false

        do {
            async let theatricalOutcome = fetchOutcome {
                try await TMDbService.shared.fetchTheatricalReleases(
                    weekStart: dates.start, weekEnd: dates.end, countryCode: country)
            }
            async let streamingOutcome = fetchOutcome {
                try await TMDbService.shared.fetchStreamingReleases(
                    weekStart: dates.start, weekEnd: dates.end, countryCode: country)
            }

            // Each fetch's outcome is captured independently so one failing
            // doesn't discard a result the other already completed. Only this
            // load's own cancellation (the check below) abandons both.
            let (theatricalResult, streamingResult) = await (theatricalOutcome, streamingOutcome)
            guard generation == loadGeneration else { return }
            try Task.checkCancellation()

            let theatricalResults: [TMDbMovieResult]
            let streamingResults: [TMDbMovieResult]
            // Set only when exactly one side failed — tolerated so the other
            // side's good results aren't discarded, but still surfaced below
            // so a missing category (e.g. every streaming-only release) isn't
            // silently absent with no explanation.
            var listFetchError: Error?
            var failedListName = ""
            switch (theatricalResult, streamingResult) {
            case (.success(let t), .success(let s)):
                (theatricalResults, streamingResults) = (t, s)
            case (.success(let t), .failure(let error)):
                (theatricalResults, streamingResults) = (t, [])
                listFetchError = error
                failedListName = "Streaming"
            case (.failure(let error), .success(let s)):
                (theatricalResults, streamingResults) = ([], s)
                listFetchError = error
                failedListName = "Theatrical"
            case (.failure(let error), .failure):
                throw error
            }

            // Deduplicate: streaming first, theatrical overwrites (so isTheatrical is accurate)
            var movieMap: [Int: (TMDbMovieResult, Bool)] = [:]
            for m in streamingResults  { movieMap[m.id] = (m, false) }
            for m in theatricalResults { movieMap[m.id] = (m, true) }

            let allEntries = Array(movieMap.values)

            // Pre-compute date bounds used in the per-batch filter.
            // TMDb release dates are midnight UTC, so the window must sit on the
            // UTC grid too: rebuild the displayed week's local calendar days as
            // UTC midnights. (Comparing against local-midnight bounds dropped
            // Monday releases west of UTC and let the next Monday slip in.)
            var utcCalendar = Calendar(identifier: .gregorian)
            utcCalendar.timeZone = TimeZone(identifier: "UTC")!
            func utcMidnight(ofLocalDay day: Date) -> Date {
                let c = Calendar.current.dateComponents([.year, .month, .day], from: day)
                return utcCalendar.date(from: c)!
            }
            let windowStart = utcMidnight(ofLocalDay: dates.start)
            let weekEnd1Day = utcCalendar.date(byAdding: .day, value: 1, to: utcMidnight(ofLocalDay: dates.end))!
            // Secondary staleness guard: TMDb's release_dates data is incomplete
            // for smaller markets, so old movies can appear if their only recorded
            // country entry is a recent re-release. Requiring the movie's global
            // primary release to be within the past month blocks those false positives
            // while still allowing legitimate delayed international rollouts.
            let oneMonthAgo = Calendar.current.date(byAdding: .month, value: -1, to: Date())!
            // UTC, to match the window bounds above.
            let primaryDateFmt = DateFormatter.tmdbDateOnly(timeZone: TimeZone(identifier: "UTC")!)

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
            var loaded: [Movie] = []
            var detailFetchFailures = 0
            var firstDetailFetchError: Error?
            for (batchIndex, batch) in batches.enumerated() {
                // Checked before every batch (i.e. after each 2s sleep), so a
                // superseded load never sends another round of requests.
                guard generation == loadGeneration else { return }
                try Task.checkCancellation()
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
                    if case .failure(let error) = outcome, firstDetailFetchError == nil {
                        firstDetailFetchError = error
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
                    let inWindow = details.releaseDate(for: country, in: windowStart, to: weekEnd1Day) != nil
                        || primaryDateFmt.date(from: details.releaseDate).map { $0 >= windowStart && $0 < weekEnd1Day } ?? false
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
                        isWideRelease: details.hasWideRelease(for: country, from: windowStart, to: weekEnd1Day),
                        countryCode: country,
                        weekStart: windowStart,
                        weekEnd: weekEnd1Day
                    )
                }
                loaded = (loaded + newMovies).sorted { $0.voteCount > $1.voteCount }
                if showsProgressively && !loaded.isEmpty { movies = loaded }

                if batchIndex < batches.count - 1 {
                    try await Task.sleep(nanoseconds: 2_000_000_000) // 2s between batches
                }
            }

            // Every single detail fetch failed (e.g. the connection dropped
            // mid-load) — don't let an empty list read as "no releases this
            // week"; fall back to saved results like any other failed refresh.
            if let firstDetailFetchError, detailFetchFailures == allEntries.count {
                throw firstDetailFetchError
            }

            movies = loaded
            loadedSelection = selection
            if detailFetchFailures == 0 && listFetchError == nil {
                // Only complete results are cached, so a fallback never passes
                // an incomplete week off as complete.
                CacheService.shared.saveMovies(loaded, forWeekStart: dates.start, countryCode: country)
            } else {
                var problems: [String] = []
                if let listFetchError {
                    problems.append("\(failedListName) releases couldn't load. \(Self.message(for: listFetchError))")
                }
                if detailFetchFailures > 0 {
                    // Counted on the same basis: movies whose details were fetched, before filtering.
                    problems.append("\(detailFetchFailures) of \(allEntries.count) movies couldn't load.")
                }
                errorMessage = problems.joined(separator: " ")
                apiKeyRejected = [listFetchError, firstDetailFetchError].contains { $0.map(Self.isUnauthorized) ?? false }
            }

        } catch {
            guard generation == loadGeneration else { return }
            // Only this task's own cancellation is benign; a URLError(.cancelled)
            // that arrives without it is reported like any other failure.
            if Task.isCancelled {
                isLoading = false
                return
            }
            errorMessage = Self.message(for: error)
            apiKeyRejected = Self.isUnauthorized(error)
            // Fall back to the cache, else the list already on screen for this
            // week, flagged as saved results rather than passed off as fresh.
            if let cached = CacheService.shared.loadMovies(forWeekStart: dates.start, countryCode: country) {
                movies = cached
            }
            showingSavedResults = !movies.isEmpty
            loadedSelection = movies.isEmpty ? nil : selection
        }

        if generation == loadGeneration {
            isLoading = false
        }
    }

    /// On returning to the foreground: the week shown is relative to today, so
    /// reload once the real week has rolled over since the last load.
    func reloadIfWeekRolledOver() {
        guard let lastLoadedDuringWeekOf,
              weekDates(for: 0).start != lastLoadedDuringWeekOf,
              KeychainHelper.shared.hasAPIKey else { return }
        Task { await loadMovies() }
    }

    /// The API key was removed: stop any load in flight and clear the list.
    func clearForMissingKey() {
        loadGeneration += 1
        loadTask?.cancel()
        movies = []
        loadedSelection = nil
        isLoading = false
        errorMessage = nil
        showingSavedResults = false
        apiKeyRejected = false
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

    /// URLError(.cancelled)'s own description is just "cancelled".
    private static func message(for error: Error) -> String {
        if error is CancellationError || (error as? URLError)?.code == .cancelled {
            return "Loading was interrupted. Please try again."
        }
        return error.localizedDescription
    }

    private static func isUnauthorized(_ error: Error) -> Bool {
        (error as? TMDbError) == .unauthorized
    }

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
