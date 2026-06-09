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
        didSet { UserDefaults.standard.set(countryCode, forKey: "selectedCountryCode") }
    }

    init() {
        countryCode = UserDefaults.standard.string(forKey: "selectedCountryCode")
                      ?? Locale.current.region?.identifier
                      ?? "US"
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
        let f = DateFormatter()
        f.dateFormat = "MMM d"
        return "\(f.string(from: dates.start)) – \(f.string(from: dates.end))"
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

        if !forceRefresh, let cached = CacheService.shared.loadMovies(forWeekStart: dates.start) {
            movies = cached
            return
        }

        isLoading = true
        errorMessage = nil
        movies = []

        do {
            async let theatrical = TMDbService.shared.fetchTheatricalReleases(
                weekStart: dates.start, weekEnd: dates.end, countryCode: countryCode)
            async let streaming = TMDbService.shared.fetchStreamingReleases(
                weekStart: dates.start, weekEnd: dates.end, countryCode: countryCode)

            let (theatricalResults, streamingResults) = try await (theatrical, streaming)
            guard generation == loadGeneration else { return }

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
            let primaryDateFmt: DateFormatter = {
                let f = DateFormatter()
                f.dateFormat = "yyyy-MM-dd"
                // POSIX locale: parsing API dates must not depend on the device's
                // calendar setting (Buddhist/Japanese calendars shift the year).
                f.locale = Locale(identifier: "en_US_POSIX")
                return f
            }()

            // Fetch details in batches to stay under the 40 req/10s rate limit.
            // Task group returns raw TMDbMovieDetails; toMovie() is called after
            // the group completes so it runs on the main actor (Swift 6 safe).
            for batch in allEntries.chunked(into: 15) {
                let batchDetails = try await withThrowingTaskGroup(
                    of: (TMDbMovieDetails, Bool).self
                ) { group in
                    for (result, isTheatrical) in batch {
                        group.addTask {
                            let details = try await TMDbService.shared.fetchMovieDetails(id: result.id)
                            return (details, isTheatrical)
                        }
                    }
                    var pairs: [(TMDbMovieDetails, Bool)] = []
                    for try await pair in group { pairs.append(pair) }
                    return pairs
                }
                guard generation == loadGeneration else { return }
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

                if allEntries.count > 15 {
                    try await Task.sleep(nanoseconds: 500_000_000) // 0.5s between batches
                }
            }

            CacheService.shared.saveMovies(movies, forWeekStart: dates.start)

        } catch {
            guard generation == loadGeneration else { return }
            errorMessage = error.localizedDescription
            // Fall back to stale cache silently
            if let cached = CacheService.shared.loadMovies(forWeekStart: dates.start) {
                movies = cached
                errorMessage = nil
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
