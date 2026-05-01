import Foundation

class TMDbService {
    static let shared = TMDbService()
    private let baseURL = "https://api.themoviedb.org/3"

    private var apiKey: String {
        KeychainHelper.shared.getAPIKey() ?? ""
    }

    // MARK: - Weekly Releases

    func fetchTheatricalReleases(weekStart: Date, weekEnd: Date) async throws -> [TMDbMovieResult] {
        try await fetchAllPages(baseItems: [
            URLQueryItem(name: "api_key", value: apiKey),
            URLQueryItem(name: "region", value: "US"),
            URLQueryItem(name: "primary_release_date.gte", value: dateString(from: weekStart)),
            URLQueryItem(name: "primary_release_date.lte", value: dateString(from: weekEnd)),
            URLQueryItem(name: "with_release_type", value: "1|2|3"),
            URLQueryItem(name: "sort_by", value: "popularity.desc")
        ])
    }

    func fetchStreamingReleases(weekStart: Date, weekEnd: Date) async throws -> [TMDbMovieResult] {
        try await fetchAllPages(baseItems: [
            URLQueryItem(name: "api_key", value: apiKey),
            URLQueryItem(name: "region", value: "US"),
            URLQueryItem(name: "primary_release_date.gte", value: dateString(from: weekStart)),
            URLQueryItem(name: "primary_release_date.lte", value: dateString(from: weekEnd)),
            URLQueryItem(name: "with_release_type", value: "4"),
            URLQueryItem(name: "sort_by", value: "popularity.desc")
        ])
    }

    private func fetchAllPages(baseItems: [URLQueryItem]) async throws -> [TMDbMovieResult] {
        var all: [TMDbMovieResult] = []
        var page = 1
        var totalPages = 1
        repeat {
            var items = baseItems
            items.append(URLQueryItem(name: "page", value: "\(page)"))
            var components = URLComponents(string: "\(baseURL)/discover/movie")!
            components.queryItems = items
            let response: TMDbMovieListResponse = try await fetch(url: components.url!)
            all.append(contentsOf: response.results)
            totalPages = response.totalPages
            page += 1
        } while page <= totalPages
        return all
    }

    // MARK: - Movie Details

    func fetchMovieDetails(id: Int) async throws -> TMDbMovieDetails {
        var components = URLComponents(string: "\(baseURL)/movie/\(id)")!
        components.queryItems = [
            URLQueryItem(name: "api_key", value: apiKey),
            URLQueryItem(name: "append_to_response", value: "videos,credits,watch/providers,reviews,external_ids")
        ]
        return try await fetch(url: components.url!)
    }

    // MARK: - Private

    private func fetch<T: Decodable>(url: URL) async throws -> T {
        let (data, response) = try await URLSession.shared.data(from: url)
        guard let http = response as? HTTPURLResponse else {
            throw TMDbError.invalidResponse
        }
        switch http.statusCode {
        case 200:
            break
        case 401:
            throw TMDbError.unauthorized
        case 429:
            throw TMDbError.rateLimited
        default:
            throw TMDbError.httpError(http.statusCode)
        }
        return try JSONDecoder().decode(T.self, from: data)
    }

    private func dateString(from date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: date)
    }
}

enum TMDbError: LocalizedError {
    case invalidResponse
    case unauthorized
    case rateLimited
    case httpError(Int)

    var errorDescription: String? {
        switch self {
        case .invalidResponse: return "Invalid server response."
        case .unauthorized: return "Invalid API key. Please check your TMDb API key in settings."
        case .rateLimited: return "Too many requests. Please wait a moment and try again."
        case .httpError(let code): return "Server error (\(code))."
        }
    }
}
