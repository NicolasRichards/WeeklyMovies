import SwiftUI

struct RateFilmSheet: View {
    let title: String
    let onRate: (Int?) -> Void

    @State private var selectedRating = 0

    var body: some View {
        VStack(spacing: 24) {
            VStack(spacing: 6) {
                Text("How was it?")
                    .font(.title2)
                    .fontWeight(.bold)
                Text(title)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            HStack(spacing: 16) {
                ForEach(1...5, id: \.self) { star in
                    Image(systemName: star <= selectedRating ? "star.fill" : "star")
                        .font(.system(size: 40))
                        .foregroundStyle(.yellow)
                        .onTapGesture {
                            selectedRating = (selectedRating == star) ? 0 : star
                        }
                }
            }

            HStack(spacing: 16) {
                Button("Skip") { onRate(nil) }
                    .buttonStyle(.bordered)
                    .controlSize(.large)

                Button("Save Rating") {
                    onRate(selectedRating > 0 ? selectedRating : nil)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(selectedRating == 0)
            }
        }
        .padding(32)
        .presentationDetents([.height(260)])
        .presentationDragIndicator(.visible)
    }
}
