import Foundation
import Observation

@Observable
class WatchlistStore {
    static let shared = WatchlistStore()

    var watchlist: [UserFilm] = []
    var seenList: [UserFilm] = []

    private let kvStore = NSUbiquitousKeyValueStore.default
    private let watchlistKey = "wm_watchlist"
    private let seenListKey = "wm_seenList"

    // Local fallback (also used for migration of pre-iCloud data)
    private var localURL: URL {
        URL.documentsDirectory.appendingPathComponent("userfilms.json")
    }

    init() {
        load()
        // Update when changes arrive from another device
        NotificationCenter.default.addObserver(
            forName: NSUbiquitousKeyValueStore.didChangeExternallyNotification,
            object: kvStore,
            queue: .main
        ) { [weak self] _ in
            // The observer block is nonisolated even with queue: .main, so hop
            // to the main actor explicitly rather than relying on the queue.
            Task { @MainActor in self?.load() }
        }
        kvStore.synchronize()
    }

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
        if let data = kvStore.data(forKey: watchlistKey),
           let list = try? JSONDecoder().decode([UserFilm].self, from: data) {
            watchlist = list
        }
        if let data = kvStore.data(forKey: seenListKey),
           let list = try? JSONDecoder().decode([UserFilm].self, from: data) {
            seenList = list
        }

        // Merge in any pre-iCloud local data still sitting on this device. This
        // can't be gated on "iCloud is still empty" — on a second device that
        // had its own separate pre-sync watchlist, a first device may have
        // already pushed its own list to iCloud by the time this one upgrades,
        // which would make that check false and strand this device's local file
        // on disk forever, invisible to the user. Local-only films (by movie ID)
        // are merged in; where both sides already have the same film, the
        // already-synced iCloud copy wins.
        if let data = try? Data(contentsOf: localURL),
           let saved = try? JSONDecoder().decode(SavedData.self, from: data) {
            let watchlistIDs = Set(watchlist.map(\.id))
            let seenIDs = Set(seenList.map(\.id))
            watchlist += saved.watchlist.filter { !watchlistIDs.contains($0.id) }
            seenList += saved.seenList.filter { !seenIDs.contains($0.id) }
            try? FileManager.default.removeItem(at: localURL)
            save() // push the merged-in local data to iCloud
        }
    }

    private func save() {
        if let data = try? JSONEncoder().encode(watchlist) {
            kvStore.set(data, forKey: watchlistKey)
        }
        if let data = try? JSONEncoder().encode(seenList) {
            kvStore.set(data, forKey: seenListKey)
        }
        kvStore.synchronize()
    }

    private struct SavedData: Codable {
        var watchlist: [UserFilm]
        var seenList: [UserFilm]
    }
}
