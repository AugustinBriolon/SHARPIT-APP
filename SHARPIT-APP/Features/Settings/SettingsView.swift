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
    @Environment(ShellRouter.self) private var router: ShellRouter?
    @AppStorage(AppearancePreference.storageKey) private var appearance: AppearancePreference = .system
    @State private var profile: AthleteProfileStore
    @State private var push = PushNotificationManager.shared
    @State private var notificationStatus: UNAuthorizationStatus?
    @State private var providerKeys: [String] = []
    /// The coach's budget, read when the page opens; the line shows only once it is known.
    @State private var coachQuota: V1CoachQuota?
    @State private var showingCoachUsage = false
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
                        SharpitSettingsLabel(title: String(localized: "Ton profil"), detail: profileDetail, symbol: "person")
                    }
                    // They calibrate training, not health: here rather than in Santé (SHARPIT ADR-053).
                    // Endurance thresholds mean nothing to a strength-only athlete.
                    if !PracticedSportCatalog.isStrengthOnly(profile.profile.practicedSports?.sports ?? []) {
                        NavigationLink(value: SettingsRoute.thresholds) {
                            SharpitSettingsLabel(title: String(localized: "Seuils et repères"), symbol: "gauge.with.dots.needle.50percent")
                        }
                    }
                    NavigationLink(value: SettingsRoute.equipment) {
                        SharpitSettingsLabel(title: String(localized: "Matériel"), detail: sportsDetail, symbol: "bicycle")
                    }
                    // Goals live in Plan: the row closes Paramètres and opens them there.
                    if let router {
                        Button {
                            dismiss()
                            router.open(.goals)
                        } label: {
                            HStack(spacing: SharpitSpacing.sm) {
                                SharpitSettingsLabel(title: String(localized: "Objectifs"), symbol: "flag")
                                Image(systemName: "chevron.right")
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundStyle(SharpitColor.slate.opacity(0.5))
                                    .accessibilityHidden(true)
                            }
                            .contentShape(.rect)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .sharpitListRows()

                Section {
                    NavigationLink(value: SettingsRoute.coachMemory) {
                        SharpitSettingsLabel(title: String(localized: "Mémoire du coach"), symbol: "brain")
                    }
                    if let coachQuota {
                        Button { showingCoachUsage = true } label: {
                            CoachUsageLine(quota: coachQuota)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .sharpitListRows()

                Section {
                    NavigationLink(value: SettingsRoute.sources) {
                        SharpitSettingsLabel(title: String(localized: "Connexions"), detail: sourcesDetail, symbol: "link")
                    }
                    NavigationLink(value: SettingsRoute.features) {
                        SharpitSettingsLabel(title: String(localized: "Pages et widgets"), detail: featuresDetail, symbol: "square.grid.2x2")
                    }
                    // A page, not a quick setting: the switch and the kinds it sends are one
                    // decision, and iOS may have the last word on it.
                    NavigationLink(value: SettingsRoute.notifications) {
                        SharpitSettingsLabel(title: String(localized: "Notifications"), detail: notificationsDetail, symbol: "bell")
                    }
                    // Answered in place, per iPhone: the row is its own menu.
                    Picker(selection: $appearance) {
                        ForEach(AppearancePreference.allCases, id: \.self) { Text($0.label).tag($0) }
                    } label: {
                        HStack(spacing: SharpitSpacing.sm) {
                            SharpitSettingsGlyph(symbol: "circle.lefthalf.filled")
                            Text("Affichage")
                                .font(SharpitTypography.system(size: 17, weight: .regular, relativeTo: .body))
                        }
                        .padding(.vertical, 3)
                    }
                    .pickerStyle(.menu)
                    .tint(SharpitColor.slate)
                    NavigationLink(value: SettingsRoute.density) {
                        SharpitSettingsLabel(title: String(localized: "Densité de lecture"), detail: displayMode.isExpert ? String(localized: "Expert") : String(localized: "Essentiel"), symbol: "text.alignleft")
                    }
                    NavigationLink(value: SettingsRoute.language) {
                        SharpitSettingsLabel(title: String(localized: "Langue"), detail: AppLanguage.chosen.displayName, symbol: "globe")
                    }
                }
                .sharpitListRows()

                Section {
                    NavigationLink(value: SettingsRoute.pro) {
                        SharpitSettingsLabel(title: "SharpIt Pro", detail: isPro || pro?.pro?.subscription != nil ? ProReadout.status(pro?.pro?.subscription, isPro: isPro) : String(localized: "Découvrir"), symbol: "sparkles")
                    }
                    // Hidden with the Nutrition page: switched off, it shows nowhere.
                    if features.isOn(.nutrition) {
                        NavigationLink(value: SettingsRoute.ownFoods) {
                            SharpitSettingsLabel(title: String(localized: "Mes aliments"), symbol: "fork.knife")
                        }
                    }
                    NavigationLink(value: SettingsRoute.feedback) {
                        SharpitSettingsLabel(title: String(localized: "Donner un avis"), symbol: "bubble.left")
                    }
                    NavigationLink(value: SettingsRoute.privacy) {
                        SharpitSettingsLabel(title: String(localized: "Confidentialité & conditions"), symbol: "lock")
                    }
                } footer: {
                    footer
                }
                .sharpitListRows()
            }
            .sharpitGroupedList(cards: true)
            .navigationTitle("Paramètres")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button { dismiss() } label: { Image(systemName: "xmark") }
                        .accessibilityLabel("Fermer")
                }
                // The tier, said once where the page opens.
                SharpitBarBadge {
                    CliniqueStatusPill(isPro ? String(localized: "Pro") : String(localized: "Gratuit"), status: isPro ? .pro : .unknown)
                }
            }
            .navigationDestination(for: SettingsRoute.self, destination: destination)
            .task { await profile.load() }
            .task { await refreshNotificationStatus() }
            .task { await refreshProviderKeys() }
            .task { coachQuota = try? await CoachQuotaClient().quota(token: try await tokenProvider()) }
            .sheet(isPresented: $showingCoachUsage) {
                CoachUsageSheet(quota: coachQuota) {
                    showingCoachUsage = false
                    path.append(.pro)
                }
            }
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

    private var profileDetail: String? {
        SettingsReadout.profile(birthDate: profile.profile.birthDate, heightCm: profile.profile.heightCm)
    }

    private var notificationsDetail: String {
        if notificationStatus == .denied { return String(localized: "Refusées dans iOS") }
        guard push.isEnabledByAthlete else { return String(localized: "Désactivées") }
        guard let prefs = profile.profile.notificationPrefs else { return String(localized: "Verdict du matin") }
        let on = [
            prefs.morningVerdict ? String(localized: "verdict du matin") : nil,
            prefs.weeklyReview ? "bilan" : nil,
            prefs.sessionReminder ? "rappels" : nil,
            prefs.sessionDone ? String(localized: "séances faites") : nil,
            prefs.targetStrain ? String(localized: "cible du jour") : nil,
            prefs.dayCheckIns ? "check-ins" : nil,
            prefs.missedSession ? String(localized: "séances manquées") : nil,
            prefs.syncAlerts ? "alertes" : nil,
        ].compactMap { $0 }
        return on.isEmpty ? String(localized: "Aucune") : on.joined(separator: ", ").capitalizedFirst
    }

    private var sourcesDetail: String {
        ConnectionsReadout.sourcesSummary(ConnectionsReadout.linkedSources(
            providerKeys: providerKeys,
            appleHealthEnabled: appleHealth.isEnabled,
            appleCalendarLinked: appleCalendar.isLinked
        ))
    }

    /// Offline, the line counts the iPhone's own sources only.
    private func refreshProviderKeys() async {
        guard let token = try? await tokenProvider(),
              let status = try? await syncClient.syncStatus(token: token) else { return }
        providerKeys = status.providers.map(\.key)
    }

    private var sportsDetail: String? {
        let sports = PracticedSportCatalog.ordered(profile.profile.practicedSports?.sports ?? [])
        let labels = sports.compactMap { id in PracticedSportCatalog.all.first { $0.id == id }?.label }
        return labels.isEmpty ? nil : labels.joined(separator: " · ")
    }

    /// « Tout est affiché », or what is hidden.
    private var featuresDetail: String {
        let off = SharpitFeature.allCases.filter { !features.isOn($0) }.map(\.title)
        return off.isEmpty ? String(localized: "Tout est affiché") : String(localized: "Masqué : ") + off.joined(separator: ", ")
    }

    private var footer: some View {
        VStack(spacing: SharpitSpacing.xxs) {
            Text("SharpIt")
                .font(SharpitTypography.eyebrow)
                .tracking(SharpitTypography.eyebrowTracking * 2)
                .foregroundStyle(SharpitColor.slate)
            Text("Version \(AppVersion.display)")
                .font(SharpitTypography.meta)
                .foregroundStyle(SharpitColor.slate.opacity(0.7))
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
        case .coachMemory:
            CoachMemoryView(client: CoachMemoryClient(), tokenProvider: tokenProvider)
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
        case .language:
            LanguageSettingsView(client: profileClient, tokenProvider: tokenProvider)
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
    case coachMemory
    case pro
    case sources
    case equipment
    case thresholds
    case privacy
    case notifications
    case density
    case language
    case features
    case ownFoods
    case feedback
}

/// How Paramètres words what a row holds before it is opened.
nonisolated enum SettingsReadout {
    /// « 34 ans · 181 cm », with whatever of the two the profile holds.
    static func profile(birthDate: Date?, heightCm: Int?, now: Date = .now, calendar: Calendar = .current) -> String? {
        let age = birthDate.flatMap { calendar.dateComponents([.year], from: $0, to: now).year }
        let parts = [age.map { String(localized: "\($0) ans") }, heightCm.map { "\($0) cm" }].compactMap(\.self)
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }
}

/// « Utilisation du coach »: the share of the rolling day's budget spent, over a thin bar in the
/// coach's hue. It opens the usage sheet.
private struct CoachUsageLine: View {
    let quota: V1CoachQuota

    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: SharpitSpacing.sm) {
                SharpitSettingsGlyph(symbol: "chart.bar")
                Text("Utilisation du coach")
                    .foregroundStyle(SharpitColor.foreground)
                Spacer(minLength: SharpitSpacing.xs)
                Text("\(CoachQuotaReadout.usedPercent(quota)) sur 24 h")
                    .monospacedDigit()
                    .foregroundStyle(SharpitColor.slate)
            }
            .font(SharpitTypography.body)
            SharpitBarTrack(fraction: quota.usedRatio, tone: SharpitColor.pillarCoach)
                .frame(height: 4)
                .accessibilityHidden(true)
        }
        .padding(.vertical, 6)
        .contentShape(.rect)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
        .accessibilityHint("Ouvre la consommation")
    }
}
