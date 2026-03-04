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
        guard let id = imdbID, !id.isEmpty else { return nil }
        return URL(string: "https://www.imdb.com/title/\(id)/")
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
    let externalIds: TMDbExternalIds?
    let credits: TMDbCredits?
    let videos: TMDbVideos?
    let reviews: TMDbReviewsResponse?
    let watchProviders: TMDbWatchProvidersResponse?

    enum CodingKeys: String, CodingKey {
        case id, title, overview, credits, videos, reviews
        case releaseDate = "release_date"
        case posterPath = "poster_path"
        case voteAverage = "vote_average"
        case voteCount = "vote_count"
        case externalIds = "external_ids"
        case watchProviders = "watch/providers"
    }

    func toMovie(isTheatrical: Bool) -> Movie {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        let date = dateFormatter.date(from: releaseDate) ?? Date()

        let director = credits?.crew.first(where: { $0.job == "Director" })?.name
        let cast = Array(
            (credits?.cast ?? [])
                .sorted { $0.order < $1.order }
                .prefix(5)
                .map(\.name)
        )
        let trailerKey = videos?.results.first(where: { $0.isYouTubeTrailer })?.key

        let providers: [StreamingProvider] = (watchProviders?.results?.us?.flatrate ?? []).map {
            StreamingProvider(
                id: $0.providerId,
                name: $0.providerName,
                logoPath: $0.logoPath,
                link: watchProviders?.results?.us?.link
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

struct TMDbWatchProvidersResponse: Codable {
    let results: TMDbWatchProviderCountries?
}

struct TMDbWatchProviderCountries: Codable {
    let us: TMDbUSProviders?
    enum CodingKeys: String, CodingKey { case us = "US" }
}

struct TMDbUSProviders: Codable {
    let link: String?
    let flatrate: [TMDbProvider]?
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
