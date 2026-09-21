import SwiftUI

/// The athlete's own space, in the groups the web's Réglages hub uses: the model SHARPIT
/// holds of them, the account, what they prefer, and where their data comes from.
///
/// Grouped rather than flat: a list of unrelated panels gives no reason why Corps sits beside
/// Seuils. A surface the app has not built yet is named as coming, not hidden — the athlete
/// knows it exists on the web.
struct MeView<Account: View>: View {
    let appleHealth: AppleHealthSource
    let syncClient: any SyncServing
    let profileClient: any AthleteProfileServing & BodyCompositionServing
    let displayMode: DisplayModeStore
    let tokenProvider: () async throws -> String
    @ViewBuilder let account: Account

    @Environment(\.openURL) private var openURL
    @State private var status: V1SyncStatus?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: SharpitSpacing.section) {
                    account
                    modelGroup
                    accountGroup
                    preferencesGroup
                    dataGroup
                    aboutGroup
                }
                .padding(SharpitSpacing.pageInset)
            }
            .background(SharpitCanvasBackground())
            .navigationTitle("Moi")
            .navigationBarTitleDisplayMode(.inline)
            .task { await loadStatus() }
            .refreshable { await loadStatus() }
        }
    }

    /// What SHARPIT knows about this body and reads its training against.
    private var modelGroup: some View {
        SharpitHubGroup("Modèle") {
            NavigationLink {
                BodyView(client: profileClient, tokenProvider: tokenProvider)
            } label: {
                SharpitHubRow(
                    symbol: "heart.text.square",
                    title: "Corps",
                    detail: "Poids et composition, mesurés par ta balance"
                )
            }
            .buttonStyle(.sharpitPressable)
            NavigationLink {
                ThresholdsView(client: profileClient, tokenProvider: tokenProvider)
            } label: {
                SharpitHubRow(
                    symbol: "slider.horizontal.3",
                    title: "Seuils & repères",
                    detail: "FTP, allure seuil, FC max"
                )
            }
            .buttonStyle(.sharpitPressable)
            SharpitHubRow(symbol: "target", title: "Objectifs", comingSoon: true)
            SharpitHubRow(symbol: "bicycle", title: "Équipement", comingSoon: true)
            SharpitHubRow(symbol: "brain", title: "Mémoire du coach", comingSoon: true)
        }
    }

    private var accountGroup: some View {
        SharpitHubGroup("Compte") {
            NavigationLink {
                ProfileView(client: profileClient, tokenProvider: tokenProvider)
            } label: {
                SharpitHubRow(
                    symbol: "person.text.rectangle",
                    title: "Profil",
                    detail: "Taille, date de naissance, rythme visé"
                )
            }
            .buttonStyle(.sharpitPressable)
        }
    }

    private var preferencesGroup: some View {
        SharpitHubGroup("Préférences") {
            NavigationLink {
                DisplayModeView(
                    client: profileClient,
                    displayMode: displayMode,
                    tokenProvider: tokenProvider
                )
            } label: {
                SharpitHubRow(
                    symbol: "text.magnifyingglass",
                    title: "Densité de lecture",
                    detail: displayMode.isExpert ? "Expert" : "Essentiel"
                )
            }
            .buttonStyle(.sharpitPressable)
            SharpitHubRow(symbol: "paintbrush", title: "Apparence", comingSoon: true)
        }
    }

    /// Where the numbers come from. Garmin is connected on the web, where its sign-in lives;
    /// Apple Health is switched on here, because only the phone can read it.
    private var dataGroup: some View {
        SharpitHubGroup("Données") {
            Button {
                openURL(APIConfiguration.baseURL.appending(path: "/settings/integrations"))
            } label: {
                SharpitHubRow(
                    symbol: "applewatch.radiowaves.left.and.right",
                    title: "Garmin",
                    detail: garminDetail,
                    tone: garmin == nil ? SharpitColor.mutedForeground : SharpitColor.signalRecovery,
                    accessory: { SharpitHubChevron(leavesApp: true) }
                )
            }
            .buttonStyle(.sharpitPressable)
            .accessibilityHint("Ouvre les intégrations sur le web")
            appleHealthRow
            NavigationLink {
                HealthCoverageView(reader: HealthKitReader())
            } label: {
                SharpitHubRow(
                    symbol: "stethoscope",
                    title: "Diagnostic Apple Santé",
                    detail: "Ce qu'Apple Santé contient, signal par signal"
                )
            }
            .buttonStyle(.sharpitPressable)
        }
    }

    private var aboutGroup: some View {
        SharpitHubGroup("À propos") {
            Button {
                openURL(APIConfiguration.baseURL.appending(path: "/privacy"))
            } label: {
                SharpitHubRow(
                    symbol: "hand.raised",
                    title: "Confidentialité",
                    tone: SharpitColor.mutedForeground,
                    accessory: { SharpitHubChevron(leavesApp: true) }
                )
            }
            .buttonStyle(.sharpitPressable)
            Button {
                openURL(APIConfiguration.baseURL.appending(path: "/terms"))
            } label: {
                SharpitHubRow(
                    symbol: "doc.text",
                    title: "Conditions d'utilisation",
                    tone: SharpitColor.mutedForeground,
                    accessory: { SharpitHubChevron(leavesApp: true) }
                )
            }
            .buttonStyle(.sharpitPressable)
        }
    }

    private var garmin: V1SyncProvider? {
        status?.providers.first { $0.key == "garmin" }
    }

    private var garminDetail: String {
        guard status != nil else { return "Lecture du statut…" }
        guard let garmin else { return "Non connecté — se connecte sur le web" }
        guard let last = garmin.lastSyncAt else { return "Connecté" }
        return "Connecté · synchronisé " + SyncReadout.age(of: last, now: .now)
    }

    private var appleHealthRow: some View {
        SharpitHubRow(
            symbol: "heart.text.square.fill",
            title: "Apple Santé",
            detail: appleHealthDetail,
            tone: appleHealth.isEnabled ? SharpitColor.signalRisk : SharpitColor.mutedForeground,
            accessory: {
                Toggle(
                    "Apple Santé",
                    isOn: Binding(
                        get: { appleHealth.isEnabled },
                        set: { on in
                            if on {
                                Task { await appleHealth.enable(token: tokenProvider) }
                            } else {
                                appleHealth.disable()
                            }
                        }
                    )
                )
                .labelsHidden()
                .tint(SharpitColor.primary)
                .disabled(!appleHealth.isAvailable)
            }
        )
    }

    private var appleHealthDetail: String {
        if !appleHealth.isAvailable { return "Indisponible sur cet appareil" }
        switch appleHealth.state {
        case .sending: return "Envoi de la semaine…"
        case .failed(let message): return message
        case .idle:
            guard appleHealth.isEnabled else { return "Sommeil, FC repos, pas et poids dès que ta montre a synchronisé" }
            guard let sent = appleHealth.lastSentAt else { return "Activé — complète Garmin en attendant sa synchro" }
            return "Activé · envoyé " + SyncReadout.age(of: sent, now: .now)
        }
    }

    private func loadStatus() async {
        guard let token = try? await tokenProvider() else { return }
        status = try? await syncClient.syncStatus(token: token)
    }
}
