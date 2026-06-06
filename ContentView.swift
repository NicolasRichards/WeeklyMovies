import SwiftUI

struct ContentView: View {
    @State private var viewModel = MoviesViewModel()
    @State private var store = WatchlistStore.shared
    @State private var showingAPIKeySetup = false
    @State private var showingCountryPicker = false
    @State private var movieToRate: Movie?
    @Environment(\.openURL) private var openURL

    var body: some View {
        TabView {
            weeklyTab
                .tabItem { Label("This Week", systemImage: "film.stack") }

            MyFilmsView()
                .tabItem { Label("My Films", systemImage: "bookmark.fill") }
        }
        .sheet(isPresented: $showingAPIKeySetup) {
            APIKeySetupView(isPresented: $showingAPIKeySetup) {
                Task { await viewModel.loadMovies(forceRefresh: true) }
            }
        }
        .sheet(isPresented: $showingCountryPicker) {
            CountryPickerView(viewModel: viewModel)
        }
        .sheet(item: $movieToRate) { movie in
            RateFilmSheet(title: movie.title) { rating in
                store.markSeen(movie, rating: rating)
                movieToRate = nil
            }
        }
        .task {
            if !KeychainHelper.shared.hasAPIKey {
                showingAPIKeySetup = true
            } else {
                await viewModel.loadMovies(forceRefresh: true)
            }
        }
    }

    // MARK: - Weekly tab

    private var weeklyTab: some View {
        NavigationStack {
            Group {
                if viewModel.isLoading && viewModel.movies.isEmpty {
                    loadingView
                } else if let error = viewModel.errorMessage, viewModel.movies.isEmpty {
                    errorView(message: error)
                } else {
                    moviesList
                }
            }
            .navigationTitle("Weekly Movies")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        Task { await viewModel.loadMovies(forceRefresh: true) }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .disabled(viewModel.isLoading)
                }
                ToolbarItem(placement: .automatic) {
                    Button {
                        showingCountryPicker = true
                    } label: {
                        Text("\(viewModel.countryFlag) \(viewModel.countryCode)")
                            .font(.subheadline)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(.regularMaterial, in: Capsule())
                    }
                    .buttonStyle(.plain)
                }
                ToolbarItem(placement: .automatic) {
                    Button {
                        showingAPIKeySetup = true
                    } label: {
                        Image(systemName: "key")
                    }
                }
            }
        }
    }

    // MARK: - Movies list

    private var moviesList: some View {
        List {
            Section {
                weekNavigationBar
            }
            .listRowBackground(Color.clear)
            .listRowInsets(EdgeInsets())

            Section {
                Picker("Filter", selection: $viewModel.filter) {
                    ForEach(MoviesViewModel.MovieFilter.allCases, id: \.self) {
                        Text($0.rawValue).tag($0)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.vertical, 4)
            }
            .listRowBackground(Color.clear)

            if viewModel.filter == .theatrical {
                Section {
                    Toggle("Wide releases only", isOn: $viewModel.wideOnly)
                        .font(.subheadline)
                }
                .listRowBackground(Color.clear)
            }

            if viewModel.filteredMovies.isEmpty && !viewModel.isLoading {
                Section {
                    ContentUnavailableView(
                        "No Releases",
                        systemImage: "film",
                        description: Text("No \(viewModel.filter.rawValue.lowercased()) releases found for this week.")
                    )
                }
                .listRowBackground(Color.clear)
            } else {
                ForEach(viewModel.filteredMovies) { movie in
                    NavigationLink(destination: MovieDetailView(movie: movie)) {
                        MovieCardView(movie: movie)
                    }
                    .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                    .swipeActions(edge: .leading, allowsFullSwipe: true) {
                        ticketsButton(for: movie)
                    }
                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                        seenButton(for: movie)
                        watchlistButton(for: movie)
                    }
                }
            }
        }
        .listStyle(.plain)
        .refreshable {
            await viewModel.loadMovies(forceRefresh: true)
        }
        .overlay(alignment: .top) {
            if viewModel.isLoading && !viewModel.movies.isEmpty {
                ProgressView()
                    .padding(10)
                    .background(.regularMaterial, in: Circle())
                    .padding(.top, 8)
            }
        }
    }

    // MARK: - Swipe action buttons

    @ViewBuilder
    private func watchlistButton(for movie: Movie) -> some View {
        if store.isInWatchlist(movie.id) {
            Button {
                store.removeFromWatchlist(movie.id)
            } label: {
                Label("Remove", systemImage: "bookmark.slash.fill")
            }
            .tint(.gray)
        } else if !store.isInSeen(movie.id) {
            Button {
                store.addToWatchlist(movie)
            } label: {
                Label("Watchlist", systemImage: "bookmark.fill")
            }
            .tint(.blue)
        }
    }

    @ViewBuilder
    private func seenButton(for movie: Movie) -> some View {
        if !store.isInSeen(movie.id) {
            Button {
                movieToRate = movie
            } label: {
                Label("Seen", systemImage: "checkmark.circle.fill")
            }
            .tint(.green)
        }
    }

    private func ticketsButton(for movie: Movie) -> some View {
        Button {
            let query = "\(movie.title) \(Calendar.current.component(.year, from: movie.releaseDate)) movie tickets"
            let encoded = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
            if let url = URL(string: "https://www.google.com/search?q=\(encoded)") {
                openURL(url)
            }
        } label: {
            Label("Tickets", systemImage: "ticket.fill")
        }
        .tint(.orange)
    }

    // MARK: - Supporting views

    private var loadingView: some View {
        VStack(spacing: 16) {
            ProgressView().scaleEffect(1.5)
            Text("Loading this week's movies…").foregroundStyle(.secondary)
        }
    }

    private func errorView(message: String) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 48))
                .foregroundStyle(.red)
            Text("Something went wrong").font(.headline)
            Text(message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            Button("Try Again") {
                Task { await viewModel.loadMovies(forceRefresh: true) }
            }
            .buttonStyle(.bordered)
        }
    }

    private var weekNavigationBar: some View {
        HStack(spacing: 0) {
            Button { viewModel.goToPreviousWeek() } label: {
                Image(systemName: "chevron.left").font(.title2).frame(width: 44, height: 44)
            }
            Spacer()
            VStack(spacing: 2) {
                Text(viewModel.weekTitle).font(.headline)
                Text(viewModel.weekDateRange).font(.caption).foregroundStyle(.secondary)
                if viewModel.currentWeekOffset != 0 {
                    Button("Jump to Current Week") { viewModel.goToCurrentWeek() }
                        .font(.caption).padding(.top, 2)
                }
            }
            Spacer()
            Button { viewModel.goToNextWeek() } label: {
                Image(systemName: "chevron.right").font(.title2).frame(width: 44, height: 44)
            }
            .disabled(!viewModel.canGoToNextWeek)
            .opacity(viewModel.canGoToNextWeek ? 1 : 0.3)
        }
        .padding(.vertical, 4)
    }
}
