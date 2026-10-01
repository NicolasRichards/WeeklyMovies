import Foundation

class CacheService {
    static let shared = CacheService()

    private let cacheDirectory: URL

    // Cache files are keyed by the week's actual start date (e.g. week_2026-06-08.json).
    // Keying by relative offset would serve a previous calendar week's data once
    // the real week rolls over.
    private let keyFormatter = DateFormatter.tmdbDateOnly()

    init() {
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        cacheDirectory = caches.appendingPathComponent("WeeklyMovies", isDirectory: true)
        try? FileManager.default.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
        // One-time cleanup of legacy cache files: offset-keyed (week_0.json)
        // and the pre-country-split date-only format (week_2026-10-05.json).
        removeLegacyOffsetFiles()
    }

    func saveMovies(_ movies: [Movie], forWeekStart weekStart: Date, countryCode: String) {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(movies) else { return }
        try? data.write(to: cacheURL(for: weekStart, countryCode: countryCode))
    }

    func loadMovies(forWeekStart weekStart: Date, countryCode: String) -> [Movie]? {
        guard let data = try? Data(contentsOf: cacheURL(for: weekStart, countryCode: countryCode)) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode([Movie].self, from: data)
    }

    func clearCache() {
        try? FileManager.default.removeItem(at: cacheDirectory)
        try? FileManager.default.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
    }

    // Keyed by week start AND country: a cache file written under one country
    // must never answer a lookup for a different country. Without the country
    // in the key, a country change synced via iCloud while the app wasn't
    // running could leave a stale, wrong-region cache file on disk that a later
    // non-force-refresh (e.g. navigating to an adjacent week) would read as if
    // it were current data for the new country.
    private func cacheURL(for weekStart: Date, countryCode: String) -> URL {
        cacheDirectory.appendingPathComponent("week_\(keyFormatter.string(from: weekStart))_\(countryCode).json")
    }

    private func removeLegacyOffsetFiles() {
        guard let files = try? FileManager.default.contentsOfDirectory(at: cacheDirectory, includingPropertiesForKeys: nil) else { return }
        // Matches both the original offset-keyed format (week_0.json) and the
        // date-only format used before cache files were also keyed by country
        // (week_2026-10-05.json) — neither is ever read again under the
        // current week_<date>_<countryCode>.json scheme.
        let legacyPattern = #"^week_(-?\d+|\d{4}-\d{2}-\d{2})\.json$"#
        for file in files where file.lastPathComponent.range(of: legacyPattern, options: .regularExpression) != nil {
            try? FileManager.default.removeItem(at: file)
        }
    }
}
