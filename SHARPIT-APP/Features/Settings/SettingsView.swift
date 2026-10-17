import ClerkKit
import SwiftData
import SwiftUI
import UIKit
import UserNotifications

/// Paramètres, opened as a sheet from the avatar in Résumé and Corps.
///
/// The system's grouped list in the brand's dress (`docs/adr/0008`): who the athlete is and their
/// tier first, SharpIt Pro on the page's one ink row, the setting answered in place — appearance —
/// and only then the pages worth opening, each row saying its state before it is opened. The reading density is one of
/// those pages: the choice needs its explanation. What used to live in Moi and belongs elsewhere moved: the body to Corps, goals to
/// Plan, the coach's memory to Coach.
struct SettingsView: View {
    let appleHealth: AppleHealthSource
    let appleCalendar: AppleCalendarSource
    let syncClient: any SyncServing
    let profileClient: any AthleteProfileServing & BodyCompositionServing
    let displayMode: DisplayModeStore
    let features: FeatureStore
    let tokenProvider: () async throws -> String
    let modelContext: ModelContext?
    let privacyClient: any PrivacyConsentServing

    @Environment(\.dismiss) private var dismiss
    @AppStorage(AppearancePreference.storageKey) private var appearance: AppearancePreference = .system
    @State private var profile: AthleteProfileStore
    @State private var push = PushNotificationManager.shared
    @State private var notificationStatus: UNAuthorizationStatus?
    @Environment(ProStore.self) private var pro: ProStore?
    /// The pages open, the first one given when a notification opens Paramètres on it.
    @State private var path: [SettingsRoute]

    init(
        appleHealth: AppleHealthSource,
        appleCalendar: AppleCalendarSource,
        syncClient: any SyncServing,
        profileClient: any AthleteProfileServing & BodyCompositionServing,
        displayMode: DisplayModeStore,
        features: FeatureStore,
        tokenProvider: @escaping () async throws -> String,
        modelContext: ModelContext?,
        privacyClient: any PrivacyConsentServing = PrivacyConsentClient(),
        openingOn route: SettingsRoute? = nil
    ) {
        _path = State(initialValue: route.map { [$0] } ?? [])
        self.appleHealth = appleHealth
        self.appleCalendar = appleCalendar
        self.syncClient = syncClient
        self.profileClient = profileClient
        self.displayMode = displayMode
        self.features = features
        self.tokenProvider = tokenProvider
        self.modelContext = modelContext
        self.privacyClient = privacyClient
        _profile = State(initialValue: AthleteProfileStore(
            client: profileClient,
            tokenProvider: tokenProvider,
            modelContext: modelContext
        ))
    }

    var body: some View {
        NavigationStack(path: $path) {
            List {
                Section {
                    NavigationLink(value: SettingsRoute.account) {
                        AccountRow(isPro: isPro)
                    }
                }
                .sharpitListRows()

                // The page's one ink plate, as the verdict is on Résumé.
                Section {
                    NavigationLink(value: SettingsRoute.pro) {
                        ProRow(isPro: isPro)
                    }
                    .environment(\.colorScheme, .dark)
                    .listRowBackground(SharpitColor.inkSurface)
                }

                Section(eyebrow: "Apparence", footer: "Propre à cet iPhone.") {
                    SharpitSegmentedControl(
                        selection: $appearance,
                        options: AppearancePreference.allCases.map {
                            SharpitSegmentedControl<AppearancePreference>.Option(value: $0, label: $0.label, symbol: $0.symbol)
                        }
                    )
                    .listRowInsets(EdgeInsets(top: SharpitSpacing.sm, leading: SharpitSpacing.sm, bottom: SharpitSpacing.sm, trailing: SharpitSpacing.sm))
                }
                .sharpitListRows()

                Section(eyebrow: "Données") {
                    NavigationLink(value: SettingsRoute.sources) {
                        SharpitSettingsLabel(symbol: "link", title: "Sources de données", detail: sourcesDetail)
                    }
                    // A page, not a quick setting: the switch and the kinds it sends are one
                    // decision, and iOS may have the last word on it.
                    NavigationLink(value: SettingsRoute.notifications) {
                        SharpitSettingsLabel(symbol: "bell.badge", title: "Notifications", detail: notificationsDetail)
                    }
                }
                .sharpitListRows()

                Section(eyebrow: "Entraînement") {
                    NavigationLink(value: SettingsRoute.equipment) {
                        SharpitSettingsLabel(symbol: "figure.run.square.stack", title: "Sports & équipement", detail: sportsDetail)
                    }
                    // They calibrate training, not health: here rather than in Santé (SHARPIT ADR-053).
                    // Endurance thresholds mean nothing to a strength-only athlete.
                    if !PracticedSportCatalog.isStrengthOnly(profile.profile.practicedSports?.sports ?? []) {
                        NavigationLink(value: SettingsRoute.thresholds) {
                            SharpitSettingsLabel(symbol: "gauge.with.dots.needle.67percent", title: "Seuils d'entraînement", detail: "FTP, FC, allure, CSS")
                        }
                    }
                }
                .sharpitListRows()

                Section(eyebrow: "Affichage") {
                    NavigationLink(value: SettingsRoute.features) {
                        SharpitSettingsLabel(symbol: "square.grid.2x2", title: "Pages et widgets", detail: featuresDetail)
                    }
                    NavigationLink(value: SettingsRoute.density) {
                        SharpitSettingsLabel(symbol: "eye", title: "Densité de lecture", detail: displayMode.isExpert ? "Expert" : "Essentiel")
                    }
                }
                .sharpitListRows()

                // Hidden with the Nutrition page: switched off, it shows nowhere.
                if features.isOn(.nutrition) {
                    Section(eyebrow: "Nutrition") {
                        NavigationLink(value: SettingsRoute.ownFoods) {
                            SharpitSettingsLabel(symbol: "fork.knife", title: "Mes aliments", detail: "Créer, modifier, supprimer")
                        }
                    }
                    .sharpitListRows()
                }

                Section {
                    NavigationLink(value: SettingsRoute.feedback) {
                        SharpitSettingsLabel(symbol: "bubble.left.and.text.bubble.right", title: "Donner un avis", detail: "Un bug, une idée : je lis tout")
                    }
                    NavigationLink(value: SettingsRoute.privacy) {
                        SharpitSettingsLabel(symbol: "hand.raised", title: "Confidentialité & conditions", detail: "Consentements, CGU, données, compte")
                    }
                } header: {
                    SharpitEyebrow("Aide")
                } footer: {
                    footer
                }
                .sharpitListRows()
            }
            .sharpitGroupedList()
            .navigationTitle("Paramètres")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("OK") { dismiss() }
                }
            }
            .navigationDestination(for: SettingsRoute.self, destination: destination)
            .task { await profile.load() }
            .task { await refreshNotificationStatus() }
        }
        .sharpitSheet()
    }

    /// The web's word on the tier once `/api/v1/pro` answered, else the profile's.
    private var isPro: Bool {
        pro?.pro?.isPro ?? profile.profile.isPro
    }

    private func refreshNotificationStatus() async {
        notificationStatus = await push.authorizationStatus()
    }

    // MARK: - Details

    private var notificationsDetail: String {
        if notificationStatus == .denied { return "Refusées dans iOS" }
        guard push.isEnabledByAthlete else { return "Désactivées" }
        guard let prefs = profile.profile.notificationPrefs else { return "Verdict du matin" }
        let on = [
            prefs.morningVerdict ? "verdict du matin" : nil,
            prefs.weeklyReview ? "bilan" : nil,
            prefs.sessionReminder ? "rappels" : nil,
            prefs.sessionDone ? "séances faites" : nil,
            prefs.targetStrain ? "cible du jour" : nil,
            prefs.dayCheckIns ? "check-ins" : nil,
            prefs.missedSession ? "séances manquées" : nil,
            prefs.syncAlerts ? "alertes" : nil,
        ].compactMap { $0 }
        return on.isEmpty ? "Aucune" : on.joined(separator: ", ").capitalizedFirstLetter
    }

    private var sourcesDetail: String {
        appleHealth.isEnabled ? "Apple Santé activé" : "Apple Santé"
    }

    private var sportsDetail: String {
        let sports = PracticedSportCatalog.ordered(profile.profile.practicedSports?.sports ?? [])
        let labels = sports.compactMap { id in PracticedSportCatalog.all.first { $0.id == id }?.label }
        return labels.isEmpty ? "Tes disciplines et ton matériel" : labels.joined(separator: " · ")
    }

    /// « Tout est affiché », or what is hidden.
    private var featuresDetail: String {
        let off = SharpitFeature.allCases.filter { !features.isOn($0) }.map(\.title)
        return off.isEmpty ? "Tout est affiché" : "Masqué : " + off.joined(separator: ", ")
    }

    private var footer: some View {
        VStack(spacing: SharpitSpacing.xxs) {
            Text("SharpIt")
                .font(SharpitTypography.eyebrow)
                .tracking(SharpitTypography.eyebrowTracking * 2)
                .foregroundStyle(SharpitColor.mutedForeground)
            Text("Version \(AppVersion.display)")
                .font(SharpitTypography.meta)
                .foregroundStyle(SharpitColor.mutedForeground.opacity(0.7))
        }
        .frame(maxWidth: .infinity)
        .padding(.top, SharpitSpacing.lg)
    }

    // MARK: - Destinations

    @ViewBuilder
    private func destination(_ route: SettingsRoute) -> some View {
        switch route {
        case .account:
            AccountView(profileClient: profileClient, tokenProvider: tokenProvider, modelContext: modelContext)
        case .pro:
            if let pro {
                ProView(store: pro)
            }
        case .sources:
            ConnectionsView(
                appleHealth: appleHealth,
                appleCalendar: appleCalendar,
                syncClient: syncClient,
                tokenProvider: tokenProvider
            )
        case .equipment:
            EquipmentView(client: profileClient, tokenProvider: tokenProvider, modelContext: modelContext)
        case .thresholds:
            ThresholdsView(client: profileClient, tokenProvider: tokenProvider, modelContext: modelContext)
        case .privacy:
            PrivacySettingsView(client: privacyClient, tokenProvider: tokenProvider)
        case .notifications:
            NotificationPrefsView(profileClient: profileClient, tokenProvider: tokenProvider, modelContext: modelContext)
        case .features:
            FeaturesView(store: features, tokenProvider: tokenProvider)
        case .ownFoods:
            OwnFoodsSettingsView(tokenProvider: tokenProvider)
        case .feedback:
            FeedbackView(tokenProvider: tokenProvider)
        case .density:
            DisplayModeView(
                client: profileClient,
                displayMode: displayMode,
                tokenProvider: tokenProvider,
                modelContext: modelContext
            )
        }
    }
}

enum SettingsRoute: Hashable {
    case account
    case pro
    case sources
    case equipment
    case thresholds
    case privacy
    case notifications
    case density
    case features
    case ownFoods
    case feedback
}

private extension String {
    var capitalizedFirstLetter: String { prefix(1).uppercased() + dropFirst() }
}

// MARK: - Building blocks

/// The athlete, as the page opens: face, name, e-mail, tier.
private struct AccountRow: View {
    let isPro: Bool

    @Environment(Clerk.self) private var clerk
    @ScaledMetric(relativeTo: .title2) private var avatarSize: CGFloat = 56

    var body: some View {
        HStack(spacing: SharpitSpacing.md) {
            AccountAvatar(size: avatarSize)
            VStack(alignment: .leading, spacing: 2) {
                Text(name)
                    .font(SharpitTypography.sectionTitle)
                    .tracking(SharpitTypography.sectionTitleTracking)
                    .foregroundStyle(SharpitColor.foreground)
                    .lineLimit(1)
                if let email = clerk.user?.primaryEmailAddress?.emailAddress {
                    Text(email)
                        .font(SharpitTypography.meta)
                        .foregroundStyle(SharpitColor.mutedForeground)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 0)
            SharpitPill(isPro ? "Pro" : "Gratuit", style: isPro ? .lime : .neutral)
        }
        .padding(.vertical, SharpitSpacing.xs)
        .accessibilityElement(children: .combine)
        .accessibilityHint("Ouvre ton compte")
    }

    private var name: String {
        let parts = [clerk.user?.firstName, clerk.user?.lastName]
            .compactMap { $0?.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        return parts.isEmpty ? "Ton compte" : parts.joined(separator: " ")
    }
}

/// SharpIt Pro on the ink row: what it is, and what tapping does.
private struct ProRow: View {
    let isPro: Bool

    var body: some View {
        HStack(spacing: SharpitSpacing.md) {
            SharpitIconTile(symbol: "sparkle")
            VStack(alignment: .leading, spacing: 2) {
                Text("SharpIt Pro")
                    .font(SharpitTypography.cardTitle)
                    .tracking(SharpitTypography.cardTitleTracking)
                    .foregroundStyle(SharpitColor.inkSurfaceForeground)
                Text(isPro ? "Tout SharpIt est ouvert pour toi." : "Bilan hebdo, analyse de séance, lecture coach du journal.")
                    .font(SharpitTypography.meta)
                    .foregroundStyle(SharpitColor.mutedForeground)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
            if !isPro {
                SharpitPill("Découvrir", style: .lime)
            }
        }
        .padding(.vertical, SharpitSpacing.xs)
        .accessibilityElement(children: .combine)
    }
}
