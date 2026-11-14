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
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                header
                    .revealed(hasAppeared, index: 0)
                group(String(localized: "Nécessaires pour utiliser SharpIt")) {
                    ConsentCheckRow(isOn: $terms, document: .terms, onRead: { openDocument = .terms }) {
                        ConsentLabel(title: String(localized: "Conditions d'utilisation"))
                    }
                    ConsentCheckRow(isOn: $privacy, document: .privacy, onRead: { openDocument = .privacy }) {
                        ConsentLabel(title: String(localized: "Politique de confidentialité"))
                    }
                    ConsentCheckRow(isOn: $health) {
                        ConsentLabel(
                            title: String(localized: "Traitement de mes données de santé"),
                            detail: String(localized: "Sommeil, fréquence cardiaque, poids, analyses : pour lire ta forme.")
                        )
                    }
                }
                .revealed(hasAppeared, index: 1)
                group(String(localized: "Facultatifs, modifiables à tout moment")) {
                    ConsentCheckRow(isOn: $ai) {
                        ConsentLabel(
                            title: String(localized: "Lecture par l'IA du coach"),
                            detail: String(localized: "Sans elle : tes données et ton plan, sans coach ni ajustements.")
                        )
                    }
                    ConsentCheckRow(isOn: $unofficialProviders) {
                        ConsentLabel(
                            title: String(localized: "Sources non officielles"),
                            detail: String(localized: "Connexions sans partenariat avec le fabricant, moins stables.")
                        )
                    }
                }
                .revealed(hasAppeared, index: 2)
                Text(PrivacyCopy.healthDisclaimer)
                    .font(SharpitTypography.system(size: 13, weight: .regular, relativeTo: .footnote))
                    .foregroundStyle(SharpitColor.slate)
                    .fixedSize(horizontal: false, vertical: true)
                    .revealed(hasAppeared, index: 3)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 24)
            .padding(.top, SharpitSpacing.xl)
            .padding(.bottom, SharpitSpacing.xl)
        }
        .safeAreaInset(edge: .bottom, spacing: 0) { actionBar }
        .sharpitRegularColumn()
        .cliniqueSheet(wash: .neutral, height: 220)
        .sheet(item: $openDocument) { document in
            LegalDocumentSheet(document: document)
        }
        .onAppear { SharpitMotion.run { hasAppeared = true } }
    }

    // MARK: - Content

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            if reason == .healthWithdrawn {
                CliniqueStatusPill(String(localized: "Consentement santé retiré"), status: .watch)
            }
            Text("Avant de continuer")
                .font(SharpitTypography.system(size: 32, weight: .semibold, relativeTo: .largeTitle))
                .tracking(-0.6)
                .foregroundStyle(SharpitColor.foreground)
                .accessibilityAddTraits(.isHeader)
            Text(description)
                .font(SharpitTypography.system(size: 17, weight: .regular, relativeTo: .body))
                .foregroundStyle(SharpitColor.slate)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// A named run of consents, split by hairlines.
    private func group<Rows: View>(_ title: String, @ViewBuilder rows: () -> Rows) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(SharpitTypography.system(size: 14, weight: .regular, relativeTo: .footnote))
                .foregroundStyle(SharpitColor.slate)
            Group(subviews: rows()) { subviews in
                ForEach(subviews) { row in
                    if row.id != subviews.first?.id { CliniqueDivider() }
                    row
                }
            }
        }
    }

    private var actionBar: some View {
        VStack(spacing: 4) {
            if let error {
                Label(error, systemImage: "exclamationmark.triangle")
                    .font(SharpitTypography.meta)
                    .foregroundStyle(SharpitColor.signalRisk)
                    .padding(.horizontal, SharpitSpacing.sm)
                    .padding(.vertical, SharpitSpacing.xxs + 2)
                    .sharpitGlassCapsule()
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
            Button {
                SharpitMotion.run(SharpitMotion.selection) {
                    terms = true; privacy = true; health = true; ai = true; unofficialProviders = true
                }
                Task { await submit() }
            } label: {
                Group {
                    if isSaving { ProgressView().tint(SharpitColor.primaryForeground) } else { Text("Tout accepter") }
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(CliniqueButtonStyle(kind: .primary, isLarge: true))
            .disabled(isSaving)
            Button(cta) { Task { await submit() } }
                .buttonStyle(CliniqueButtonStyle(kind: .plain))
                .foregroundStyle(SharpitColor.foreground)
                .disabled(!canSubmit)
        }
        .animation(SharpitMotion.reveal, value: error)
        .padding(.horizontal, 24)
        .padding(.top, SharpitSpacing.sm)
        .padding(.bottom, SharpitSpacing.xs)
        .background(SharpitColor.card)
    }

    // MARK: - Copy (the web's `consentWallCopy`)

    private var description: String {
        switch reason {
        case .healthWithdrawn:
            String(localized: "Tu as retiré ton consentement pour les données de santé. Résumé et les traitements physiologiques restent bloqués tant que tu ne le réactives pas.")
        case .documents:
            String(localized: "Tes données de santé restent à toi. Voici ce que tu acceptes, point par point.")
        }
    }

    private var cta: String { reason == .healthWithdrawn ? String(localized: "Réactiver avec ma sélection") : String(localized: "Continuer avec ma sélection") }

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
            await onAccepted(saved)
        } catch SharpitAPIError.unauthorized {
            self.error = String(localized: "Session expirée. Reconnecte-toi.")
        } catch {
            self.error = String(localized: "Enregistrement impossible. Réessaie.")
        }
    }
}

/// Copy shared by the wall and Moi → Confidentialité, in the web's words.
enum PrivacyCopy {
    static let healthDisclaimer =
        String(localized: "SharpIt est un outil d'aide à l'entraînement. Ce n'est pas un dispositif médical et ça ne remplace pas un avis médical. Les signaux (récupération, fatigue, risques) sont des estimations d'entraînement, pas un diagnostic.")
}

/// A consent's words: what it is, and under it what it covers.
struct ConsentLabel: View {
    let title: String
    var detail: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(SharpitTypography.system(size: 17, weight: .semibold, relativeTo: .body))
                .foregroundStyle(SharpitColor.foreground)
            if let detail {
                Text(detail)
                    .font(SharpitTypography.system(size: 14, weight: .regular, relativeTo: .footnote))
                    .foregroundStyle(SharpitColor.slate)
            }
        }
    }
}

/// A checkbox row: the whole row toggles, and a document it names opens with « Lire » without
/// ticking anything.
struct ConsentCheckRow<Content: View>: View {
    @Binding var isOn: Bool
    var document: LegalDocument?
    var onRead: (() -> Void)?
    @ViewBuilder let label: Content

    var body: some View {
        HStack(alignment: .center, spacing: SharpitSpacing.sm) {
            Button {
                SharpitMotion.run(SharpitMotion.selection) { isOn.toggle() }
            } label: {
                HStack(alignment: .center, spacing: 14) {
                    Image(systemName: isOn ? "checkmark.square.fill" : "square")
                        .font(.system(size: 24, weight: .regular))
                        .foregroundStyle(isOn ? SharpitColor.foreground : SharpitColor.outline)
                        .contentTransition(.symbolEffect(.replace))
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
                Button(action: onRead) { Text("Lire").underline() }
                    .font(SharpitTypography.system(size: 15, weight: .regular, relativeTo: .subheadline))
                    .foregroundStyle(SharpitColor.slate)
                    .accessibilityLabel("Lire \(document.title)")
            }
        }
        .padding(.vertical, 12)
        .frame(minHeight: SharpitSpacing.minimumTouchTarget)
    }
}
