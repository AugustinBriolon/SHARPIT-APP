import SwiftUI

/// An in-app native modal sheet to connect a Garmin account using direct credentials.
/// Replaces the external browser redirect that lost the Clerk session on mobile.
struct GarminConnectSheet: View {
    let garminClient: any GarminConnecting
    let tokenProvider: () async throws -> String
    let onConnected: () -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var email = ""
    @State private var password = ""
    @State private var isLoading = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            ZStack {
                SharpitColor.background.ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 22) {
                        // Header
                        VStack(spacing: 12) {
                            ProviderLogo(provider: .garmin)

                            Text("Connecter Garmin")
                                .font(.custom(SharpitFontFamily.heading.resolvedName(for: .bold) ?? "System", size: 22))
                                .foregroundStyle(SharpitColor.foreground)

                            Text("Renseigne tes identifiants Garmin Connect pour synchroniser tes séances, ton sommeil et ta récupération.")
                                .font(.custom(SharpitFontFamily.body.resolvedName(for: .regular) ?? "System", size: 14))
                                .foregroundStyle(SharpitColor.mutedForeground)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal, 8)
                        }
                        .padding(.top, 8)

                        // Error Banner
                        if let errorMessage {
                            errorBanner(message: errorMessage)
                        }

                        // Form Fields
                        VStack(spacing: 14) {
                            // Email field
                            HStack(spacing: 12) {
                                Image(systemName: "envelope")
                                    .font(.system(size: 16))
                                    .foregroundStyle(SharpitColor.mutedForeground)
                                    .frame(width: 20)

                                TextField("Adresse e-mail Garmin", text: $email)
                                    .font(.custom(SharpitFontFamily.body.resolvedName(for: .regular) ?? "System", size: 16))
                                    .foregroundStyle(SharpitColor.foreground)
                                    .keyboardType(.emailAddress)
                                    .textInputAutocapitalization(.never)
                                    .autocorrectionDisabled()
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 15)
                            .background {
                                RoundedRectangle(cornerRadius: SharpitTokens.radius, style: .continuous)
                                    .fill(SharpitColor.card)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: SharpitTokens.radius, style: .continuous)
                                            .strokeBorder(SharpitColor.border, lineWidth: 1)
                                    )
                                    .sharpitShadow(.control)
                            }

                            // Password field
                            HStack(spacing: 12) {
                                Image(systemName: "lock")
                                    .font(.system(size: 16))
                                    .foregroundStyle(SharpitColor.mutedForeground)
                                    .frame(width: 20)

                                SecureField("Mot de passe Garmin", text: $password)
                                    .font(.custom(SharpitFontFamily.body.resolvedName(for: .regular) ?? "System", size: 16))
                                    .foregroundStyle(SharpitColor.foreground)
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 15)
                            .background {
                                RoundedRectangle(cornerRadius: SharpitTokens.radius, style: .continuous)
                                    .fill(SharpitColor.card)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: SharpitTokens.radius, style: .continuous)
                                            .strokeBorder(SharpitColor.border, lineWidth: 1)
                                    )
                                    .sharpitShadow(.control)
                            }
                        }

                        // Action Button
                        Button {
                            SharpitHaptics.play(.light)
                            Task { await handleConnect() }
                        } label: {
                            HStack(spacing: 8) {
                                if isLoading {
                                    ProgressView()
                                        .tint(SharpitColor.primaryForeground)
                                    Text("Connexion en cours…")
                                        .font(.custom(SharpitFontFamily.body.resolvedName(for: .semibold) ?? "System", size: 16))
                                        .foregroundStyle(SharpitColor.primaryForeground)
                                } else {
                                    Text("Connecter mon compte")
                                        .font(.custom(SharpitFontFamily.body.resolvedName(for: .semibold) ?? "System", size: 16))
                                        .foregroundStyle(SharpitColor.primaryForeground)
                                }
                            }
                            .frame(maxWidth: .infinity)
                            .frame(height: 52)
                            .background(SharpitColor.primary, in: RoundedRectangle(cornerRadius: SharpitTokens.radius, style: .continuous))
                            .sharpitShadow(.panel)
                        }
                        .buttonStyle(.sharpitPressable)
                        .disabled(email.trimmingCharacters(in: .whitespaces).isEmpty || password.isEmpty || isLoading)
                        .opacity(email.trimmingCharacters(in: .whitespaces).isEmpty || password.isEmpty ? 0.6 : 1.0)

                        // Privacy & Security guarantee note
                        HStack(alignment: .top, spacing: 8) {
                            Image(systemName: "lock.shield.fill")
                                .font(.system(size: 13))
                                .foregroundStyle(SharpitColor.mutedForeground.opacity(0.8))
                                .padding(.top, 1)

                            Text("Tes identifiants sont chiffrés et utilisés uniquement pour générer une clé de synchronisation sécurisée. Ton mot de passe n'est jamais stocké en clair.")
                                .font(.custom(SharpitFontFamily.body.resolvedName(for: .regular) ?? "System", size: 12))
                                .foregroundStyle(SharpitColor.mutedForeground.opacity(0.8))
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .padding(.horizontal, 4)
                        .padding(.top, 4)
                    }
                    .padding(.horizontal, SharpitSpacing.pageInset)
                    .padding(.top, 24)
                    .padding(.bottom, 36)
                }
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(SharpitColor.mutedForeground)
                            .padding(8)
                            .background(Circle().fill(SharpitColor.card))
                    }
                    .accessibilityLabel("Fermer")
                }
            }
        }
        .presentationDetents([.fraction(0.68), .large])
        .presentationDragIndicator(.visible)
        .presentationBackground(SharpitColor.background)
    }

    private func errorBanner(message: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 13))
                .foregroundStyle(SharpitColor.destructive)

            Text(message)
                .font(.custom(SharpitFontFamily.body.resolvedName(for: .regular) ?? "System", size: 13))
                .foregroundStyle(SharpitColor.destructive)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(SharpitColor.destructive.opacity(0.1), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private func handleConnect() async {
        let cleanEmail = email.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanEmail.isEmpty, !password.isEmpty else { return }

        isLoading = true
        errorMessage = nil

        do {
            let token = try await tokenProvider()
            _ = try await garminClient.connectGarmin(username: cleanEmail, password: password, token: token)
            SharpitHaptics.play(.success)
            onConnected()
            dismiss()
        } catch {
            SharpitHaptics.play(.error)
            errorMessage = error.localizedDescription
        }

        isLoading = false
    }
}
