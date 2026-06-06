import Foundation

struct UserFilm: Identifiable, Codable {
    let id: Int
    let title: String
    let posterPath: String?
    let dateAdded: Date
    var seenDate: Date?
    var personalRating: Int? // 1–5, nil = unrated

    var posterURL: URL? {
        guard let path = posterPath else { return nil }
        return URL(string: "https://image.tmdb.org/t/p/w500\(path)")
    }
}
