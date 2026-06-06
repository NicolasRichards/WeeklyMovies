import SwiftUI

private struct Country: Identifiable {
    let id: String   // ISO 3166-1 alpha-2 code e.g. "US", "GB"
    let name: String
}

struct CountryPickerView: View {
    var viewModel: MoviesViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var searchText = ""

    private let allCountries: [Country] = {
        let codes = [
            // North America
            "US", "CA", "MX",
            // Central America & Caribbean
            "GT", "HN", "SV", "NI", "CR", "PA", "CU", "DO", "PR", "JM", "TT",
            // South America
            "BR", "AR", "CL", "CO", "PE", "VE", "EC", "BO", "UY", "PY",
            // Western Europe
            "GB", "IE", "FR", "DE", "AT", "CH", "NL", "BE", "LU",
            "ES", "PT", "IT", "GR", "MT",
            // Nordic
            "SE", "NO", "DK", "FI", "IS",
            // Eastern Europe
            "PL", "CZ", "SK", "HU", "RO", "BG", "HR", "RS", "SI", "BA",
            "UA", "BY", "MD", "AL", "MK", "ME", "XK",
            // Baltic
            "EE", "LV", "LT",
            // Russia & Central Asia
            "RU", "KZ", "UZ", "GE", "AM", "AZ",
            // Middle East & North Africa
            "IL", "TR", "AE", "SA", "QA", "KW", "BH", "OM", "JO", "LB",
            "EG", "MA", "DZ", "TN",
            // Sub-Saharan Africa
            "ZA", "NG", "KE", "GH",
            // South Asia
            "IN", "PK", "BD", "LK",
            // East Asia
            "JP", "KR", "CN", "HK", "TW",
            // Southeast Asia
            "SG", "MY", "TH", "ID", "PH", "VN",
            // Oceania
            "AU", "NZ",
        ]
        return codes
            .map { code in
                Country(
                    id: code,
                    name: Locale.current.localizedString(forRegionCode: code) ?? code
                )
            }
            .sorted { $0.name.localizedCompare($1.name) == .orderedAscending }
    }()

    private var filteredCountries: [Country] {
        guard !searchText.isEmpty else { return allCountries }
        let q = searchText.lowercased()
        return allCountries.filter {
            $0.name.lowercased().contains(q) || $0.id.lowercased().contains(q)
        }
    }

    var body: some View {
        VStack(spacing: 0) {

            // ── Header ────────────────────────────────────────────────────────
            HStack {
                Text("Select Country")
                    .font(.headline)
                Spacer()
                Button("Cancel") { dismiss() }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)

            Divider()

            // ── Search field ──────────────────────────────────────────────────
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("Search countries", text: $searchText)
                    .autocorrectionDisabled()
                    #if os(iOS)
                    .textInputAutocapitalization(.never)
                    #endif
                if !searchText.isEmpty {
                    Button { searchText = "" } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(10)
            .background(.quaternary, in: RoundedRectangle(cornerRadius: 10))
            .padding(.horizontal, 16)
            .padding(.vertical, 8)

            Divider()

            // ── Country list ──────────────────────────────────────────────────
            List(filteredCountries) { country in
                Button {
                    viewModel.setCountry(country.id)
                    dismiss()
                } label: {
                    HStack {
                        Text(flagEmoji(for: country.id))
                            .font(.title2)
                        Text(country.name)
                            .foregroundStyle(.primary)
                        Spacer()
                        if country.id == viewModel.countryCode {
                            Image(systemName: "checkmark")
                                .foregroundStyle(.tint)
                                .fontWeight(.semibold)
                        }
                    }
                }
            }
            .listStyle(.plain)
        }
        #if os(macOS)
        .frame(minWidth: 380, minHeight: 520)
        #endif
    }

    private func flagEmoji(for code: String) -> String {
        code.uppercased().unicodeScalars
            .compactMap { UnicodeScalar(127397 + $0.value) }
            .reduce("") { $0 + String($1) }
    }
}
