import Foundation
import SwiftUI

@MainActor
class MoviesViewModel: ObservableObject {
    @Published var movies: [Movie] = []
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var currentWeekOffset = 0
    @Published var filter: MovieFilter = .all

    enum MovieFilter: String, CaseIterable {
        case all = "All"
        case theatrical = "Theater"
        case streaming = "Streaming"
    }

    var filteredMovies: [Movie] {
        switch filter {
        case .all:        return movies
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
                weekStart: dates.start, weekEnd: dates.end)
            async let streaming = TMDbService.shared.fetchStreamingReleases(
                weekStart: dates.start, weekEnd: dates.end)

            let (theatricalResults, streamingResults) = try await (theatrical, streaming)

            // Deduplicate: streaming first, theatrical overwrites (so isTheatrical is accurate)
            var movieMap: [Int: (TMDbMovieResult, Bool)] = [:]
            for m in streamingResults  { movieMap[m.id] = (m, false) }
            for m in theatricalResults { movieMap[m.id] = (m, true) }

            let allEntries = Array(movieMap.values)
            var detailedMovies: [Movie] = []

            // Fetch details in batches to stay under the 40 req/10s rate limit
            for batch in allEntries.chunked(into: 15) {
                let batchMovies = try await withThrowingTaskGroup(of: Movie?.self) { group in
                    for (result, isTheatrical) in batch {
                        group.addTask {
                            let details = try await TMDbService.shared.fetchMovieDetails(id: result.id)
                            return details.toMovie(isTheatrical: isTheatrical)
                        }
                    }
                    var results: [Movie] = []
                    for try await movie in group {
                        if let movie { results.append(movie) }
                    }
                    return results
                }
                detailedMovies.append(contentsOf: batchMovies)

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
