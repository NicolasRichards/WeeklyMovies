import SwiftUI

struct MovieCardView: View {
    let movie: Movie

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            posterImage

            VStack(alignment: .leading, spacing: 6) {
                Text(movie.title)
                    .font(.headline)
                    .lineLimit(2)

                Text(movie.releaseDateFormatted)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                ratingRow

                typeBadges

                if !movie.streamingProviders.isEmpty {
                    StreamingProvidersRow(providers: movie.streamingProviders)
                }
            }
        }
        .padding(.vertical, 4)
    }

    private var posterImage: some View {
        AsyncImage(url: movie.posterURL) { image in
            image
                .resizable()
                .aspectRatio(contentMode: .fill)
        } placeholder: {
            Rectangle()
                .fill(.quaternary)
                .overlay {
                    Image(systemName: "film")
                        .font(.title2)
                        .foregroundStyle(.tertiary)
                }
        }
        .frame(width: 80, height: 120)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private var ratingRow: some View {
        HStack(spacing: 4) {
            Image(systemName: "star.fill")
                .foregroundStyle(.yellow)
                .font(.caption)
            Text(String(format: "%.1f", movie.voteAverage))
                .font(.subheadline)
                .fontWeight(.medium)
            Text("(\(movie.voteCount))")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var typeBadges: some View {
        HStack(spacing: 6) {
            if movie.isTheatrical {
                badge(label: "Theater", icon: "film.stack", color: .blue)
            }
            if !movie.streamingProviders.isEmpty {
                badge(label: "Streaming", icon: "play.tv", color: .green)
            }
        }
    }

    private func badge(label: String, icon: String, color: Color) -> some View {
        Label(label, systemImage: icon)
            .font(.caption)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(color.opacity(0.15))
            .foregroundStyle(color)
            .clipShape(Capsule())
    }
}

struct StreamingProvidersRow: View {
    let providers: [StreamingProvider]

    var body: some View {
        HStack(spacing: 4) {
            ForEach(providers.prefix(5)) { provider in
                AsyncImage(url: provider.logoURL) { image in
                    image.resizable().aspectRatio(contentMode: .fill)
                } placeholder: {
                    RoundedRectangle(cornerRadius: 4).fill(.quaternary)
                }
                .frame(width: 22, height: 22)
                .clipShape(RoundedRectangle(cornerRadius: 4))
            }
            if providers.count > 5 {
                Text("+\(providers.count - 5)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }
}
