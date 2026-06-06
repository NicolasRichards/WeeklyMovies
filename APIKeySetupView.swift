import SwiftUI

struct APIKeySetupView: View {
    @Binding var isPresented: Bool
    let onSave: () -> Void

    @State private var apiKey = ""
    @State private var validationState: ValidationState = .idle

    private let tmdbAPIURL = URL(string: "https://www.themoviedb.org/settings/api")!
    private let tmdbSignupURL = URL(string: "https://www.themoviedb.org/signup")!

    enum ValidationState {
        case idle, validating, invalid(String), valid
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 32) {
                    headerSection
                    stepsSection
                    inputSection
                    actionSection
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 32)
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
        }
    }

    // MARK: - Sections

    private var headerSection: some View {
        VStack(spacing: 12) {
            Image(systemName: "popcorn.fill")
                .font(.system(size: 64))
                .foregroundStyle(.yellow)

            Text("One quick setup")
                .font(.title)
                .fontWeight(.bold)

            Text("Weekly Movies uses The Movie Database (TMDb) for all its data. A free TMDb account gives you a personal API key — it takes about two minutes.")
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
    }

    private var stepsSection: some View {
        VStack(spacing: 0) {
            stepRow(number: "1", title: "Create a free TMDb account", detail: "No credit card required.", action: {
                Link("Sign up at themoviedb.org →", destination: tmdbSignupURL)
                    .font(.subheadline)
            })
            Divider().padding(.leading, 44)
            stepRow(number: "2", title: "Request an API key", detail: "Go to Settings → API and click \"Create\". Choose \"Developer\" when asked.", action: {
                Link("Open TMDb API settings →", destination: tmdbAPIURL)
                    .font(.subheadline)
            })
            Divider().padding(.leading, 44)
            stepRow(number: "3", title: "Paste your key below", detail: "Copy the v3 auth key (32 characters) and paste it in the field below.", action: {
                EmptyView()
            })
        }
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
    }

    private var inputSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Your API Key (v3 auth)")
                .font(.subheadline)
                .fontWeight(.medium)

            HStack(spacing: 10) {
                SecureField("Paste 32-character key here", text: $apiKey)
                    .textFieldStyle(.roundedBorder)
                    .autocorrectionDisabled()
                    #if os(iOS)
                    .textInputAutocapitalization(.never)
                    .keyboardType(.asciiCapable)
                    #endif
                    .onChange(of: apiKey) { validationState = .idle }
                    .onSubmit { Task { await validate() } }

                if !apiKey.isEmpty {
                    Button {
                        apiKey = ""
                        validationState = .idle
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }

            validationFeedback
        }
    }

    @ViewBuilder
    private var validationFeedback: some View {
        switch validationState {
        case .idle:
            EmptyView()
        case .validating:
            HStack(spacing: 6) {
                ProgressView().scaleEffect(0.8)
                Text("Verifying key…")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        case .invalid(let message):
            Label(message, systemImage: "xmark.circle.fill")
                .font(.caption)
                .foregroundStyle(.red)
        case .valid:
            Label("Key verified!", systemImage: "checkmark.circle.fill")
                .font(.caption)
                .foregroundStyle(.green)
        }
    }

    private var actionSection: some View {
        VStack(spacing: 16) {
            Button {
                Task { await validate() }
            } label: {
                Group {
                    if case .validating = validationState {
                        ProgressView()
                            .tint(.white)
                    } else {
                        Text("Verify & Save Key")
                    }
                }
                .frame(maxWidth: .infinity)
                .frame(height: 20)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(!canSubmit)

            if KeychainHelper.shared.hasAPIKey {
                Button(role: .destructive) {
                    KeychainHelper.shared.deleteAPIKey()
                    isPresented = false
                } label: {
                    Text("Remove Saved Key")
                }
                .font(.subheadline)
            }
        }
    }

    // MARK: - Helpers

    private var canSubmit: Bool {
        let trimmed = apiKey.trimmingCharacters(in: .whitespaces)
        guard trimmed.count == 32 else { return false }
        if case .validating = validationState { return false }
        return true
    }

    private func validate() async {
        let trimmed = apiKey.trimmingCharacters(in: .whitespaces)
        guard trimmed.count == 32 else {
            validationState = .invalid("TMDb v3 keys are exactly 32 characters.")
            return
        }
        validationState = .validating
        do {
            try await TMDbService.shared.validateAPIKey(trimmed)
            validationState = .valid
            KeychainHelper.shared.saveAPIKey(trimmed)
            try? await Task.sleep(nanoseconds: 600_000_000)
            isPresented = false
            onSave()
        } catch TMDbError.unauthorized {
            validationState = .invalid("Key not recognised by TMDb. Double-check you copied the v3 auth key.")
        } catch {
            validationState = .invalid("Couldn't reach TMDb. Check your connection and try again.")
        }
    }

    @ViewBuilder
    private func stepRow<A: View>(number: String, title: String, detail: String, @ViewBuilder action: () -> A) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text(number)
                .font(.headline)
                .foregroundStyle(.white)
                .frame(width: 28, height: 28)
                .background(.blue, in: Circle())

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                action()
            }
            Spacer()
        }
        .padding(14)
    }
}
