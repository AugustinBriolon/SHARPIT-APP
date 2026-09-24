import SwiftData
import SwiftUI

/// The athlete's own space: who is signed in, what SHARPIT knows of them, how they read it,
/// where the data comes from.
///
/// Built like the system's Settings: the account first, then short groups of rows that open
/// something. Surfaces the app has not built yet are named once, in a footer, rather than as
/// rows — a row that cannot be tapped still looks like it can, and four of them took a third
/// of the screen for nothing the athlete could do.
struct MeView<Account: View>: View {
    let appleHealth: AppleHealthSource
    let syncClient: any SyncServing
    let profileClient: any AthleteProfileServing & BodyCompositionServing
    let displayMode: DisplayModeStore
    let tokenProvider: () async throws -> String
    let modelContext: ModelContext?
    var goalClient: any GoalServing = GoalClient()
    var coachMemoryClient: any CoachMemoryServing = CoachMemoryClient()
    var privacyClient: any PrivacyConsentServing = PrivacyConsentClient()
    @ViewBuilder let account: Account

    var body: some View {
        NavigationStack {
            List {
                Section { account }.sharpitListRows()
                Section(eyebrow: "Modèle") { modelRows }.sharpitListRows()
                Section(eyebrow: "Entraînement") { trainingRows }.sharpitListRows()
                Section(
                    eyebrow: "Préférences",
                    footer: "À venir : apparence."
                ) { preferencesRows }
                .sharpitListRows()
                Section(eyebrow: "À propos") { aboutRows }.sharpitListRows()
            }
            .sharpitGroupedList()
            .navigationTitle("Moi")
            .navigationBarTitleDisplayMode(.large)
        }
    }

    /// What SHARPIT knows about this athlete and reads their training against.
    @ViewBuilder
    private var modelRows: some View {
        NavigationLink {
            BodyView(
                client: profileClient,
                profileClient: profileClient,
                tokenProvider: tokenProvider,
                modelContext: modelContext
            )
        } label: {
            rowLabel("Corps", symbol: "figure.stand", background: MeTone.body)
        }
        NavigationLink {
            ThresholdsView(client: profileClient, tokenProvider: tokenProvider, modelContext: modelContext)
        } label: {
            rowLabel("Seuils et repères", symbol: "gauge.with.dots.needle.67percent", background: MeTone.thresholds)
        }
        NavigationLink {
            ProfileView(client: profileClient, tokenProvider: tokenProvider, modelContext: modelContext)
        } label: {
            rowLabel("Profil", symbol: "person.text.rectangle", background: MeTone.profile)
        }
    }

    /// Goals, gear inventory and coach context.
    @ViewBuilder
    private var trainingRows: some View {
        NavigationLink {
            GoalsView(client: goalClient, tokenProvider: tokenProvider)
        } label: {
            rowLabel("Objectifs", symbol: "flag.fill", background: MeTone.goals)
        }
        NavigationLink {
            EquipmentView(client: profileClient, tokenProvider: tokenProvider, modelContext: modelContext)
        } label: {
            rowLabel("Sports & équipement", symbol: "figure.run.square.stack", background: MeTone.gear)
        }
        NavigationLink {
            CoachMemoryView(client: coachMemoryClient, tokenProvider: tokenProvider)
        } label: {
            rowLabel("Mémoire du coach", symbol: "brain.head.profile", background: MeTone.coach)
        }
    }

    @ViewBuilder
    private var preferencesRows: some View {
        NavigationLink {
            DisplayModeView(
                client: profileClient,
                displayMode: displayMode,
                tokenProvider: tokenProvider,
                modelContext: modelContext
            )
        } label: {
            LabeledContent {
                Text(displayMode.isExpert ? "Expert" : "Essentiel")
                    .font(SharpitTypography.body)
                    .foregroundStyle(SharpitColor.mutedForeground)
            } label: {
                rowLabel("Densité de lecture", symbol: "eye.fill", background: MeTone.density)
            }
        }
        NavigationLink {
            ConnectionsView(appleHealth: appleHealth, syncClient: syncClient, tokenProvider: tokenProvider)
        } label: {
            rowLabel("Connexions", symbol: "link", background: MeTone.connections)
        }
    }

    /// The documents and every consent, in one screen — the wall's counterpart once past it.
    @ViewBuilder
    private var aboutRows: some View {
        NavigationLink {
            PrivacySettingsView(client: privacyClient, tokenProvider: tokenProvider)
        } label: {
            rowLabel("Confidentialité & conditions", symbol: "hand.raised.fill", background: MeTone.privacy)
        }
    }

    private func rowLabel(_ title: String, symbol: String, background: Color) -> some View {
        Label {
            Text(title)
                .font(SharpitTypography.bodyEmphasis)
                .foregroundStyle(SharpitColor.foreground)
        } icon: {
            SharpitRowIcon(symbol: symbol, background: background)
        }
    }
}

private enum MeTone {
    // MODÈLE
    static let body = Color(red: 0.94, green: 0.38, blue: 0.42)
    static let thresholds = Color(red: 0.98, green: 0.52, blue: 0.12)
    static let profile = Color(red: 0.20, green: 0.50, blue: 0.95)

    // ENTRAÎNEMENT
    static let goals = Color(red: 0.98, green: 0.70, blue: 0.12)
    static let gear = SharpitColor.primary
    static let coach = Color(red: 0.58, green: 0.36, blue: 0.88)

    // PRÉFÉRENCES
    static let density = Color(red: 0.34, green: 0.44, blue: 0.86)
    static let connections = Color(red: 0.12, green: 0.68, blue: 0.62)

    // À PROPOS
    static let privacy = Color(red: 0.44, green: 0.50, blue: 0.58)
}
