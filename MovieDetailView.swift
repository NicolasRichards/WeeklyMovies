import SwiftUI

struct MovieDetailView: View {
    let movie: Movie
    @Environment(\.openURL) private var openURL

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                heroImage

                VStack(alignment: .leading, spacing: 20) {
                    titleSection

                    Divider()

                    if !movie.overview.isEmpty {
                        overviewSection
                        Divider()
                    }

                    if movie.director != nil || !movie.cast.isEmpty {
                        castSection
                        Divider()
                    }

                    actionButtons

                    if !movie.streamingProviders.isEmpty {
                        Divider()
                        streamingSection
                    }

                    if !movie.reviews.isEmpty {
                        Divider()
                        reviewsSection
                    }
                }
                .padding()
            }
        }
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: - Sections

    private var heroImage: some View {
        AsyncImage(url: movie.posterURL) { image in
            image
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(maxWidth: .infinity)
                .frame(height: 320)
                .clipped()
        } placeholder: {
            Rectangle()
                .fill(.quaternary)
                .frame(maxWidth: .infinity)
                .frame(height: 320)
                .overlay {
                    Image(systemName: "film")
                        .font(.system(size: 60))
                        .foregroundStyle(.tertiary)
                }
        }
    }

    private var titleSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(movie.title)
                .font(.title2)
                .fontWeight(.bold)

            HStack {
                Label(movie.releaseDateFormatted, systemImage: "calendar")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                Spacer()

                HStack(spacing: 4) {
                    Image(systemName: "star.fill").foregroundStyle(.yellow)
                    Text(String(format: "%.1f", movie.voteAverage)).fontWeight(.semibold)
                    Text("/ 10").foregroundStyle(.secondary)
                    Text("(\(movie.voteCount))").font(.caption).foregroundStyle(.tertiary)
                }
                .font(.subheadline)
            }

            HStack(spacing: 8) {
                if movie.isTheatrical {
                    typeBadge("In Theaters", icon: "film.stack", color: .blue)
                }
                if !movie.streamingProviders.isEmpty {
                    typeBadge("Streaming", icon: "play.tv", color: .green)
                }
            }
        }
    }

    private var overviewSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Synopsis").font(.headline)
            Text(movie.overview).font(.body)
        }
    }

    private var castSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Cast & Crew").font(.headline)

            if let director = movie.director {
                creditRow(label: "Director", value: director)
            }
            if !movie.cast.isEmpty {
                creditRow(label: "Cast", value: movie.cast.joined(separator: ", "))
            }
        }
    }

    private var actionButtons: some View {
        HStack(spacing: 12) {
            if let imdbURL = movie.imdbURL {
                Link(destination: imdbURL) {
                    Label("View on IMDb", systemImage: "link")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .tint(.yellow)
            }

            if let trailerURL = movie.trailerURL {
                Link(destination: trailerURL) {
                    Label("Watch Trailer", systemImage: "play.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
            }
        }
    }

    private var streamingSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Available On").font(.headline)

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 90))], spacing: 12) {
                ForEach(movie.streamingProviders) { provider in
                    providerCard(provider)
                }
            }
        }
    }

    private var reviewsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Reviews (\(movie.reviews.count))").font(.headline)
            ForEach(Array(movie.reviews.prefix(5).enumerated()), id: \.element.id) { idx, review in
                ReviewRowView(review: review)
                if idx < min(movie.reviews.count, 5) - 1 {
                    Divider()
                }
            }
        }
    }

    // MARK: - Helpers

    private func typeBadge(_ label: String, icon: String, color: Color) -> some View {
        Label(label, systemImage: icon)
            .font(.subheadline)
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(color.opacity(0.15))
            .foregroundStyle(color)
            .clipShape(Capsule())
    }

    private func creditRow(label: String, value: String) -> some View {
        HStack(alignment: .top) {
            Text(label)
                .foregroundStyle(.secondary)
                .frame(width: 75, alignment: .leading)
            Text(value)
                .fontWeight(.medium)
        }
        .font(.subheadline)
    }

    private func providerCard(_ provider: StreamingProvider) -> some View {
        VStack(spacing: 6) {
            AsyncImage(url: provider.logoURL) { image in
                image.resizable().aspectRatio(contentMode: .fit)
            } placeholder: {
                RoundedRectangle(cornerRadius: 8).fill(.quaternary)
            }
            .frame(width: 44, height: 44)
            .clipShape(RoundedRectangle(cornerRadius: 8))

            Text(provider.name)
                .font(.caption)
                .multilineTextAlignment(.center)
                .lineLimit(2)
        }
        .frame(maxWidth: .infinity)
        .padding(8)
        .background(.quaternary.opacity(0.5))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }
}

// MARK: - Review Row

struct ReviewRowView: View {
    let review: Review
    @State private var isExpanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(review.author)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                Spacer()
                if let rating = review.rating {
                    HStack(spacing: 2) {
                        Image(systemName: "star.fill").foregroundStyle(.yellow).font(.caption)
                        Text(String(format: "%.1f", rating)).font(.caption).fontWeight(.medium)
                    }
                }
            }

            Text(review.content)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineLimit(isExpanded ? nil : 4)

            if review.content.count > 200 {
                Button(isExpanded ? "Show less" : "Read more") {
                    withAnimation(.easeInOut(duration: 0.2)) { isExpanded.toggle() }
                }
                .font(.caption)
            }
        }
    }
}
