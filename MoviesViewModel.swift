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
        case .theatrical: return movies.filter { $0.isTheatrical }
        case .streaming:  return movies.filter { !$0.streamingProviders.isEmpty }
        }
    }

    var weekTitle: String {
        switch currentWeekOffset {
        case 0:  return "This Week"
        case -1: return "Last Week"
        default: return "\(abs(currentWeekOffset)) Weeks Ago"
        }
    }

    var weekDateRange: String {
        let dates = weekDates(for: currentWeekOffset)
        let f = DateFormatter()
        f.dateFormat = "MMM d"
        return "\(f.string(from: dates.start)) – \(f.string(from: dates.end))"
    }

    var canGoToNextWeek: Bool { currentWeekOffset < 0 }

    // MARK: - Actions

    func loadMovies(forceRefresh: Bool = false) async {
        if !forceRefresh, let cached = CacheService.shared.loadMovies(forWeekOffset: currentWeekOffset) {
            movies = cached
            return
        }

        isLoading = true
        errorMessage = nil
        let dates = weekDates(for: currentWeekOffset)

        do {
            async let theatrical = TMDbService.shared.fetchTheatricalReleases(
                weekStart: dates.start, weekEnd: dates.end, countryCode: countryCode)
            async let streaming = TMDbService.shared.fetchStreamingReleases(
                weekStart: dates.start, weekEnd: dates.end, countryCode: countryCode)

            let (theatricalResults, streamingResults) = try await (theatrical, streaming)

            // Deduplicate: streaming first, theatrical overwrites (so isTheatrical is accurate)
            var movieMap: [Int: (TMDbMovieResult, Bool)] = [:]
            for m in streamingResults  { movieMap[m.id] = (m, false) }
            for m in theatricalResults { movieMap[m.id] = (m, true) }

            let allEntries = Array(movieMap.values)
            var detailedMovies: [Movie] = []

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
                // Two-pass filter:
                // 1. The movie's FIRST-EVER release in the selected country must
                //    fall within the displayed week.
                // 2. The movie's global primary release must be within the past month.
                //    This is a safety net for markets where TMDb's historical
                //    release_dates data is sparse — it prevents old movies with a
                //    new re-release event this week from slipping through.
                let firstReleaseThisWeek = batchDetails.filter { (details, _) in
                    guard let first = details.firstReleaseDate(for: countryCode),
                          first >= dates.start && first < weekEnd1Day else { return false }
                    if let globalDate = primaryDateFmt.date(from: details.releaseDate),
                       globalDate < oneMonthAgo { return false }
                    return true
                }
                detailedMovies.append(contentsOf: firstReleaseThisWeek.map {
                    $0.0.toMovie(isTheatrical: $0.1, countryCode: countryCode)
                })

                if allEntries.count > 15 {
                    try await Task.sleep(nanoseconds: 500_000_000) // 0.5s between batches
                }
            }

            let sorted = detailedMovies.sorted { $0.voteAverage > $1.voteAverage }
            movies = sorted
            CacheService.shared.saveMovies(sorted, forWeekOffset: currentWeekOffset)

        } catch {
            errorMessage = error.localizedDescription
            // Fall back to stale cache silently
            if let cached = CacheService.shared.loadMovies(forWeekOffset: currentWeekOffset) {
                movies = cached
                errorMessage = nil
            }
        }

        isLoading = false
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
