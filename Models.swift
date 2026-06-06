import Foundation

// MARK: - App Models

struct Movie: Identifiable, Codable, Equatable {
    let id: Int
    let title: String
    let releaseDate: Date
    let posterPath: String?
    let overview: String
    let voteAverage: Double
    let voteCount: Int
    var imdbID: String?
    var isTheatrical: Bool
    var isWideRelease: Bool
    var streamingProviders: [StreamingProvider]
    var reviews: [Review]
    var director: String?
    var cast: [String]
    var trailerKey: String?

    var posterURL: URL? {
        guard let path = posterPath else { return nil }
        return URL(string: "https://image.tmdb.org/t/p/w500\(path)")
    }

    var imdbURL: URL? {
        if let id = imdbID, !id.isEmpty {
            return URL(string: "https://www.imdb.com/title/\(id)/")
        }
        // TMDb sometimes hasn't linked the IMDB ID yet for new releases —
        // fall back to a title search so the link always works.
        let query = title.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        return URL(string: "https://www.imdb.com/find?q=\(query)&s=tt&ttype=ft")
    }

    var trailerURL: URL? {
        guard let key = trailerKey else { return nil }
        return URL(string: "https://www.youtube.com/watch?v=\(key)")
    }

    var releaseDateFormatted: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MM/dd/yyyy"
        return formatter.string(from: releaseDate)
    }
}

struct StreamingProvider: Identifiable, Codable, Equatable {
    let id: Int
    let name: String
    let logoPath: String
    var link: String?

    var logoURL: URL? {
        URL(string: "https://image.tmdb.org/t/p/w92\(logoPath)")
    }
}

struct Review: Identifiable, Codable, Equatable {
    let id: String
    let author: String
    let content: String
    let rating: Double?
    let url: String?
    let createdAt: Date
}

// MARK: - TMDb API Response Models

struct TMDbMovieListResponse: Codable {
    let results: [TMDbMovieResult]
    let totalPages: Int
    let totalResults: Int

    enum CodingKeys: String, CodingKey {
        case results
        case totalPages = "total_pages"
        case totalResults = "total_results"
    }
}

struct TMDbMovieResult: Codable {
    let id: Int
    let title: String
    let releaseDate: String
    let posterPath: String?
    let overview: String
    let voteAverage: Double
    let voteCount: Int

    enum CodingKeys: String, CodingKey {
        case id, title, overview
        case releaseDate = "release_date"
        case posterPath = "poster_path"
        case voteAverage = "vote_average"
        case voteCount = "vote_count"
    }
}

struct TMDbMovieDetails: Codable {
    let id: Int
    let title: String
    let releaseDate: String
    let posterPath: String?
    let overview: String
    let voteAverage: Double
    let voteCount: Int
    let runtime: Int?
    let externalIds: TMDbExternalIds?
    let credits: TMDbCredits?
    let videos: TMDbVideos?
    let reviews: TMDbReviewsResponse?
    let watchProviders: TMDbWatchProvidersResponse?
    let releaseDates: TMDbReleaseDatesResponse?

    enum CodingKeys: String, CodingKey {
        case id, title, overview, credits, videos, reviews, runtime
        case releaseDate = "release_date"
        case posterPath = "poster_path"
        case voteAverage = "vote_average"
        case voteCount = "vote_count"
        case externalIds = "external_ids"
        case watchProviders = "watch/providers"
        case releaseDates = "release_dates"
    }

    /// Returns true if the movie has a wide (type 3) release in the given country within [start, end).
    func hasWideRelease(for countryCode: String, from start: Date, to end: Date) -> Bool {
        let isoFormatter = ISO8601DateFormatter()
        isoFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let fallback = ISO8601DateFormatter()
        fallback.formatOptions = [.withInternetDateTime]
        func parse(_ s: String) -> Date? { isoFormatter.date(from: s) ?? fallback.date(from: s) }

        guard let entries = releaseDates?.results
            .first(where: { $0.iso31661 == countryCode })?.releaseDates else { return false }
        return entries.contains { $0.type == 3 && parse($0.releaseDate).map { $0 >= start && $0 < end } ?? false }
    }

    /// Returns true if the movie has any release in the given country within [start, end).
    func hasRelease(for countryCode: String, from start: Date, to end: Date) -> Bool {
        // TMDb timestamps look like "2015-12-25T00:00:00.000Z" — fractional seconds
        // are NOT handled by ISO8601DateFormatter's default options, so we add them.
        let isoFormatter = ISO8601DateFormatter()
        isoFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let fallback = ISO8601DateFormatter()
        fallback.formatOptions = [.withInternetDateTime]
        func parse(_ s: String) -> Date? { isoFormatter.date(from: s) ?? fallback.date(from: s) }

        guard let entries = releaseDates?.results
            .first(where: { $0.iso31661 == countryCode })?.releaseDates else { return false }
        return entries.compactMap { parse($0.releaseDate) }.contains { $0 >= start && $0 < end }
    }

    /// Returns the earliest release date within [start, end) for the given country.
    func releaseDate(for countryCode: String, in start: Date, to end: Date) -> Date? {
        let isoFormatter = ISO8601DateFormatter()
        isoFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let fallback = ISO8601DateFormatter()
        fallback.formatOptions = [.withInternetDateTime]
        func parse(_ s: String) -> Date? { isoFormatter.date(from: s) ?? fallback.date(from: s) }

        return releaseDates?.results
            .first(where: { $0.iso31661 == countryCode })?
            .releaseDates
            .compactMap { parse($0.releaseDate) }
            .filter { $0 >= start && $0 < end }
            .min()
    }

    func toMovie(isTheatrical: Bool, isWideRelease: Bool, countryCode: String, weekStart: Date, weekEnd: Date) -> Movie {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        // Use the country release date that falls within the displayed week so the
        // date shown matches when the movie opens locally, not an earlier foreign premiere.
        let date = releaseDate(for: countryCode, in: weekStart, to: weekEnd)
            ?? dateFormatter.date(from: releaseDate)
            ?? Date()

        let director = credits?.crew.first(where: { $0.job == "Director" })?.name
        let cast = Array(
            (credits?.cast ?? [])
                .sorted { $0.order < $1.order }
                .prefix(5)
                .map(\.name)
        )
        let trailerKey = videos?.results.first(where: { $0.isYouTubeTrailer })?.key

        let countryProviders = watchProviders?.results?[countryCode]
        let providers: [StreamingProvider] = (countryProviders?.flatrate ?? []).map {
            StreamingProvider(
                id: $0.providerId,
                name: $0.providerName,
                logoPath: $0.logoPath,
                link: countryProviders?.link
            )
        }

        let isoFormatter = ISO8601DateFormatter()
        let movieReviews: [Review] = (reviews?.results ?? []).map { r in
            Review(
                id: r.id,
                author: r.author,
                content: r.content,
                rating: r.authorDetails?.rating,
                url: r.url,
                createdAt: isoFormatter.date(from: r.createdAt) ?? Date()
            )
        }

        return Movie(
            id: id,
            title: title,
            releaseDate: date,
            posterPath: posterPath,
            overview: overview,
            voteAverage: voteAverage,
            voteCount: voteCount,
            imdbID: externalIds?.imdbId,
            isTheatrical: isTheatrical,
            isWideRelease: isWideRelease,
            streamingProviders: providers,
            reviews: movieReviews,
            director: director,
            cast: cast,
            trailerKey: trailerKey
        )
    }
}

struct TMDbExternalIds: Codable {
    let imdbId: String?
    enum CodingKeys: String, CodingKey { case imdbId = "imdb_id" }
}

struct TMDbCredits: Codable {
    let cast: [TMDbCastMember]
    let crew: [TMDbCrewMember]
}

struct TMDbCastMember: Codable {
    let name: String
    let order: Int
}

struct TMDbCrewMember: Codable {
    let name: String
    let job: String
}

struct TMDbVideos: Codable {
    let results: [TMDbVideo]
}

struct TMDbVideo: Codable {
    let key: String
    let site: String
    let type: String

    var isYouTubeTrailer: Bool {
        site == "YouTube" && type == "Trailer"
    }
}

struct TMDbReviewsResponse: Codable {
    let results: [TMDbReview]
}

struct TMDbReview: Codable {
    let id: String
    let author: String
    let content: String
    let url: String
    let createdAt: String
    let authorDetails: TMDbAuthorDetails?

    enum CodingKeys: String, CodingKey {
        case id, author, content, url
        case createdAt = "created_at"
        case authorDetails = "author_details"
    }
}

struct TMDbAuthorDetails: Codable {
    let rating: Double?
}

// MARK: - Release Dates (used to find first-ever US release)

struct TMDbReleaseDatesResponse: Codable {
    let results: [TMDbCountryRelease]
}

struct TMDbCountryRelease: Codable {
    let iso31661: String
    let releaseDates: [TMDbReleaseDateEntry]

    enum CodingKeys: String, CodingKey {
        case iso31661 = "iso_3166_1"
        case releaseDates = "release_dates"
    }
}

struct TMDbReleaseDateEntry: Codable {
    let releaseDate: String  // ISO 8601 e.g. "2026-02-28T00:00:00.000Z"
    let type: Int            // 1=Premiere 2=Limited 3=Theatrical 4=Digital 5=Physical 6=TV

    enum CodingKeys: String, CodingKey {
        case releaseDate = "release_date"
        case type
    }
}

struct TMDbWatchProvidersResponse: Codable {
    // Keys are ISO-3166-1 alpha-2 country codes e.g. "US", "GB", "FR"
    let results: [String: TMDbCountryProviders]?
}

struct TMDbCountryProviders: Codable {
    let link: String?
    let flatrate: [TMDbProvider]?
}

// Minimal response model used only to validate an API key.
struct TMDbConfigurationResponse: Codable {
    let images: TMDbConfigurationImages
    struct TMDbConfigurationImages: Codable {
        let baseUrl: String
        enum CodingKeys: String, CodingKey { case baseUrl = "base_url" }
    }
}

struct TMDbProvider: Codable {
    let providerId: Int
    let providerName: String
    let logoPath: String

    enum CodingKeys: String, CodingKey {
        case providerId = "provider_id"
        case providerName = "provider_name"
        case logoPath = "logo_path"
    }
}
