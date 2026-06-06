import SwiftUI

struct MyFilmsView: View {
    @State private var store = WatchlistStore.shared
    @State private var selectedTab: FilmTab = .watchlist
    @State private var filmToRate: UserFilm?

    enum FilmTab: String, CaseIterable {
        case watchlist = "Watchlist"
        case seen = "Seen"
    }

    var body: some View {
        NavigationStack {
            Group {
                if selectedTab == .watchlist {
                    filmList(store.watchlist, emptyMessage: "No films saved yet.\nSwipe a movie to add it to your watchlist.")
                } else {
                    seenListView
                }
            }
            .navigationTitle("My Films")
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Picker("Tab", selection: $selectedTab) {
                        ForEach(FilmTab.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 200)
                }
            }
        }
        .sheet(item: $filmToRate) { film in
            RateFilmSheet(title: film.title) { rating in
                store.updateRating(id: film.id, rating: rating)
                filmToRate = nil
            }
        }
    }

    // MARK: - Watchlist

    private func filmList(_ films: [UserFilm], emptyMessage: String) -> some View {
        Group {
            if films.isEmpty {
                emptyState(message: emptyMessage)
            } else {
                List {
                    ForEach(films) { film in
                        filmRow(film)
                            .swipeActions(edge: .trailing) {
                                Button(role: .destructive) {
                                    if selectedTab == .watchlist {
                                        store.removeFromWatchlist(film.id)
                                    } else {
                                        store.removeFromSeen(film.id)
                                    }
                                } label: {
                                    Label("Remove", systemImage: "trash")
                                }
                            }
                    }
                }
                .listStyle(.plain)
            }
        }
    }

    // MARK: - Seen list (with ratings)

    private var seenListView: some View {
        Group {
            if store.seenList.isEmpty {
                emptyState(message: "No films marked as seen yet.\nSwipe a movie to mark it watched.")
            } else {
                List {
                    ForEach(store.seenList) { film in
                        seenRow(film)
                            .swipeActions(edge: .trailing) {
                                Button(role: .destructive) {
                                    store.removeFromSeen(film.id)
                                } label: {
                                    Label("Remove", systemImage: "trash")
                                }
                            }
                    }
                }
                .listStyle(.plain)
            }
        }
    }

    // MARK: - Row views

    private func filmRow(_ film: UserFilm) -> some View {
        HStack(spacing: 12) {
            posterThumbnail(film.posterURL)

            VStack(alignment: .leading, spacing: 4) {
                Text(film.title)
                    .font(.headline)
                    .lineLimit(2)
                Text("Added \(film.dateAdded.formatted(date: .abbreviated, time: .omitted))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }

    private func seenRow(_ film: UserFilm) -> some View {
        HStack(spacing: 12) {
            posterThumbnail(film.posterURL)

            VStack(alignment: .leading, spacing: 6) {
                Text(film.title)
                    .font(.headline)
                    .lineLimit(2)

                if let seenDate = film.seenDate {
                    Text("Seen \(seenDate.formatted(date: .abbreviated, time: .omitted))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                StarRatingView(rating: film.personalRating) {
                    filmToRate = film
                }
            }
        }
        .padding(.vertical, 4)
    }

    private func posterThumbnail(_ url: URL?) -> some View {
        AsyncImage(url: url) { image in
            image.resizable().aspectRatio(contentMode: .fill)
        } placeholder: {
            Rectangle().fill(.quaternary)
                .overlay { Image(systemName: "film").foregroundStyle(.tertiary) }
        }
        .frame(width: 54, height: 80)
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }

    private func emptyState(message: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: "bookmark")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
            Text(message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Star Rating View

struct StarRatingView: View {
    let rating: Int?
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 2) {
                ForEach(1...5, id: \.self) { star in
                    Image(systemName: starIcon(for: star))
                        .foregroundStyle(.yellow)
                        .font(.caption)
                }
                if rating == nil {
                    Text("Rate it")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.leading, 4)
                }
            }
        }
        .buttonStyle(.plain)
    }

    private func starIcon(for star: Int) -> String {
        guard let rating else { return "star" }
        return star <= rating ? "star.fill" : "star"
    }
}
