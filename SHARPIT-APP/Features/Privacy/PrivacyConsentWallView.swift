import SwiftUI

/// The web's `/consent` wall, rendered natively: the two documents and the health consent are
/// required together, AI processing and the unofficial-providers notice are optional and can
/// be given later from Moi → Confidentialité.
struct PrivacyConsentWallView: View {
    let reason: V1PrivacyConsents.WallReason
    let client: any PrivacyConsentServing
    let tokenProvider: () async throws -> String
    /// Called with the consents as saved; the gate then moves on.
    let onAccepted: (V1PrivacyConsents) async -> Void

    @State private var terms = false
    @State private var privacy = false
    @State private var health = false
    @State private var ai: Bool
    @State private var unofficialProviders: Bool
    @State private var isSaving = false
    @State private var error: String?
    @State private var openDocument: LegalDocument?
    @State private var hasAppeared = false

    init(
        reason: V1PrivacyConsents.WallReason,
        initial: V1PrivacyConsents?,
        client: any PrivacyConsentServing,
        tokenProvider: @escaping () async throws -> String,
        onAccepted: @escaping (V1PrivacyConsents) async -> Void
    ) {
        self.reason = reason
        self.client = client
        self.tokenProvider = tokenProvider
        self.onAccepted = onAccepted
        // An optional consent already given stays ticked: the wall never withdraws one.
        _ai = State(initialValue: initial?.hasAIConsent ?? false)
        _unofficialProviders = State(initialValue: initial?.hasUnofficialProvidersAck ?? false)
    }

    private var canSubmit: Bool { terms && privacy && health && !isSaving }

    var body: some View {
        ZStack {
            SharpitCanvasBackground()
            ScrollView {
                VStack(alignment: .leading, spacing: SharpitSpacing.lg) {
                    header
                        .revealed(hasAppeared, index: 0)
                    requiredPanel
                        .revealed(hasAppeared, index: 1)
                    optionalPanel
                        .revealed(hasAppeared, index: 2)
                    disclaimer
                        .revealed(hasAppeared, index: 3)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, SharpitSpacing.pageInset)
                .padding(.top, SharpitSpacing.xl)
                .padding(.bottom, SharpitSpacing.xl)
            }
            .safeAreaInset(edge: .bottom, spacing: 0) { actionBar }
        }
        .sheet(item: $openDocument) { document in
            LegalDocumentSheet(document: document)
        }
        .sensoryFeedback(.success, trigger: canSubmit) { _, ready in ready }
        .onAppear { SharpitMotion.run { hasAppeared = true } }
    }

    // MARK: - Content

    private var header: some View {
        VStack(alignment: .leading, spacing: SharpitSpacing.sm) {
            SharpitEyebrow(reason == .healthWithdrawn ? "Données de santé" : "Avant de commencer", systemImage: "hand.raised.fill")
            Text(title)
                .font(SharpitTypography.pageTitle)
                .tracking(SharpitTypography.pageTitleTracking)
                .foregroundStyle(SharpitColor.foreground)
                .accessibilityAddTraits(.isHeader)
            Text(description)
                .font(SharpitTypography.body)
                .foregroundStyle(SharpitColor.mutedForeground)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var requiredPanel: some View {
        VStack(alignment: .leading, spacing: 0) {
            ConsentCheckRow(isOn: $terms, document: .terms, onRead: { openDocument = .terms }) {
                Text("J'accepte les Conditions d'utilisation.")
            }
            Divider().padding(.leading, 44)
            ConsentCheckRow(isOn: $privacy, document: .privacy, onRead: { openDocument = .privacy }) {
                Text("J'accepte la Politique de confidentialité.")
            }
            Divider().padding(.leading, 44)
            ConsentCheckRow(isOn: $health) {
                Text("J'autorise la synchronisation et le traitement de mes données de santé / physiologiques (Twin, récupération, fatigue).")
            }
        }
        .padding(.horizontal, SharpitSpacing.cardPadding)
        .sharpitSurface(.panel)
    }

    private var optionalPanel: some View {
        VStack(alignment: .leading, spacing: SharpitSpacing.xs) {
            Text("OPTIONNEL — TU POURRAS AUSSI LES ACTIVER PLUS TARD")
                .font(SharpitTypography.label)
                .tracking(SharpitTypography.labelTracking)
                .foregroundStyle(SharpitColor.mutedForeground)
            VStack(alignment: .leading, spacing: 0) {
                ConsentCheckRow(isOn: $ai) {
                    Text("J'autorise le traitement par IA (coach, bilans rédigés). Les moteurs déterministes du Twin fonctionnent sans ce consentement.")
                }
                Divider().padding(.leading, 44)
                ConsentCheckRow(isOn: $unofficialProviders) {
                    Text("Je comprends que certaines connexions fournisseurs peuvent être non officielles.")
                }
            }
            .padding(.horizontal, SharpitSpacing.cardPadding)
            .sharpitSurface(.panelAlt)
        }
    }

    private var disclaimer: some View {
        Text(PrivacyCopy.healthDisclaimer)
            .font(SharpitTypography.meta)
            .foregroundStyle(SharpitColor.mutedForeground)
            .padding(.leading, SharpitSpacing.sm)
            .overlay(alignment: .leading) {
                Rectangle()
                    .fill(SharpitColor.border)
                    .frame(width: 2)
            }
            .fixedSize(horizontal: false, vertical: true)
    }

    private var actionBar: some View {
        VStack(alignment: .leading, spacing: SharpitSpacing.xs) {
            if let error {
                Label(error, systemImage: "exclamationmark.triangle")
                    .font(SharpitTypography.meta)
                    .foregroundStyle(SharpitColor.signalRisk)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
            Button {
                SharpitHaptics.play(.light)
                Task { await submit() }
            } label: {
                HStack(spacing: SharpitSpacing.xs) {
                    if isSaving {
                        ProgressView().tint(SharpitColor.primaryForeground)
                    }
                    Text(isSaving ? ctaBusy : cta)
                        .contentTransition(.opacity)
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(SharpitColor.primary)
            .controlSize(.large)
            .disabled(!canSubmit)
            .animation(SharpitMotion.selection, value: canSubmit)
        }
        .animation(SharpitMotion.reveal, value: error)
        .padding(.horizontal, SharpitSpacing.pageInset)
        .padding(.top, SharpitSpacing.sm)
        .padding(.bottom, SharpitSpacing.xs)
        .background(SharpitCanvasBackground())
    }

    // MARK: - Copy (the web's `consentWallCopy`)

    private var title: String {
        reason == .healthWithdrawn ? "Consentement santé retiré" : "Confidentialité & conditions"
    }

    private var description: String {
        switch reason {
        case .healthWithdrawn:
            "Tu as retiré ton consentement pour les données de santé. Résumé et les traitements physiologiques restent bloqués tant que tu ne le réactives pas."
        case .documents:
            "Avant d'utiliser SharpIt, accepte les documents légaux et le traitement des données de santé."
        }
    }

    private var cta: String { reason == .healthWithdrawn ? "Réactiver et continuer" : "Continuer" }
    private var ctaBusy: String { reason == .healthWithdrawn ? "Réactivation…" : "Enregistrement…" }

    // MARK: - Save

    private func submit() async {
        guard canSubmit else { return }
        isSaving = true
        error = nil
        defer { isSaving = false }
        do {
            let token = try await tokenProvider()
            let saved = try await client.updateConsents(
                .wall(ai: ai, unofficialProviders: unofficialProviders),
                token: token
            )
            SharpitHaptics.play(.success)
            await onAccepted(saved)
        } catch SharpitAPIError.unauthorized {
            self.error = "Session expirée. Reconnecte-toi."
        } catch {
            self.error = "Enregistrement impossible. Réessaie."
        }
    }
}

/// Copy shared by the wall and Moi → Confidentialité, in the web's words.
enum PrivacyCopy {
    static let healthDisclaimer =
        "SharpIt est un outil d'aide à l'entraînement. Ce n'est pas un dispositif médical et ça ne remplace pas un avis médical. Les signaux (récupération, fatigue, risques) sont des estimations d'entraînement, pas un diagnostic."
}

/// A checkbox row: the whole row toggles, and a document it names opens with « Lire » without
/// ticking anything.
private struct ConsentCheckRow<Content: View>: View {
    @Binding var isOn: Bool
    var document: LegalDocument?
    var onRead: (() -> Void)?
    @ViewBuilder let label: Content

    var body: some View {
        HStack(alignment: .top, spacing: SharpitSpacing.sm) {
            Button {
                SharpitHaptics.play(.soft)
                SharpitMotion.run(SharpitMotion.selection) { isOn.toggle() }
            } label: {
                HStack(alignment: .top, spacing: SharpitSpacing.sm) {
                    Image(systemName: isOn ? "checkmark.square.fill" : "square")
                        .font(.system(size: 22, weight: .regular))
                        .foregroundStyle(isOn ? SharpitColor.primary : SharpitColor.mutedForeground.opacity(0.6))
                        .contentTransition(.symbolEffect(.replace))
                        .frame(width: 28)
                    label
                        .font(SharpitTypography.body)
                        .foregroundStyle(SharpitColor.foreground)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                }
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .accessibilityAddTraits(isOn ? [.isSelected] : [])

            if let document, let onRead {
                Button("Lire", action: onRead)
                    .font(SharpitTypography.meta.weight(.semibold))
                    .foregroundStyle(SharpitColor.primary)
                    .accessibilityLabel("Lire \(document.title)")
            }
        }
        .padding(.vertical, SharpitSpacing.sm)
        .frame(minHeight: SharpitSpacing.minimumTouchTarget)
    }
}
