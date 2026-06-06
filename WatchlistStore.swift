import Foundation
import Observation

@Observable
class WatchlistStore {
    static let shared = WatchlistStore()

    var watchlist: [UserFilm] = []
    var seenList: [UserFilm] = []

    private var saveURL: URL {
        URL.documentsDirectory.appendingPathComponent("userfilms.json")
    }

    init() { load() }

    // MARK: - Actions

    func addToWatchlist(_ movie: Movie) {
        guard !isInWatchlist(movie.id), !isInSeen(movie.id) else { return }
        watchlist.insert(UserFilm(id: movie.id, title: movie.title,
                                  posterPath: movie.posterPath, dateAdded: Date()), at: 0)
        save()
    }

    func removeFromWatchlist(_ id: Int) {
        watchlist.removeAll { $0.id == id }
        save()
    }

    func markSeen(_ movie: Movie, rating: Int?) {
        watchlist.removeAll { $0.id == movie.id }
        if !isInSeen(movie.id) {
            seenList.insert(UserFilm(id: movie.id, title: movie.title,
                                     posterPath: movie.posterPath, dateAdded: Date(),
                                     seenDate: Date(), personalRating: rating), at: 0)
        } else if let rating {
            updateRating(id: movie.id, rating: rating)
        }
        save()
    }

    func updateRating(id: Int, rating: Int?) {
        guard let idx = seenList.firstIndex(where: { $0.id == id }) else { return }
        seenList[idx].personalRating = rating
        save()
    }

    func removeFromSeen(_ id: Int) {
        seenList.removeAll { $0.id == id }
        save()
    }

    // MARK: - Queries

    func isInWatchlist(_ id: Int) -> Bool { watchlist.contains { $0.id == id } }
    func isInSeen(_ id: Int) -> Bool { seenList.contains { $0.id == id } }

    // MARK: - Persistence

    private func load() {
        guard let data = try? Data(contentsOf: saveURL),
              let saved = try? JSONDecoder().decode(SavedData.self, from: data) else { return }
        watchlist = saved.watchlist
        seenList = saved.seenList
    }

    private func save() {
        let data = SavedData(watchlist: watchlist, seenList: seenList)
        try? JSONEncoder().encode(data).write(to: saveURL)
    }

    private struct SavedData: Codable {
        var watchlist: [UserFilm]
        var seenList: [UserFilm]
    }
}
