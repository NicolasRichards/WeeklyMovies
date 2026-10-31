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
    private let migratedLocalFilmsKey = "wm_didMigrateLocalFilms"

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
        ) { [weak self] note in
            let reason = note.userInfo?[NSUbiquitousKeyValueStoreChangeReasonKey] as? Int
            // The observer block is nonisolated even with queue: .main, so hop
            // to the main actor explicitly rather than relying on the queue.
            Task { @MainActor in
                // A different iCloud account: drop the old account's lists so the
                // next edit can't push them into the new account.
                self?.load(replacingMissing: reason == NSUbiquitousKeyValueStoreAccountChange)
            }
        }
        kvStore.synchronize()
    }

    // MARK: - Actions

    func addToWatchlist(_ movie: Movie) {
        guard !isInWatchlist(movie.id), !isInSeen(movie.id) else { return }
        watchlist.insert(UserFilm(id: movie.id, title: movie.title,
                                  posterPath: movie.posterPath, dateAdded: Date()), at: 0)
        saveWatchlist()
    }

    func removeFromWatchlist(_ id: Int) {
        watchlist.removeAll { $0.id == id }
        saveWatchlist()
    }

    func markSeen(_ movie: Movie, rating: Int?) {
        if isInWatchlist(movie.id) {
            watchlist.removeAll { $0.id == movie.id }
            saveWatchlist()
        }
        if !isInSeen(movie.id) {
            seenList.insert(UserFilm(id: movie.id, title: movie.title,
                                     posterPath: movie.posterPath, dateAdded: Date(),
                                     seenDate: Date(), personalRating: rating), at: 0)
            saveSeenList()
        } else if let rating {
            updateRating(id: movie.id, rating: rating)
        }
    }

    func updateRating(id: Int, rating: Int?) {
        guard let idx = seenList.firstIndex(where: { $0.id == id }) else { return }
        seenList[idx].personalRating = rating
        saveSeenList()
    }

    func removeFromSeen(_ id: Int) {
        seenList.removeAll { $0.id == id }
        saveSeenList()
    }

    // MARK: - Queries

    func isInWatchlist(_ id: Int) -> Bool { watchlist.contains { $0.id == id } }
    func isInSeen(_ id: Int) -> Bool { seenList.contains { $0.id == id } }

    // MARK: - Persistence

    /// `replacingMissing` empties a list whose key is absent (a new iCloud
    /// account) instead of keeping what's in memory.
    private func load(replacingMissing: Bool = false) {
        if let data = kvStore.data(forKey: watchlistKey),
           let list = try? JSONDecoder().decode([UserFilm].self, from: data) {
            watchlist = list
        } else if replacingMissing {
            watchlist = []
        }
        if let data = kvStore.data(forKey: seenListKey),
           let list = try? JSONDecoder().decode([UserFilm].self, from: data) {
            seenList = list
        } else if replacingMissing {
            seenList = []
        }

        // Merge in any pre-iCloud local data still sitting on this device. This
        // can't be gated on "iCloud is still empty" — on a second device that
        // had its own separate pre-sync watchlist, a first device may have
        // already pushed its own list to iCloud by the time this one upgrades,
        // which would make that check false and strand this device's local file
        // on disk forever, invisible to the user. Local-only films (by movie ID,
        // checked against BOTH lists so a film already seen elsewhere isn't also
        // merged into watchlist) are merged in; where either side already has
        // the film, the already-synced iCloud copy wins. Gated by a one-time
        // flag (not just the local file's existence) so this can only ever run
        // once per device — load() reruns on every external iCloud change with
        // no key filter, and re-running the merge risks re-adding a film that
        // was deliberately removed on another device after it synced.
        if !UserDefaults.standard.bool(forKey: migratedLocalFilmsKey),
           let data = try? Data(contentsOf: localURL),
           let saved = try? JSONDecoder().decode(SavedData.self, from: data) {
            let existingIDs = Set(watchlist.map(\.id)).union(seenList.map(\.id))
            watchlist += saved.watchlist.filter { !existingIDs.contains($0.id) }
            seenList += saved.seenList.filter { !existingIDs.contains($0.id) }
            // Restore most-recent-first order (addToWatchlist/markSeen maintain
            // it via insert(at: 0)) after appending the merged-in local films.
            watchlist.sort { $0.dateAdded > $1.dateAdded }
            seenList.sort { $0.dateAdded > $1.dateAdded }
            // Push the merged-in local data to iCloud before deleting the backup
            saveWatchlist()
            saveSeenList()
            try? FileManager.default.removeItem(at: localURL)
            UserDefaults.standard.set(true, forKey: migratedLocalFilmsKey)
        }
    }

    // Each list is written only when it changed, so a stale copy of the other
    // list on this device can't overwrite another device's newer edits to it.
    private func saveWatchlist() { save(watchlist, forKey: watchlistKey) }
    private func saveSeenList() { save(seenList, forKey: seenListKey) }

    private func save(_ films: [UserFilm], forKey key: String) {
        if let data = try? JSONEncoder().encode(films) {
            kvStore.set(data, forKey: key)
        }
        kvStore.synchronize()
    }

    private struct SavedData: Codable {
        var watchlist: [UserFilm]
        var seenList: [UserFilm]
    }
}
