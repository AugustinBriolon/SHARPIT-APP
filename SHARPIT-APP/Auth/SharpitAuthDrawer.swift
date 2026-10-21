import AuthenticationServices
import ClerkKit
import SwiftUI

/// An Apple Design Award-grade authentication drawer in pure French, adhering strictly
/// to the SharpIt design system with zero extraneous clutter above the input field.
struct SharpitAuthDrawer: View {
    @Environment(Clerk.self) private var clerk
    @Environment(\.dismiss) private var dismiss
    /// Why an account is asked for, when the athlete arrives from the wizard.
    var headline: String?

    // Form states
    @State private var email = ""
    @State private var verificationCode = ""
    @State private var step: AuthStep = .identifier
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var isPasswordVisible = false
    @FocusState private var isPasswordFocused: Bool

    // Active session references
    @State private var activeSignIn: SignIn?
    @State private var activeSignUp: SignUp?

    private enum AuthStep {
        case identifier
        case codeVerification(email: String)
        case password(email: String)
    }

    var body: some View {
        NavigationStack {
            ZStack {
                SharpitColor.background.ignoresSafeArea()

                ScrollView {
                    VStack(spacing: SharpitSpacing.md) {
                        switch step {
                        case .identifier:
                            identifierView
                        case .codeVerification(let targetEmail):
                            codeVerificationView(email: targetEmail)
                        case .password(let targetEmail):
                            passwordView(email: targetEmail)
                        }
                    }
                    .padding(.horizontal, SharpitSpacing.pageInset)
                    .padding(.top, SharpitSpacing.lg)
                    .padding(.bottom, SharpitSpacing.xl)
                }
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(SharpitColor.foreground)
                    }
                    .accessibilityLabel("Fermer")
                }
            }
        }
        .sharpitSheet()
        .presentationDetents([.fraction(0.68), .large])
        .presentationDragIndicator(.visible)
    }

    // MARK: – Step 1: Identifier View (Direct Email Input, Zero Content Above)

    private var identifierView: some View {
        VStack(spacing: SharpitSpacing.md) {
            if let headline {
                Text(headline)
                    .font(SharpitTypography.verdict)
                    .tracking(SharpitTypography.verdictTracking)
                    .foregroundStyle(SharpitColor.foreground)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
            }

            // Error banner if any
            if let errorMessage {
                errorBanner(message: errorMessage)
            }

            // 1. Direct Email Input (Immediate top focus)
            HStack(spacing: SharpitSpacing.sm) {
                Image(systemName: "envelope")
                    .font(.system(size: 16))
                    .foregroundStyle(SharpitColor.mutedForeground)

                TextField("Adresse e-mail", text: $email)
                    .font(SharpitTypography.body)
                    .foregroundStyle(SharpitColor.foreground)
                    .keyboardType(.emailAddress)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
            }
            .padding(.horizontal, SharpitSpacing.md)
            .padding(.vertical, SharpitSpacing.md)
            .background {
                RoundedRectangle(cornerRadius: SharpitTokens.radius, style: .continuous)
                    .fill(SharpitColor.card)
                    .overlay(
                        RoundedRectangle(cornerRadius: SharpitTokens.radius, style: .continuous)
                            .strokeBorder(SharpitColor.border, lineWidth: 1)
                    )
                    .sharpitShadow(.control)
            }

            // 2. Primary Action Button
            Button {
                Task { await handleEmailSubmit() }
            } label: {
                HStack(spacing: SharpitSpacing.xs) {
                    if isLoading {
                        ProgressView()
                            .tint(SharpitColor.primaryForeground)
                    } else {
                        Text("Continuer")
                            .font(SharpitTypography.bodyEmphasis.weight(.semibold))
                            .foregroundStyle(SharpitColor.primaryForeground)

                        Image(systemName: "arrow.right")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(SharpitColor.primaryForeground.opacity(0.8))
                    }
                }
                .frame(maxWidth: .infinity)
                .frame(height: 52)
                .sharpitConcentricBackground(SharpitColor.primary, minimum: SharpitTokens.radius)
                .sharpitShadow(.panel)
            }
            .buttonStyle(.sharpitPressable)
            .disabled(email.trimmingCharacters(in: .whitespaces).isEmpty || isLoading)
            .opacity(email.trimmingCharacters(in: .whitespaces).isEmpty ? 0.6 : 1.0)

            // 3. Elegant "ou" Separator
            HStack(spacing: SharpitSpacing.sm) {
                Rectangle()
                    .fill(SharpitColor.border)
                    .frame(height: 1)
                Text("ou")
                    .font(SharpitTypography.meta)
                    .foregroundStyle(SharpitColor.mutedForeground)
                Rectangle()
                    .fill(SharpitColor.border)
                    .frame(height: 1)
            }
            .padding(.vertical, SharpitSpacing.xxs)

            // 4. Social Auth: Apple first, as App Review asks, Google beside it in the same shape
            VStack(spacing: SharpitSpacing.sm) {
                SharpitAppleSignInButton { Task { await handleAppleSignIn() } }
                    .disabled(isLoading)
                SharpitGoogleSignInButton { Task { await handleGoogleSignIn() } }
                    .disabled(isLoading)
            }

            // 5. Trust Footnote
            HStack(spacing: SharpitSpacing.xxs + 2) {
                Image(systemName: "lock.shield.fill")
                    .font(.system(size: 11))
                    .foregroundStyle(SharpitColor.mutedForeground.opacity(0.8))
                Text("Sécurisé par Clerk")
                    .font(SharpitTypography.meta)
                    .foregroundStyle(SharpitColor.mutedForeground.opacity(0.8))
            }
            .padding(.top, SharpitSpacing.xs)
        }
    }

    // MARK: – Step 2: Code Verification View

    private func codeVerificationView(email: String) -> some View {
        VStack(spacing: SharpitSpacing.md) {
            VStack(spacing: SharpitSpacing.xxs + 2) {
                Text("Code de vérification")
                    .font(SharpitTypography.pageTitle)
                    .tracking(SharpitTypography.pageTitleTracking)
                    .foregroundStyle(SharpitColor.foreground)

                Text("Saisis le code reçu à l'adresse\n\(email)")
                    .font(SharpitTypography.body)
                    .foregroundStyle(SharpitColor.mutedForeground)
                    .multilineTextAlignment(.center)
            }

            if let errorMessage {
                errorBanner(message: errorMessage)
            }

            // OTP Input
            HStack {
                TextField("Code à 6 chiffres", text: $verificationCode)
                    .font(SharpitTypography.data)
                    .tracking(SharpitTypography.dataTracking)
                    .multilineTextAlignment(.center)
                    .keyboardType(.numberPad)
                    .textContentType(.oneTimeCode)
            }
            .padding(.horizontal, SharpitSpacing.md)
            .padding(.vertical, SharpitSpacing.md)
            .background {
                RoundedRectangle(cornerRadius: SharpitTokens.radius, style: .continuous)
                    .fill(SharpitColor.card)
                    .overlay(
                        RoundedRectangle(cornerRadius: SharpitTokens.radius, style: .continuous)
                            .strokeBorder(SharpitColor.border, lineWidth: 1)
                    )
            }

            Button {
                Task { await handleVerifyCode() }
            } label: {
                HStack {
                    if isLoading {
                        ProgressView()
                            .tint(SharpitColor.primaryForeground)
                    } else {
                        Text("Valider")
                            .font(SharpitTypography.bodyEmphasis.weight(.semibold))
                            .foregroundStyle(SharpitColor.primaryForeground)
                    }
                }
                .frame(maxWidth: .infinity)
                .frame(height: 52)
                .sharpitConcentricBackground(SharpitColor.primary, minimum: SharpitTokens.radius)
            }
            .buttonStyle(.sharpitPressable)
            .disabled(verificationCode.trimmingCharacters(in: .whitespaces).isEmpty || isLoading)

            HStack(spacing: SharpitSpacing.md) {
                Button {
                    Task { await handleResendCode() }
                } label: {
                    Text("Renvoyer le code")
                        .font(SharpitTypography.bodyEmphasis)
                        .foregroundStyle(SharpitColor.foreground)
                }
                .disabled(isLoading)

                Text("•")
                    .foregroundStyle(SharpitColor.mutedForeground.opacity(0.4))

                Button {
                    step = .identifier
                    verificationCode = ""
                    errorMessage = nil
                } label: {
                    Text("Changer d'e-mail")
                        .font(SharpitTypography.body)
                        .foregroundStyle(SharpitColor.primary)
                }
            }
            .padding(.top, SharpitSpacing.xxs)

            if activeSignIn?.supportedFirstFactors?.contains(where: { $0.strategy == .password }) == true {
                Button {
                    verificationCode = ""
                    errorMessage = nil
                    step = .password(email: email)
                } label: {
                    Text("Se connecter avec un mot de passe à la place")
                        .font(SharpitTypography.body)
                        .foregroundStyle(SharpitColor.primary)
                }
                .padding(.top, SharpitSpacing.xxs)
            }
        }
    }

    // MARK: – Step 3: Password View

    private func passwordView(email: String) -> some View {
        VStack(spacing: SharpitSpacing.md) {
            VStack(spacing: SharpitSpacing.xxs + 2) {
                Text("Mot de passe")
                    .font(SharpitTypography.pageTitle)
                    .tracking(SharpitTypography.pageTitleTracking)
                    .foregroundStyle(SharpitColor.foreground)

                Text("Saisis ton mot de passe pour \(email)")
                    .font(SharpitTypography.body)
                    .foregroundStyle(SharpitColor.mutedForeground)
            }

            if let errorMessage {
                errorBanner(message: errorMessage)
            }

            passwordField
                .onChange(of: verificationCode) { _, _ in errorMessage = nil }
                .onAppear { isPasswordFocused = true }

            Button {
                Task { await handleVerifyPassword() }
            } label: {
                HStack {
                    if isLoading {
                        ProgressView()
                            .tint(SharpitColor.primaryForeground)
                    } else {
                        Text("Se connecter")
                            .font(SharpitTypography.bodyEmphasis.weight(.semibold))
                            .foregroundStyle(SharpitColor.primaryForeground)
                    }
                }
                .frame(maxWidth: .infinity)
                .frame(height: 52)
                .sharpitConcentricBackground(SharpitColor.primary, minimum: SharpitTokens.radius)
            }
            .buttonStyle(.sharpitPressable)
            .disabled(verificationCode.isEmpty || isLoading)

            VStack(spacing: SharpitSpacing.sm) {
                Button {
                    Task { await handleSwitchToEmailCode(email: email) }
                } label: {
                    HStack(spacing: SharpitSpacing.xxs + 2) {
                        Image(systemName: "envelope.badge")
                            .font(.system(size: 13))
                        Text("M'envoyer un code par e-mail à la place")
                            .font(SharpitTypography.bodyEmphasis)
                    }
                    .foregroundStyle(SharpitColor.primary)
                }
                .disabled(isLoading)

                Button {
                    step = .identifier
                    verificationCode = ""
                    errorMessage = nil
                } label: {
                    Text("Modifier l'adresse e-mail")
                        .font(SharpitTypography.body)
                        .foregroundStyle(SharpitColor.mutedForeground)
                }
            }
            .padding(.top, SharpitSpacing.xxs)
        }
    }

    // MARK: – Helpers & Icons

    private var passwordField: some View {
        HStack(spacing: SharpitSpacing.xs) {
            Group {
                if isPasswordVisible {
                    TextField("Mot de passe", text: $verificationCode)
                } else {
                    SecureField("Mot de passe", text: $verificationCode)
                }
            }
            .focused($isPasswordFocused)
            .textContentType(.password)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .font(SharpitTypography.body)

            Button {
                isPasswordVisible.toggle()
            } label: {
                Image(systemName: isPasswordVisible ? "eye.slash" : "eye")
                    .font(.system(size: 16))
                    .foregroundStyle(SharpitColor.mutedForeground)
                    .frame(width: 44, height: 44)
            }
            .accessibilityLabel(isPasswordVisible ? "Masquer le mot de passe" : "Afficher le mot de passe")
        }
        .padding(.leading, SharpitSpacing.md)
        .padding(.trailing, SharpitSpacing.xs)
        .padding(.vertical, SharpitSpacing.xs)
        .background {
            RoundedRectangle(cornerRadius: SharpitTokens.radius, style: .continuous)
                .fill(SharpitColor.card)
                .overlay(
                    RoundedRectangle(cornerRadius: SharpitTokens.radius, style: .continuous)
                        .strokeBorder(SharpitColor.border, lineWidth: 1)
                )
        }
    }

    private func errorBanner(message: String) -> some View {
        HStack(spacing: SharpitSpacing.xs) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 13))
                .foregroundStyle(SharpitColor.destructive)

            Text(message)
                .font(SharpitTypography.meta)
                .foregroundStyle(SharpitColor.destructive)
        }
        .padding(.horizontal, SharpitSpacing.sm)
        .padding(.vertical, SharpitSpacing.xs)
        .frame(maxWidth: .infinity, alignment: .leading)
        .sharpitConcentricBackground(SharpitColor.destructive.opacity(0.1), minimum: SharpitRadius.small)
    }

    // MARK: – Authentication Actions

    private func handleAppleSignIn() async {
        isLoading = true
        errorMessage = nil
        do {
            try await clerk.auth.signInWithApple()
            dismiss()
        } catch is CancellationError {
            // User dismissed Apple prompt
        } catch {
            errorMessage = String(localized: "Échec de la connexion Apple : \(error.localizedDescription)")
        }
        isLoading = false
    }

    private func handleGoogleSignIn() async {
        isLoading = true
        errorMessage = nil
        do {
            try await clerk.auth.signInWithOAuth(provider: .google)
            dismiss()
        } catch is CancellationError {
            // User dismissed Google sheet
        } catch {
            errorMessage = String(localized: "Échec de la connexion Google : \(error.localizedDescription)")
        }
        isLoading = false
    }

    private func handleEmailSubmit() async {
        let cleanEmail = email.trimmingCharacters(in: .whitespacesAndNewlines)
        guard cleanEmail.contains("@") && cleanEmail.contains(".") else {
            errorMessage = String(localized: "Adresse e-mail invalide.")
            return
        }

        isLoading = true
        errorMessage = nil

        do {
            let signIn = try await clerk.auth.signIn(cleanEmail)

            switch signIn.status {
            case .complete:
                if let sessionId = signIn.createdSessionId {
                    try await clerk.auth.setActive(sessionId: sessionId)
                }
                dismiss()
            case .needsFirstFactor:
                // Prioritize password when available (required for App Store Review demo accounts)
                let hasPassword = signIn.supportedFirstFactors?.contains(where: { $0.strategy == .password }) ?? false
                if hasPassword {
                    self.activeSignIn = signIn
                    verificationCode = ""
                    step = .password(email: cleanEmail)
                } else {
                    let preparedSignIn = try await signIn.sendEmailCode()
                    self.activeSignIn = preparedSignIn
                    step = .codeVerification(email: cleanEmail)
                }
            default:
                let preparedSignIn = try await signIn.sendEmailCode()
                self.activeSignIn = preparedSignIn
                step = .codeVerification(email: cleanEmail)
            }
        } catch {
            // If sign-in fails because user does not exist yet, attempt sign-up
            do {
                let signUp = try await clerk.auth.signUp(emailAddress: cleanEmail)
                let preparedSignUp = try await signUp.sendEmailCode()
                self.activeSignUp = preparedSignUp
                step = .codeVerification(email: cleanEmail)
            } catch let signUpError {
                errorMessage = String(localized: "Erreur : \(signUpError.localizedDescription)")
            }
        }
        isLoading = false
    }

    private func handleSwitchToEmailCode(email: String) async {
        isLoading = true
        errorMessage = nil
        do {
            if let activeSignIn {
                let prepared = try await activeSignIn.sendEmailCode()
                self.activeSignIn = prepared
                verificationCode = ""
                step = .codeVerification(email: email)
            } else {
                let signIn = try await clerk.auth.signIn(email)
                let prepared = try await signIn.sendEmailCode()
                self.activeSignIn = prepared
                verificationCode = ""
                step = .codeVerification(email: email)
            }
        } catch {
            errorMessage = String(localized: "Impossible d'envoyer le code : \(error.localizedDescription)")
        }
        isLoading = false
    }

    private func handleVerifyCode() async {
        let cleanCode = verificationCode.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanCode.isEmpty else { return }

        isLoading = true
        errorMessage = nil

        do {
            if let activeSignIn {
                let result = try await activeSignIn.verifyCode(cleanCode)
                self.activeSignIn = result
                if result.status == .complete {
                    if let sessionId = result.createdSessionId {
                        try await clerk.auth.setActive(sessionId: sessionId)
                    }
                    dismiss()
                } else if result.status.rawValue == "missing_requirements" {
                    errorMessage = String(localized: "Inscription incomplète : des informations complémentaires sont requises.")
                } else {
                    errorMessage = String(localized: "Vérification incomplète : \(result.status.rawValue)")
                }
            } else if let activeSignUp {
                let result = try await activeSignUp.verifyEmailCode(cleanCode)
                self.activeSignUp = result
                if result.status == .complete {
                    if let sessionId = result.createdSessionId {
                        try await clerk.auth.setActive(sessionId: sessionId)
                    }
                    dismiss()
                } else if result.status.rawValue == "missing_requirements" {
                    errorMessage = String(localized: "Inscription incomplète : des informations complémentaires sont requises.")
                } else {
                    errorMessage = String(localized: "Vérification incomplète : \(result.status.rawValue)")
                }
            }
        } catch let err {
            let desc = err.localizedDescription
            if desc.lowercased().contains("already been verified") {
                errorMessage = String(localized: "Ce code a déjà été validé. Demande un nouveau code pour continuer.")
            } else {
                errorMessage = desc
            }
        }
        isLoading = false
    }

    private func handleResendCode() async {
        isLoading = true
        errorMessage = nil
        do {
            if let activeSignIn {
                let prepared = try await activeSignIn.sendEmailCode()
                self.activeSignIn = prepared
                errorMessage = String(localized: "Un nouveau code a été envoyé !")
            } else if let activeSignUp {
                let prepared = try await activeSignUp.sendEmailCode()
                self.activeSignUp = prepared
                errorMessage = String(localized: "Un nouveau code a été envoyé !")
            }
        } catch {
            errorMessage = String(localized: "Impossible de renvoyer le code : \(error.localizedDescription)")
        }
        isLoading = false
    }

    private func handleVerifyPassword() async {
        guard let activeSignIn, !verificationCode.isEmpty else { return }

        isLoading = true
        errorMessage = nil

        do {
            let result = try await activeSignIn.authenticateWithPassword(verificationCode)
            self.activeSignIn = result
            guard result.status == .complete, let sessionId = result.createdSessionId else {
                errorMessage = String(localized: "Connexion incomplète. Vérifie ton compte ou essaie un code par e-mail.")
                isLoading = false
                return
            }
            try await clerk.auth.setActive(sessionId: sessionId)
            dismiss()
        } catch is URLError {
            errorMessage = String(localized: "Connexion impossible. Vérifie ton réseau et réessaie.")
        } catch {
            errorMessage = String(localized: "Mot de passe incorrect, ou compte introuvable. Réessaie.")
            verificationCode = ""
            isPasswordFocused = true
        }
        isLoading = false
    }
}
