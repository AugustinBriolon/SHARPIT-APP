import Observation
import SwiftUI

/// The athlete's consents, read and changed one at a time — the web's privacy settings panel.
@MainActor
@Observable
final class PrivacySettingsStore {
    enum Phase: Equatable {
        case loading
        case loaded
        case failed(String)
        case unauthorized
    }

    private(set) var phase: Phase = .loading
    private(set) var consents: V1PrivacyConsents?
    private(set) var isSaving = false
    private(set) var saveError: String?

    private let client: any PrivacyConsentServing
    private let tokenProvider: () async throws -> String

    init(client: any PrivacyConsentServing, tokenProvider: @escaping () async throws -> String) {
        self.client = client
        self.tokenProvider = tokenProvider
    }

    func load() async {
        do {
            let token = try await tokenProvider()
            consents = try await client.consents(token: token)
            phase = .loaded
        } catch SharpitAPIError.unauthorized {
            phase = .unauthorized
        } catch {
            if consents == nil { phase = .failed("Lecture de tes consentements impossible.") }
        }
    }

    /// Writes one change and adopts what the server saved. Returns the saved consents, so the
    /// caller can hand a withdrawn health consent to the gate.
    @discardableResult
    func update(_ update: PrivacyConsentUpdate) async -> V1PrivacyConsents? {
        guard !isSaving else { return nil }
        isSaving = true
        saveError = nil
        defer { isSaving = false }
        do {
            let token = try await tokenProvider()
            let saved = try await client.updateConsents(update, token: token)
            SharpitMotion.run(SharpitMotion.selection) { consents = saved }
            return saved
        } catch SharpitAPIError.unauthorized {
            saveError = "Session expirée. Reconnecte-toi."
        } catch {
            saveError = "Enregistrement impossible. Réessaie."
        }
        return nil
    }
}

/// Moi → Confidentialité: the documents, the required health consent and the optional ones.
///
/// Withdrawing the health consent asks first, then puts the wall back at once — Résumé and the
/// physiological processing stop until it is given again, as on the web.
struct PrivacySettingsView: View {
    @State private var store: PrivacySettingsStore
    @Environment(AccountGateModel.self) private var gate: AccountGateModel?
    @State private var openDocument: LegalDocument?
    @State private var confirmsHealthWithdraw = false

    init(client: any PrivacyConsentServing, tokenProvider: @escaping () async throws -> String) {
        _store = State(initialValue: PrivacySettingsStore(client: client, tokenProvider: tokenProvider))
    }

    var body: some View {
        Group {
            switch store.phase {
            case .unauthorized:
                SharpitStateMessage.sessionExpired()
            case .failed(let message):
                SharpitStateMessage.failed(message) { Task { await store.load() } }
            case .loading, .loaded:
                list
            }
        }
        .navigationTitle("Confidentialité")
        .navigationBarTitleDisplayMode(.inline)
        .task { await store.load() }
        .sheet(item: $openDocument) { LegalDocumentSheet(document: $0) }
        .confirmationDialog(
            "Retirer le consentement santé ?",
            isPresented: $confirmsHealthWithdraw,
            titleVisibility: .visible
        ) {
            Button("Retirer", role: .destructive) {
                Task {
                    var update = PrivacyConsentUpdate()
                    update.healthDataConsent = false
                    if let saved = await store.update(update) {
                        gate?.consentsChanged(saved)
                    }
                }
            }
            Button("Annuler", role: .cancel) {}
        } message: {
            Text("Résumé et les traitements physiologiques seront bloqués immédiatement. Tu pourras réactiver le consentement sur l'écran dédié.")
        }
    }

    private var list: some View {
        List {
            Section(eyebrow: "Documents", footer: documentsFooter) {
                ForEach(LegalDocument.allCases) { document in
                    Button {
                        openDocument = document
                    } label: {
                        HStack {
                            Label {
                                Text(document.title)
                                    .font(SharpitTypography.bodyEmphasis)
                                    .foregroundStyle(SharpitColor.foreground)
                            } icon: {
                                SharpitRowIcon(symbol: document.symbol)
                            }
                            Spacer(minLength: 0)
                            Image(systemName: "chevron.right")
                                .font(SharpitTypography.meta.weight(.semibold))
                                .foregroundStyle(.tertiary)
                                .accessibilityHidden(true)
                        }
                        .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                }
            }
            .sharpitListRows()

            Section(eyebrow: "Données de santé (requis)", footer: PrivacyCopy.healthDisclaimer) {
                Toggle(isOn: healthBinding) {
                    consentLabel(
                        "Sync et traitements physiologiques",
                        detail: "Données de santé / physiologiques (art. 9). Sans ce consentement, l'accès à Résumé est bloqué."
                    )
                }
            }
            .sharpitListRows()

            Section(eyebrow: "Traitements optionnels") {
                Toggle(isOn: binding(\.hasAIConsent) { on in
                    var update = PrivacyConsentUpdate()
                    update.aiProcessingConsent = on
                    return update
                }) {
                    consentLabel(
                        "Traitement par IA",
                        detail: "Coach et bilans rédigés. Sans ce consentement, les moteurs déterministes restent disponibles."
                    )
                }
                Toggle(isOn: binding(\.hasUnofficialProvidersAck) { on in
                    var update = PrivacyConsentUpdate()
                    update.unofficialProvidersAck = on
                    return update
                }) {
                    consentLabel(
                        "Fournisseurs non officiels",
                        detail: "J'ai pris connaissance que certaines intégrations sont non officielles / « en l'état »."
                    )
                }
            }
            .sharpitListRows()

            if let saveError = store.saveError {
                Section {
                    Label(saveError, systemImage: "exclamationmark.triangle")
                        .font(SharpitTypography.meta)
                        .foregroundStyle(SharpitColor.signalRisk)
                }
                .listRowBackground(Color.clear)
            }
        }
        .sharpitGroupedList()
        .disabled(store.phase != .loaded || store.isSaving)
        .redacted(reason: store.phase == .loaded ? [] : .placeholder)
        .refreshable { await store.load() }
    }

    private var documentsFooter: String {
        let accepted = store.consents?.privacyVersion ?? "—"
        let current = store.consents?.currentPrivacyVersion ?? "—"
        return "Version acceptée : \(accepted) · actuelle : \(current). Contact : augustin.briolon@gmail.com"
    }

    private func consentLabel(_ title: String, detail: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(SharpitTypography.bodyEmphasis)
                .foregroundStyle(SharpitColor.foreground)
            Text(detail)
                .font(SharpitTypography.meta)
                .foregroundStyle(SharpitColor.mutedForeground)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// Turning health on writes at once; turning it off asks first.
    private var healthBinding: Binding<Bool> {
        Binding(
            get: { store.consents?.hasHealthConsent ?? false },
            set: { on in
                if on {
                    Task {
                        var update = PrivacyConsentUpdate()
                        update.healthDataConsent = true
                        await store.update(update)
                    }
                } else {
                    confirmsHealthWithdraw = true
                }
            }
        )
    }

    private func binding(
        _ keyPath: KeyPath<V1PrivacyConsents, Bool>,
        update: @escaping (Bool) -> PrivacyConsentUpdate
    ) -> Binding<Bool> {
        Binding(
            get: { store.consents?[keyPath: keyPath] ?? false },
            set: { on in Task { await store.update(update(on)) } }
        )
    }
}
