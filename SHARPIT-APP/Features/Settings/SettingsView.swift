import ClerkKit
import SwiftData
import SwiftUI
import UIKit
import UserNotifications

/// Paramètres, opened as a sheet from the avatar in Résumé and Corps.
///
/// A page of cards rather than a grouped list: who the athlete is and their tier first, then
/// the two settings answered in place — appearance and notifications — and only then the pages
/// worth opening, each row saying its state before it is opened. The reading density is one of
/// those pages: the choice needs its explanation. What used to live in Moi and belongs elsewhere moved: the body to Corps, goals to
/// Plan, the coach's memory to Coach.
struct SettingsView: View {
    let appleHealth: AppleHealthSource
    let syncClient: any SyncServing
    let profileClient: any AthleteProfileServing & BodyCompositionServing
    let displayMode: DisplayModeStore
    let tokenProvider: () async throws -> String
    let modelContext: ModelContext?
    let privacyClient: any PrivacyConsentServing
    let cloudSync: CloudSyncMonitor

    @Environment(\.dismiss) private var dismiss
    @AppStorage(AppearancePreference.storageKey) private var appearance: AppearancePreference = .system
    @State private var profile: AthleteProfileStore
    @State private var push = PushNotificationManager.shared
    @State private var notificationStatus: UNAuthorizationStatus?
    @Environment(ProStore.self) private var pro: ProStore?

    init(
        appleHealth: AppleHealthSource,
        syncClient: any SyncServing,
        profileClient: any AthleteProfileServing & BodyCompositionServing,
        displayMode: DisplayModeStore,
        tokenProvider: @escaping () async throws -> String,
        modelContext: ModelContext?,
        privacyClient: any PrivacyConsentServing = PrivacyConsentClient(),
        cloudSync: CloudSyncMonitor = .shared
    ) {
        self.appleHealth = appleHealth
        self.syncClient = syncClient
        self.profileClient = profileClient
        self.displayMode = displayMode
        self.tokenProvider = tokenProvider
        self.modelContext = modelContext
        self.privacyClient = privacyClient
        self.cloudSync = cloudSync
        _profile = State(initialValue: AthleteProfileStore(
            client: profileClient,
            tokenProvider: tokenProvider,
            modelContext: modelContext
        ))
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: SharpitSpacing.section) {
                    NavigationLink(value: SettingsRoute.account) {
                        AccountCard(isPro: isPro)
                    }
                    .buttonStyle(.sharpitPressable)

                    NavigationLink(value: SettingsRoute.pro) {
                        ProCard(isPro: isPro)
                    }
                    .buttonStyle(.sharpitPressable)

                    SettingsGroup(title: "Réglages rapides") {
                        appearanceControl
                    }

                    // A page, not a quick setting: the switch and the kinds it sends are one
                    // decision, and iOS may have the last word on it.
                    SettingsGroup(title: "Notifications") {
                        NavigationLink(value: SettingsRoute.notifications) {
                            SettingsRow(symbol: "bell.badge.fill", tint: SettingsTone.notifications, title: "Notifications", detail: notificationsDetail)
                        }
                    }
                    .buttonStyle(.plain)

                    SettingsGroup(title: "Données") {
                        NavigationLink(value: SettingsRoute.sources) {
                            SettingsRow(symbol: "link", tint: SettingsTone.sources, title: "Sources de données", detail: sourcesDetail)
                        }
                        SettingsDivider()
                        NavigationLink(value: SettingsRoute.iCloud) {
                            SettingsRow(symbol: "icloud.fill", tint: SettingsTone.iCloud, title: "Synchronisation iCloud", detail: iCloudDetail)
                        }
                    }
                    .buttonStyle(.plain)

                    SettingsGroup(title: "Entraînement") {
                        NavigationLink(value: SettingsRoute.equipment) {
                            SettingsRow(symbol: "figure.run.square.stack", tint: SettingsTone.gear, title: "Sports & équipement", detail: sportsDetail)
                        }
                        SettingsDivider()
                        NavigationLink(value: SettingsRoute.density) {
                            SettingsRow(
                                symbol: "eye.fill",
                                tint: SettingsTone.density,
                                title: "Densité de lecture",
                                detail: displayMode.isExpert ? "Expert" : "Essentiel"
                            )
                        }
                    }
                    .buttonStyle(.plain)

                    SettingsGroup(title: "Confidentialité") {
                        NavigationLink(value: SettingsRoute.privacy) {
                            SettingsRow(symbol: "hand.raised.fill", tint: SettingsTone.privacy, title: "Confidentialité & conditions", detail: "Consentements, CGU, politique")
                        }
                    }
                    .buttonStyle(.plain)

                    footer
                }
                .padding(.horizontal, SharpitSpacing.pageInset)
                .padding(.top, SharpitSpacing.xs)
                .padding(.bottom, SharpitSpacing.xl)
            }
            .scrollIndicators(.hidden)
            .background(SharpitCanvasBackground())
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
            .task { await cloudSync.refreshAccountStatus() }
        }
        .sharpitSheet()
    }

    /// The web's word on the tier once `/api/v1/pro` answered, else the profile's.
    private var isPro: Bool {
        pro?.pro?.isPro ?? profile.profile.isPro
    }

    // MARK: - Quick settings

    private var appearanceControl: some View {
        VStack(alignment: .leading, spacing: SharpitSpacing.sm) {
            SettingsRow(symbol: "circle.lefthalf.filled", tint: SettingsTone.appearance, title: "Apparence", detail: "Propre à cet iPhone", showsChevron: false)
            SharpitSegmentedControl(
                selection: $appearance,
                options: AppearancePreference.allCases.map {
                    SharpitSegmentedControl<AppearancePreference>.Option(value: $0, label: $0.label, symbol: $0.symbol)
                }
            )
        }
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
            prefs.syncAlerts ? "alertes" : nil,
        ].compactMap { $0 }
        return on.isEmpty ? "Aucune" : on.joined(separator: ", ").capitalizedFirstLetter
    }

    private var sourcesDetail: String {
        appleHealth.isEnabled ? "Garmin · Apple Santé" : "Garmin"
    }

    private var iCloudDetail: String {
        if let error = cloudSync.lastError, !error.isEmpty { return "Erreur de synchronisation" }
        guard let last = [cloudSync.events[.exporting], cloudSync.events[.importing]]
            .compactMap({ $0?.endedAt }).max() else {
            return ConnectionsReadout.iCloud(cloudSync.accountStatus)
        }
        let when = Date.RelativeFormatStyle(presentation: .named, locale: SharpitLocale.french).format(last)
        return "À jour · \(when)"
    }

    private var sportsDetail: String {
        let sports = PracticedSportCatalog.ordered(profile.profile.practicedSports?.sports ?? [])
        let labels = sports.compactMap { id in PracticedSportCatalog.all.first { $0.id == id }?.label }
        return labels.isEmpty ? "Tes disciplines et ton matériel" : labels.joined(separator: " · ")
    }

    private var footer: some View {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "—"
        let build = info?["CFBundleVersion"] as? String ?? "—"
        return VStack(spacing: SharpitSpacing.xxs) {
            Text("SHARPIT")
                .font(SharpitTypography.eyebrow)
                .tracking(SharpitTypography.eyebrowTracking * 2)
                .foregroundStyle(SharpitColor.mutedForeground)
            Text("Version \(version) (\(build))")
                .font(SharpitTypography.meta)
                .foregroundStyle(SharpitColor.mutedForeground.opacity(0.7))
        }
        .frame(maxWidth: .infinity)
        .padding(.top, SharpitSpacing.sm)
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
            ConnectionsView(appleHealth: appleHealth, syncClient: syncClient, tokenProvider: tokenProvider)
        case .iCloud:
            ICloudSyncView(monitor: cloudSync)
        case .equipment:
            EquipmentView(client: profileClient, tokenProvider: tokenProvider, modelContext: modelContext)
        case .privacy:
            PrivacySettingsView(client: privacyClient, tokenProvider: tokenProvider)
        case .notifications:
            NotificationPrefsView(profileClient: profileClient, tokenProvider: tokenProvider)
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
    case iCloud
    case equipment
    case privacy
    case notifications
    case density
}

private extension String {
    var capitalizedFirstLetter: String { prefix(1).uppercased() + dropFirst() }
}

// MARK: - Building blocks

/// The athlete, as the page opens: face, name, e-mail, tier.
private struct AccountCard: View {
    let isPro: Bool

    @Environment(Clerk.self) private var clerk
    @ScaledMetric(relativeTo: .title2) private var avatarSize: CGFloat = 60

    var body: some View {
        HStack(spacing: SharpitSpacing.md) {
            AccountAvatar(size: avatarSize)
            VStack(alignment: .leading, spacing: SharpitSpacing.xxs) {
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
                Text(isPro ? "PRO" : "GRATUIT")
                    .font(SharpitTypography.label)
                    .tracking(SharpitTypography.labelTracking)
                    .foregroundStyle(isPro ? SharpitColor.highlightForeground : SharpitColor.mutedForeground)
                    .padding(.horizontal, SharpitSpacing.xs)
                    .padding(.vertical, 3)
                    .background(isPro ? SharpitColor.highlight : SharpitColor.analysisGrid.opacity(0.6), in: Capsule())
                    .padding(.top, 2)
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.tertiary)
                .accessibilityHidden(true)
        }
        .padding(SharpitSpacing.cardPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .sharpitSurface(.panel)
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

/// SharpIt Pro on the ink surface — the one dark plate of the page, as the verdict is on Résumé.
private struct ProCard: View {
    let isPro: Bool

    var body: some View {
        HStack(alignment: .center, spacing: SharpitSpacing.md) {
            VStack(alignment: .leading, spacing: SharpitSpacing.xxs) {
                SharpitEyebrow(isPro ? "Ton abonnement" : "Abonnement", systemImage: "sparkle")
                Text("SharpIt Pro")
                    .font(SharpitTypography.verdict)
                    .tracking(SharpitTypography.verdictTracking)
                    .foregroundStyle(SharpitColor.inkSurfaceForeground)
                Text(isPro ? "Tout SharpIt est ouvert pour toi." : "Bilan hebdomadaire, analyse de séance, lecture coach du journal.")
                    .font(SharpitTypography.meta)
                    .foregroundStyle(SharpitColor.inkSurfaceForeground.opacity(0.7))
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
            Text(isPro ? "Gérer" : "Découvrir")
                .font(SharpitTypography.meta.weight(.semibold))
                .foregroundStyle(SharpitColor.highlightForeground)
                .padding(.horizontal, SharpitSpacing.sm)
                .padding(.vertical, SharpitSpacing.xs)
                .background(SharpitColor.highlight, in: Capsule())
        }
        .padding(SharpitSpacing.cardPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .sharpitSurface(.ink)
        .accessibilityElement(children: .combine)
    }
}

/// A titled card of rows.
private struct SettingsGroup<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: SharpitSpacing.xs) {
            SharpitEyebrow(title)
                .padding(.leading, SharpitSpacing.xxs)
            VStack(alignment: .leading, spacing: SharpitSpacing.sm) {
                content
            }
            .padding(SharpitSpacing.cardPadding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .sharpitSurface(.panel)
        }
    }
}

private struct SettingsDivider: View {
    var body: some View {
        Rectangle()
            .fill(SharpitColor.analysisGrid.opacity(0.7))
            .frame(height: 1)
            .padding(.leading, 44)
    }
}

/// One row: a tinted symbol in a soft well, its name, and what it holds right now.
private struct SettingsRow: View {
    let symbol: String
    let tint: Color
    let title: String
    var detail: String?
    var showsChevron = true

    var body: some View {
        HStack(spacing: SharpitSpacing.sm) {
            Image(systemName: symbol)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 32, height: 32)
                .background(tint.opacity(0.14), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(SharpitTypography.bodyEmphasis)
                    .foregroundStyle(SharpitColor.foreground)
                if let detail {
                    Text(detail)
                        .font(SharpitTypography.meta)
                        .foregroundStyle(SharpitColor.mutedForeground)
                        .lineLimit(1)
                        .contentTransition(.opacity)
                }
            }
            Spacer(minLength: 0)
            if showsChevron {
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.tertiary)
                    .accessibilityHidden(true)
            }
        }
        .contentShape(.rect)
    }
}

private enum SettingsTone {
    static let appearance = Color(red: 0.34, green: 0.44, blue: 0.86)
    static let notifications = Color(red: 0.90, green: 0.36, blue: 0.40)
    static let sources = Color(red: 0.12, green: 0.62, blue: 0.56)
    static let iCloud = Color(red: 0.20, green: 0.50, blue: 0.95)
    static let gear = SharpitColor.primary
    static let density = Color(red: 0.55, green: 0.36, blue: 0.86)
    static let privacy = Color(red: 0.44, green: 0.50, blue: 0.58)
}
