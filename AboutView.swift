import SwiftUI
import StoreKit

struct AboutView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @Environment(\.requestReview) private var requestReview
    @State private var tipJar = TipJar()

    private let appStoreURL = URL(string: "https://apps.apple.com/app/id6777580481")!

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    VStack(spacing: 8) {
                        Image(systemName: "film.stack")
                            .font(.system(size: 44))
                            .foregroundStyle(.tint)
                        Text("Weekly Movies")
                            .font(.title.bold())
                        Text("This week's theatrical and streaming releases.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .padding(.top, 12)

                    supportSection

                    Divider()

                    VStack(spacing: 8) {
                        Text("Movie data provided by")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                        Button("The Movie Database (TMDb)") {
                            openURL(URL(string: "https://www.themoviedb.org")!)
                        }
                        .font(.headline)
                        Text("This product uses the TMDb API but is not endorsed or certified by TMDb.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }

                    Text("Made with love by Nicolas Richards")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(24)
            }
            .navigationTitle("About")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .task { await tipJar.load() }
        .task { await tipJar.listenForTransactions() }
    }

    // MARK: - Support

    private var supportSection: some View {
        VStack(spacing: 16) {
            Text("Enjoying the app? 🎬")
                .font(.title3.bold())

            Text("This app is 100% free, ad-free and tracking free, a gift meant for every movie lover. Have a little extra and want to say thanks? Only do this if you really can afford to!")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            VStack(spacing: 10) {
                Text("☕ Buy us a coffee?")
                    .font(.headline)

                if tipJar.didTip {
                    Text("Thank you so much. 💛")
                        .font(.subheadline)
                        .foregroundStyle(.tint)
                        .padding(.vertical, 8)
                } else if tipJar.loadFailed {
                    Text("Tip options couldn't load right now.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .padding(.vertical, 8)
                } else if tipJar.products.isEmpty {
                    ProgressView()
                        .padding(.vertical, 12)
                } else {
                    ForEach(tipJar.products, id: \.id) { product in
                        tipRow(reels: reelCount(for: product), product: product)
                    }
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))

            HStack(spacing: 12) {
                Button {
                    requestReview()
                } label: {
                    Label("Rate us", systemImage: "star.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)

                Button {
                    openURL(appStoreURL)
                } label: {
                    Label("App Store", systemImage: "arrow.up.forward")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
            }
        }
    }

    private func tipRow(reels: Int, product: Product) -> some View {
        Button {
            Task { await tipJar.purchase(product) }
        } label: {
            HStack(spacing: 12) {
                HStack(spacing: 3) {
                    ForEach(0..<reels, id: \.self) { _ in
                        Image(systemName: "movieclapper")
                    }
                }
                .foregroundStyle(.tint)

                Text(tierName(for: reels))
                    .foregroundStyle(.primary)

                Spacer()

                if tipJar.purchasing == product.id {
                    ProgressView()
                } else {
                    Text(product.displayPrice)
                        .font(.headline)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity)
            .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
        .disabled(tipJar.purchasing != nil)
    }

    private func tierName(for reels: Int) -> String {
        switch reels {
        case 1: "Small tip"
        case 2: "Medium tip"
        default: "Large tip"
        }
    }

    /// Reel count keyed off the product's own ID, not its position in a
    /// price-sorted list — that list can have fewer than 3 entries whenever
    /// not every tier is approved yet, which would otherwise mislabel tiers.
    private func reelCount(for product: Product) -> Int {
        if product.id.hasSuffix(".small") { return 1 }
        if product.id.hasSuffix(".medium") { return 2 }
        return 3
    }
}
