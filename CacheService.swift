import Foundation

class CacheService {
    static let shared = CacheService()

    private let cacheDirectory: URL

    // Cache files are keyed by the week's actual start date (e.g. week_2026-06-08.json).
    // Keying by relative offset would serve a previous calendar week's data once
    // the real week rolls over.
    private let keyFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.locale = Locale(identifier: "en_US_POSIX")
        return f
    }()

    init() {
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        cacheDirectory = caches.appendingPathComponent("WeeklyMovies", isDirectory: true)
        try? FileManager.default.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
        // One-time cleanup of legacy offset-keyed files (week_0.json etc.)
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
        for file in files where file.lastPathComponent.range(of: #"^week_-?\d+\.json$"#, options: .regularExpression) != nil {
            try? FileManager.default.removeItem(at: file)
        }
    }
}
