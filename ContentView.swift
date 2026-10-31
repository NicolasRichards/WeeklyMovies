import SwiftUI

struct ContentView: View {
    @State private var viewModel = MoviesViewModel()
    @State private var store = WatchlistStore.shared
    @State private var showingAPIKeySetup = false
    @State private var showingCountryPicker = false
    @State private var showingAbout = false
    @State private var movieToRate: Movie?
    @Environment(\.openURL) private var openURL
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        TabView {
            weeklyTab
                .tabItem { Label("This Week", systemImage: "film.stack") }

            MyFilmsView()
                .tabItem { Label("My Films", systemImage: "bookmark.fill") }
        }
        .sheet(isPresented: $showingAPIKeySetup) {
            APIKeySetupView(isPresented: $showingAPIKeySetup) {
                Task { await viewModel.loadMovies() }
            } onRemove: {
                viewModel.clearForMissingKey()
            }
        }
        .sheet(isPresented: $showingCountryPicker) {
            CountryPickerView(viewModel: viewModel)
        }
        .sheet(isPresented: $showingAbout) {
            AboutView()
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
                await viewModel.loadMovies()
            }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { viewModel.reloadIfWeekRolledOver() }
        }
    }

    // MARK: - Weekly tab

    private var weeklyTab: some View {
        NavigationStack {
            Group {
                if viewModel.isLoading && viewModel.movies.isEmpty && !viewModel.hasLoadedSelection {
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
                        Task { await viewModel.loadMovies() }
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
                ToolbarItem(placement: .automatic) {
                    Button {
                        showingAbout = true
                    } label: {
                        Image(systemName: "info.circle")
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

            if let message = viewModel.errorMessage, !viewModel.movies.isEmpty {
                Section {
                    resultsNotice(message: message)
                }
                .listRowBackground(Color.clear)
            }

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
            await viewModel.loadMovies()
        }
        .overlay(alignment: .bottom) {
            if viewModel.isLoading {
                // At the bottom so it never covers the week navigation bar
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("Updating…")
                }
                .font(.caption)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(.regularMaterial, in: Capsule())
                .padding(.bottom, 12)
            }
        }
    }

    /// Why the list shown isn't a complete, fresh result: saved results after a
    /// failed refresh, or fresh results with something missing.
    private func resultsNotice(message: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Label {
                Text(viewModel.showingSavedResults ? "Showing saved results. \(message)" : message)
            } icon: {
                Image(systemName: viewModel.apiKeyRejected ? "key"
                      : viewModel.showingSavedResults ? "wifi.slash" : "exclamationmark.triangle")
            }
            .font(.caption)
            .foregroundStyle(.secondary)

            if viewModel.apiKeyRejected {
                updateKeyButton
                    .font(.caption)
                    .buttonStyle(.borderless)
            }
        }
    }

    private var updateKeyButton: some View {
        Button("Update API Key") { showingAPIKeySetup = true }
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
            // movie.releaseDate is a midnight-UTC TMDb calendar date, not a real
            // instant — pulling .year via Calendar.current (the device's local
            // timezone AND calendar identifier) can shift it to the wrong year,
            // same root cause already fixed for releaseDateFormatted. A Thai
            // (Buddhist calendar) device would otherwise always search the
            // Buddhist-era year; a device west of UTC could search the prior
            // year for a release right at the Dec 31/Jan 1 boundary.
            var utcCalendar = Calendar(identifier: .gregorian)
            utcCalendar.timeZone = TimeZone(identifier: "UTC")!
            let year = utcCalendar.component(.year, from: movie.releaseDate)
            let query = "\(movie.title) \(year) movie tickets"
            let encoded = query.queryValueEncoded
            if let url = URL(string: "https://www.google.com/search?q=\(encoded)") {
                openURL(url)
            }
        } label: {
            Label("Tickets", systemImage: "ticket.fill")
        }
        .tint(.orange)
    }

    // MARK: - Supporting views

    /// Keeps the week arrows available while nothing is listed yet.
    private func withWeekNavigation<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        VStack(spacing: 0) {
            weekNavigationBar
                .padding(.horizontal)
            content()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private var loadingView: some View {
        withWeekNavigation {
            VStack(spacing: 16) {
                ProgressView().scaleEffect(1.5)
                Text("Loading this week's movies…").foregroundStyle(.secondary)
            }
        }
    }

    private func errorView(message: String) -> some View {
        withWeekNavigation {
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
                if viewModel.apiKeyRejected {
                    updateKeyButton
                        .buttonStyle(.borderedProminent)
                }
                Button("Try Again") {
                    Task { await viewModel.loadMovies() }
                }
                .buttonStyle(.bordered)
            }
        }
    }

    private var weekNavigationBar: some View {
        HStack(spacing: 0) {
            Button { viewModel.goToPreviousWeek() } label: {
                Image(systemName: "chevron.left").font(.title2).frame(width: 44, height: 44)
            }
            .buttonStyle(.borderless)
            .disabled(!viewModel.canGoToPreviousWeek)
            .opacity(viewModel.canGoToPreviousWeek ? 1 : 0.3)

            Spacer()

            VStack(spacing: 2) {
                Text(viewModel.weekTitle).font(.headline)
                Text(viewModel.weekDateRange).font(.caption).foregroundStyle(.secondary)
                if viewModel.currentWeekOffset != 0 {
                    Button("Jump to Current Week") { viewModel.goToCurrentWeek() }
                        .font(.caption).padding(.top, 2)
                        .buttonStyle(.borderless)
                }
            }

            Spacer()

            Button { viewModel.goToNextWeek() } label: {
                Image(systemName: "chevron.right").font(.title2).frame(width: 44, height: 44)
            }
            .buttonStyle(.borderless)
            .disabled(!viewModel.canGoToNextWeek)
            .opacity(viewModel.canGoToNextWeek ? 1 : 0.3)
        }
        .padding(.vertical, 4)
    }
}
