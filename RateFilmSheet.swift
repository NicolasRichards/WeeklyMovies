import SwiftUI

struct RateFilmSheet: View {
    let title: String
    let initialRating: Int?
    /// `nil` from Skip, 1–5 from Save, or 0 from Clear Rating (only offered
    /// when there's an `initialRating` to clear).
    let onRate: (Int?) -> Void

    @State private var selectedRating: Int

    init(title: String, initialRating: Int? = nil, onRate: @escaping (Int?) -> Void) {
        self.title = title
        self.initialRating = initialRating
        self.onRate = onRate
        _selectedRating = State(initialValue: initialRating ?? 0)
    }

    private var isClearing: Bool { selectedRating == 0 && initialRating != nil }

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

                Button(isClearing ? "Clear Rating" : "Save Rating") {
                    onRate(selectedRating)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(selectedRating == 0 && !isClearing)
            }
        }
        .padding(32)
        .presentationDetents([.height(260)])
        .presentationDragIndicator(.visible)
    }
}
