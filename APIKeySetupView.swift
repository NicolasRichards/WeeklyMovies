import SwiftUI

struct APIKeySetupView: View {
    @Binding var isPresented: Bool
    let onSave: () -> Void

    @State private var apiKey = ""
    @State private var showingLengthError = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 28) {
                // Icon + description
                VStack(spacing: 12) {
                    Image(systemName: "key.fill")
                        .font(.system(size: 56))
                        .foregroundStyle(.blue)

                    Text("TMDb API Key")
                        .font(.title2)
                        .fontWeight(.bold)

                    Text("Enter your free API key from The Movie Database to load movie data.")
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .padding(.top, 24)

                // Input
                VStack(alignment: .leading, spacing: 8) {
                    Text("API Key (v3 auth)")
                        .font(.subheadline)
                        .fontWeight(.medium)

                    SecureField("32-character API key", text: $apiKey)
                        .textFieldStyle(.roundedBorder)
                        .autocorrectionDisabled()
                        #if os(iOS)
                        .textInputAutocapitalization(.never)
                        .submitLabel(.done)
                        #endif
                        .onSubmit { trySave() }

                    Text("Find your key at themoviedb.org → Settings → API")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal)

                // Save button
                Button(action: trySave) {
                    Text("Save & Load Movies")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .disabled(apiKey.trimmingCharacters(in: .whitespaces).isEmpty)
                .padding(.horizontal)

                // Delete key option (when already set)
                if KeychainHelper.shared.hasAPIKey {
                    Button(role: .destructive) {
                        KeychainHelper.shared.deleteAPIKey()
                        isPresented = false
                    } label: {
                        Text("Remove Saved Key")
                    }
                    .font(.subheadline)
                }

                Spacer()
            }
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                if KeychainHelper.shared.hasAPIKey {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { isPresented = false }
                    }
                }
            }
            .alert("Invalid Key", isPresented: $showingLengthError) {
                Button("OK") {}
            } message: {
                Text("TMDb v3 API keys are exactly 32 characters. Please double-check and try again.")
            }
        }
    }

    private func trySave() {
        let trimmed = apiKey.trimmingCharacters(in: .whitespaces)
        guard trimmed.count == 32 else {
            showingLengthError = true
            return
        }
        KeychainHelper.shared.saveAPIKey(trimmed)
        isPresented = false
        onSave()
    }
}
