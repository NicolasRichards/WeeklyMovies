import SwiftUI

struct ContentView: View {
    @StateObject private var viewModel = MoviesViewModel()
    @State private var showingAPIKeySetup = false

    var body: some View {
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
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        Task { await viewModel.loadMovies(forceRefresh: true) }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .disabled(viewModel.isLoading)
                }
                ToolbarItem(placement: .navigationBarLeading) {
                    Button {
                        showingAPIKeySetup = true
                    } label: {
                        Image(systemName: "key")
                    }
                }
            }
        }
        .sheet(isPresented: $showingAPIKeySetup) {
            APIKeySetupView(isPresented: $showingAPIKeySetup) {
                Task { await viewModel.loadMovies(forceRefresh: true) }
            }
        }
        .task {
            if !KeychainHelper.shared.hasAPIKey {
                showingAPIKeySetup = true
            } else {
                await viewModel.loadMovies()
            }
        }
    }

    // MARK: - Subviews

    private var loadingView: some View {
        VStack(spacing: 16) {
            ProgressView()
                .scaleEffect(1.5)
            Text("Loading this week's movies…")
                .foregroundStyle(.secondary)
        }
    }

    private func errorView(message: String) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 48))
                .foregroundStyle(.red)
            Text("Something went wrong")
                .font(.headline)
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

    private var moviesList: some View {
        List {
            // Week navigation
            Section {
                weekNavigationBar
            }
            .listRowBackground(Color.clear)
            .listRowInsets(EdgeInsets())

            // Filter picker
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

            // Movie cards
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

    private var weekNavigationBar: some View {
        HStack(spacing: 0) {
            Button {
                viewModel.goToPreviousWeek()
            } label: {
                Image(systemName: "chevron.left")
                    .font(.title2)
                    .frame(width: 44, height: 44)
            }

            Spacer()

            VStack(spacing: 2) {
                Text(viewModel.weekTitle)
                    .font(.headline)
                Text(viewModel.weekDateRange)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if viewModel.currentWeekOffset != 0 {
                    Button("Jump to Current Week") {
                        viewModel.goToCurrentWeek()
                    }
                    .font(.caption)
                    .padding(.top, 2)
                }
            }

            Spacer()

            Button {
                viewModel.goToNextWeek()
            } label: {
                Image(systemName: "chevron.right")
                    .font(.title2)
                    .frame(width: 44, height: 44)
            }
            .disabled(!viewModel.canGoToNextWeek)
            .opacity(viewModel.canGoToNextWeek ? 1 : 0.3)
        }
        .padding(.vertical, 4)
    }
}
