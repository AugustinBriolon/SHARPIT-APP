import AuthenticationServices
import ClerkKit
import SwiftUI

/// An Apple Design Award-grade authentication drawer in pure French, adhering strictly
/// to the SharpIt design system with zero extraneous clutter above the input field.
struct SharpitAuthDrawer: View {
    @Environment(Clerk.self) private var clerk
    @Environment(\.dismiss) private var dismiss

    // Form states
    @State private var email = ""
    @State private var verificationCode = ""
    @State private var step: AuthStep = .identifier
    @State private var isLoading = false
    @State private var errorMessage: String?

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
                    VStack(spacing: 20) {
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
        .presentationBackground(SharpitColor.background)
        .presentationDetents([.fraction(0.68), .large])
        .presentationDragIndicator(.visible)
    }

    // MARK: – Step 1: Identifier View (Direct Email Input, Zero Content Above)

    private var identifierView: some View {
        VStack(spacing: 18) {
            // Error banner if any
            if let errorMessage {
                errorBanner(message: errorMessage)
            }

            // 1. Direct Email Input (Immediate top focus)
            HStack(spacing: 12) {
                Image(systemName: "envelope")
                    .font(.system(size: 16))
                    .foregroundStyle(SharpitColor.mutedForeground)

                TextField("Adresse e-mail", text: $email)
                    .font(.custom(SharpitFontFamily.body.resolvedName(for: .regular) ?? "System", size: 16))
                    .foregroundStyle(SharpitColor.foreground)
                    .keyboardType(.emailAddress)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 16)
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
                SharpitHaptics.play(.light)
                Task { await handleEmailSubmit() }
            } label: {
                HStack(spacing: 8) {
                    if isLoading {
                        ProgressView()
                            .tint(SharpitColor.primaryForeground)
                    } else {
                        Text("Continuer")
                            .font(.custom(SharpitFontFamily.body.resolvedName(for: .semibold) ?? "System", size: 16))
                            .foregroundStyle(SharpitColor.primaryForeground)

                        Image(systemName: "arrow.right")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(SharpitColor.primaryForeground.opacity(0.8))
                    }
                }
                .frame(maxWidth: .infinity)
                .frame(height: 52)
                .background(SharpitColor.primary, in: RoundedRectangle(cornerRadius: SharpitTokens.radius, style: .continuous))
                .sharpitShadow(.panel)
            }
            .buttonStyle(.sharpitPressable)
            .disabled(email.trimmingCharacters(in: .whitespaces).isEmpty || isLoading)
            .opacity(email.trimmingCharacters(in: .whitespaces).isEmpty ? 0.6 : 1.0)

            // 3. Elegant "ou" Separator
            HStack(spacing: 14) {
                Rectangle()
                    .fill(SharpitColor.border)
                    .frame(height: 1)
                Text("ou")
                    .font(.custom(SharpitFontFamily.body.resolvedName(for: .regular) ?? "System", size: 13))
                    .foregroundStyle(SharpitColor.mutedForeground)
                Rectangle()
                    .fill(SharpitColor.border)
                    .frame(height: 1)
            }
            .padding(.vertical, 4)

            // 4. Social Auth: Google & Apple
            VStack(spacing: 12) {
                // Google Sign In
                Button {
                    SharpitHaptics.play(.light)
                    Task { await handleGoogleSignIn() }
                } label: {
                    HStack(spacing: 12) {
                        googleIcon
                        Text("Continuer avec Google")
                            .font(.custom(SharpitFontFamily.body.resolvedName(for: .medium) ?? "System", size: 15))
                            .foregroundStyle(SharpitColor.foreground)
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 50)
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
                .buttonStyle(.sharpitPressable)
                .disabled(isLoading)

                // Apple Sign In
                Button {
                    SharpitHaptics.play(.light)
                    Task { await handleAppleSignIn() }
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "apple.logo")
                            .font(.system(size: 17))
                            .foregroundStyle(SharpitColor.foreground)

                        Text("Continuer avec Apple")
                            .font(.custom(SharpitFontFamily.body.resolvedName(for: .medium) ?? "System", size: 15))
                            .foregroundStyle(SharpitColor.foreground)
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 50)
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
                .buttonStyle(.sharpitPressable)
                .disabled(isLoading)
            }

            // 5. Trust Footnote
            HStack(spacing: 6) {
                Image(systemName: "lock.shield.fill")
                    .font(.system(size: 11))
                    .foregroundStyle(SharpitColor.mutedForeground.opacity(0.8))
                Text("Sécurisé par Clerk")
                    .font(.custom(SharpitFontFamily.body.resolvedName(for: .regular) ?? "System", size: 12))
                    .foregroundStyle(SharpitColor.mutedForeground.opacity(0.8))
            }
            .padding(.top, 10)
        }
    }

    // MARK: – Step 2: Code Verification View

    private func codeVerificationView(email: String) -> some View {
        VStack(spacing: 20) {
            VStack(spacing: 6) {
                Text("Code de vérification")
                    .font(.custom(SharpitFontFamily.heading.resolvedName(for: .bold) ?? "System", size: 22))
                    .foregroundStyle(SharpitColor.foreground)

                Text("Saisis le code reçu à l'adresse\n\(email)")
                    .font(.custom(SharpitFontFamily.body.resolvedName(for: .regular) ?? "System", size: 14))
                    .foregroundStyle(SharpitColor.mutedForeground)
                    .multilineTextAlignment(.center)
            }

            if let errorMessage {
                errorBanner(message: errorMessage)
            }

            // OTP Input
            HStack {
                TextField("Code à 6 chiffres", text: $verificationCode)
                    .font(.custom(SharpitFontFamily.data.resolvedName(for: .medium) ?? "Menlo", size: 22))
                    .multilineTextAlignment(.center)
                    .keyboardType(.numberPad)
                    .textContentType(.oneTimeCode)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 16)
            .background {
                RoundedRectangle(cornerRadius: SharpitTokens.radius, style: .continuous)
                    .fill(SharpitColor.card)
                    .overlay(
                        RoundedRectangle(cornerRadius: SharpitTokens.radius, style: .continuous)
                            .strokeBorder(SharpitColor.border, lineWidth: 1)
                    )
            }

            Button {
                SharpitHaptics.play(.light)
                Task { await handleVerifyCode() }
            } label: {
                HStack {
                    if isLoading {
                        ProgressView()
                            .tint(SharpitColor.primaryForeground)
                    } else {
                        Text("Valider")
                            .font(.custom(SharpitFontFamily.body.resolvedName(for: .semibold) ?? "System", size: 16))
                            .foregroundStyle(SharpitColor.primaryForeground)
                    }
                }
                .frame(maxWidth: .infinity)
                .frame(height: 52)
                .background(SharpitColor.primary, in: RoundedRectangle(cornerRadius: SharpitTokens.radius, style: .continuous))
            }
            .buttonStyle(.sharpitPressable)
            .disabled(verificationCode.trimmingCharacters(in: .whitespaces).isEmpty || isLoading)

            HStack(spacing: 16) {
                Button {
                    SharpitHaptics.play(.light)
                    Task { await handleResendCode() }
                } label: {
                    Text("Renvoyer le code")
                        .font(.custom(SharpitFontFamily.body.resolvedName(for: .medium) ?? "System", size: 14))
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
                        .font(.custom(SharpitFontFamily.body.resolvedName(for: .regular) ?? "System", size: 14))
                        .foregroundStyle(SharpitColor.primary)
                }
            }
            .padding(.top, 4)
        }
    }

    // MARK: – Step 3: Password View

    private func passwordView(email: String) -> some View {
        VStack(spacing: 20) {
            VStack(spacing: 6) {
                Text("Mot de passe")
                    .font(.custom(SharpitFontFamily.heading.resolvedName(for: .bold) ?? "System", size: 22))
                    .foregroundStyle(SharpitColor.foreground)

                Text("Saisis ton mot de passe pour \(email)")
                    .font(.custom(SharpitFontFamily.body.resolvedName(for: .regular) ?? "System", size: 14))
                    .foregroundStyle(SharpitColor.mutedForeground)
            }

            if let errorMessage {
                errorBanner(message: errorMessage)
            }

            SecureField("Mot de passe", text: $verificationCode)
                .font(.custom(SharpitFontFamily.body.resolvedName(for: .regular) ?? "System", size: 16))
                .padding(.horizontal, 16)
                .padding(.vertical, 16)
                .background {
                    RoundedRectangle(cornerRadius: SharpitTokens.radius, style: .continuous)
                        .fill(SharpitColor.card)
                        .overlay(
                            RoundedRectangle(cornerRadius: SharpitTokens.radius, style: .continuous)
                                .strokeBorder(SharpitColor.border, lineWidth: 1)
                        )
                }

            Button {
                SharpitHaptics.play(.light)
                Task { await handleVerifyPassword() }
            } label: {
                HStack {
                    if isLoading {
                        ProgressView()
                            .tint(SharpitColor.primaryForeground)
                    } else {
                        Text("Se connecter")
                            .font(.custom(SharpitFontFamily.body.resolvedName(for: .semibold) ?? "System", size: 16))
                            .foregroundStyle(SharpitColor.primaryForeground)
                    }
                }
                .frame(maxWidth: .infinity)
                .frame(height: 52)
                .background(SharpitColor.primary, in: RoundedRectangle(cornerRadius: SharpitTokens.radius, style: .continuous))
            }
            .buttonStyle(.sharpitPressable)
            .disabled(verificationCode.isEmpty || isLoading)

            Button {
                step = .identifier
                verificationCode = ""
                errorMessage = nil
            } label: {
                Text("Modifier l'adresse e-mail")
                    .font(.custom(SharpitFontFamily.body.resolvedName(for: .regular) ?? "System", size: 14))
                    .foregroundStyle(SharpitColor.primary)
            }
        }
    }

    // MARK: – Helpers & Icons

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

    private var googleIcon: some View {
        Image(systemName: "g.circle.fill")
            .font(.system(size: 19))
            .foregroundStyle(SharpitColor.foreground)
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
            errorMessage = "Échec de la connexion Apple : \(error.localizedDescription)"
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
            errorMessage = "Échec de la connexion Google : \(error.localizedDescription)"
        }
        isLoading = false
    }

    private func handleEmailSubmit() async {
        let cleanEmail = email.trimmingCharacters(in: .whitespacesAndNewlines)
        guard cleanEmail.contains("@") && cleanEmail.contains(".") else {
            errorMessage = "Adresse e-mail invalide."
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
                if let factor = signIn.supportedFirstFactors?.first {
                    switch factor.strategy {
                    case .password:
                        self.activeSignIn = signIn
                        step = .password(email: cleanEmail)
                    default:
                        let preparedSignIn = try await signIn.sendEmailCode()
                        self.activeSignIn = preparedSignIn
                        step = .codeVerification(email: cleanEmail)
                    }
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
                errorMessage = "Erreur : \(signUpError.localizedDescription)"
            }
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
                } else {
                    errorMessage = "Vérification incomplète : \(result.status.rawValue)"
                }
            } else if let activeSignUp {
                let result = try await activeSignUp.verifyEmailCode(cleanCode)
                self.activeSignUp = result
                if result.status == .complete {
                    if let sessionId = result.createdSessionId {
                        try await clerk.auth.setActive(sessionId: sessionId)
                    }
                    dismiss()
                } else {
                    errorMessage = "Vérification incomplète : \(result.status.rawValue)"
                }
            }
        } catch let err {
            errorMessage = err.localizedDescription
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
                errorMessage = "Un nouveau code a été envoyé !"
            } else if let activeSignUp {
                let prepared = try await activeSignUp.sendEmailCode()
                self.activeSignUp = prepared
                errorMessage = "Un nouveau code a été envoyé !"
            }
        } catch {
            errorMessage = "Impossible de renvoyer le code : \(error.localizedDescription)"
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
            if result.status == .complete {
                if let sessionId = result.createdSessionId {
                    try await clerk.auth.setActive(sessionId: sessionId)
                }
                dismiss()
            }
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }
}
