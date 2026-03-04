import Foundation

class CacheService {
    static let shared = CacheService()

    private let cacheDirectory: URL

    init() {
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        cacheDirectory = caches.appendingPathComponent("WeeklyMovies", isDirectory: true)
        try? FileManager.default.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
    }

    func saveMovies(_ movies: [Movie], forWeekOffset offset: Int) {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(movies) else { return }
        try? data.write(to: cacheURL(for: offset))
    }

    func loadMovies(forWeekOffset offset: Int) -> [Movie]? {
        guard let data = try? Data(contentsOf: cacheURL(for: offset)) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode([Movie].self, from: data)
    }

    func clearCache() {
        try? FileManager.default.removeItem(at: cacheDirectory)
        try? FileManager.default.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
    }

    private func cacheURL(for offset: Int) -> URL {
        cacheDirectory.appendingPathComponent("week_\(offset).json")
    }
}
