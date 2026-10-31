import Foundation

// MARK: - Shared Formatters

extension DateFormatter {
    /// A "yyyy-MM-dd" formatter for TMDb's plain calendar-date fields. POSIX
    /// locale so parsing/formatting never depends on the device's calendar
    /// identifier (a Buddhist/Japanese calendar would otherwise shift the year
    /// or fail to parse). Pass `timeZone` only when the string is being parsed
    /// as an absolute UTC calendar date rather than formatted/compared against
    /// a device-local date grid (those callers must leave it at the device default).
    static func tmdbDateOnly(timeZone: TimeZone? = nil) -> DateFormatter {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.locale = Locale(identifier: "en_US_POSIX")
        if let timeZone { f.timeZone = timeZone }
        return f
    }
}

extension String {
    /// Percent-encodes for use as a single URL query value. `.urlQueryAllowed`
    /// leaves "&", "+" and "=" alone, which would split or garble the query.
    var queryValueEncoded: String {
        var allowed = CharacterSet.urlQueryAllowed
        allowed.remove(charactersIn: "&+=#")
        return addingPercentEncoding(withAllowedCharacters: allowed) ?? ""
    }
}

// MARK: - App Models

/// TMDb poster widths, each the smallest that covers its view at 3x.
enum PosterSize: String {
    case w185, w342, w500

    func url(for path: String?) -> URL? {
        guard let path else { return nil }
        return URL(string: "https://image.tmdb.org/t/p/\(rawValue)\(path)")
    }
}

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

    var imdbURL: URL? {
        if let id = imdbID, !id.isEmpty {
            return URL(string: "https://www.imdb.com/title/\(id)/")
        }
        // TMDb sometimes hasn't linked the IMDB ID yet for new releases —
        // fall back to a title search so the link always works.
        let query = title.queryValueEncoded
        return URL(string: "https://www.imdb.com/find?q=\(query)&s=tt&ttype=ft")
    }

    var trailerURL: URL? {
        guard let key = trailerKey else { return nil }
        return URL(string: "https://www.youtube.com/watch?v=\(key)")
    }

    /// Locale-aware. A fixed "MM/dd/yyyy" pattern reads as day-first to most of
    /// the countries in the picker, and renders the wrong year outright on a
    /// device set to a Buddhist or Japanese calendar.
    ///
    /// Formatted in UTC: TMDb release dates are midnight-UTC calendar dates
    /// with no real time component, so formatting in the device's local time
    /// zone rolled every date back to the previous day for anyone west of UTC.
    var releaseDateFormatted: String {
        releaseDate.formatted(
            Date.FormatStyle(date: .abbreviated, time: .omitted, timeZone: TimeZone(identifier: "UTC")!)
        )
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
        guard let entries = releaseDates?.results
            .first(where: { $0.iso31661 == countryCode })?.releaseDates else { return false }
        return entries.contains { $0.type == 3 && TMDbTimestamp.parse($0.releaseDate).map { $0 >= start && $0 < end } ?? false }
    }

    /// Returns the earliest release date within [start, end) for the given
    /// country, or nil if it has no release in that window.
    func releaseDate(for countryCode: String, in start: Date, to end: Date) -> Date? {
        releaseDates?.results
            .first(where: { $0.iso31661 == countryCode })?
            .releaseDates
            .compactMap { TMDbTimestamp.parse($0.releaseDate) }
            .filter { $0 >= start && $0 < end }
            .min()
    }

    func toMovie(isTheatrical: Bool, isWideRelease: Bool, countryCode: String, weekStart: Date, weekEnd: Date) -> Movie {
        // UTC: this parses TMDb's midnight-UTC calendar-date string into the
        // Movie's stored releaseDate, which is later displayed via an explicit
        // UTC formatter/calendar (releaseDateFormatted, ticketsButton) — parsing
        // in the device's local time zone would shift the stored instant and
        // make those UTC-anchored displays show the wrong day.
        let dateFormatter = DateFormatter.tmdbDateOnly(timeZone: TimeZone(identifier: "UTC")!)
        // Use the country release date that falls within the displayed week so the
        // date shown matches when the movie opens locally, not an earlier foreign premiere.
        // Falls back to the displayed week's start — never "today" — if TMDb's
        // primary release_date is blank (it sometimes is) or unparseable, so a
        // movie never shows a release date outside the week it's listed under.
        let date = releaseDate(for: countryCode, in: weekStart, to: weekEnd)
            ?? dateFormatter.date(from: releaseDate)
            ?? weekStart

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

        let movieReviews: [Review] = (reviews?.results ?? []).map { r in
            Review(
                id: r.id,
                author: r.author,
                content: r.content,
                rating: r.authorDetails?.rating,
                url: r.url,
                createdAt: TMDbTimestamp.parse(r.createdAt) ?? Date()
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

/// Parses TMDb timestamps such as "2015-12-25T00:00:00.000Z" (fractional
/// seconds need their own options, so that's tried first, then plain).
/// Shared formatters: building them per call made ~1,600 per busy week.
enum TMDbTimestamp {
    private static let fractional: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()
    private static let plain: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    static func parse(_ string: String) -> Date? {
        fractional.date(from: string) ?? plain.date(from: string)
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
