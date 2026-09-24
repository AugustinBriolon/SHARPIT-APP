import CloudKit
import ClerkKit
import SwiftData
import SwiftUI
import UIKit
import UserNotifications

// MARK: - Apparence

/// The colour scheme, chosen per iPhone: it is how this screen should look, not a fact about the
/// athlete, so it stays on the device and never reaches the server.
nonisolated enum AppearancePreference: String, CaseIterable, Identifiable, Sendable {
    case system
    case light
    case dark

    static let storageKey = "sharpit.appearance"

    var id: String { rawValue }

    var label: String {
        switch self {
        case .system: "Système"
        case .light: "Clair"
        case .dark: "Sombre"
        }
    }

    var symbol: String {
        switch self {
        case .system: "circle.lefthalf.filled"
        case .light: "sun.max"
        case .dark: "moon"
        }
    }

    /// Nil follows the system.
    var colorScheme: ColorScheme? {
        switch self {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }
}

struct AppearanceView: View {
    @AppStorage(AppearancePreference.storageKey) private var appearance: AppearancePreference = .system

    var body: some View {
        List {
            Section(
                eyebrow: "Apparence",
                footer: "Propre à cet iPhone. « Système » suit le réglage clair ou sombre d'iOS."
            ) {
                ForEach(AppearancePreference.allCases) { option in
                    Button {
                        SharpitHaptics.play(.light)
                        SharpitMotion.run(SharpitMotion.selection) { appearance = option }
                    } label: {
                        HStack {
                            Label {
                                Text(option.label)
                                    .font(SharpitTypography.bodyEmphasis)
                                    .foregroundStyle(SharpitColor.foreground)
                            } icon: {
                                SharpitRowIcon(symbol: option.symbol)
                            }
                            Spacer(minLength: 0)
                            if appearance == option {
                                Image(systemName: "checkmark")
                                    .font(.body.weight(.semibold))
                                    .foregroundStyle(SharpitColor.primary)
                                    .transition(.scale.combined(with: .opacity))
                            }
                        }
                        .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(appearance == option ? .isSelected : [])
                }
            }
            .sharpitListRows()
        }
        .sharpitGroupedList()
        .navigationTitle("Apparence")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Notifications

/// What SharpIt may send, and whether iOS lets it.
///
/// The per-kind switches (morning verdict time, weekly review, reminders) wait on the web's
/// `notificationPrefs` (see the Corps / Paramètres spec); until then this page says what is sent
/// and hands the permission to iOS, which owns it.
struct NotificationsView: View {
    @State private var status: UNAuthorizationStatus?
    @Environment(\.openURL) private var openURL

    var body: some View {
        List {
            Section(eyebrow: "Autorisation") {
                LabeledContent {
                    Text(statusLabel)
                        .foregroundStyle(statusTone)
                } label: {
                    Label {
                        Text("Notifications")
                    } icon: {
                        SharpitRowIcon(symbol: "bell.badge")
                    }
                }
                switch status {
                case .notDetermined:
                    Button("Autoriser les notifications") {
                        Task {
                            _ = await PushNotificationManager.shared.requestAuthorization()
                            await refresh()
                        }
                    }
                case .denied:
                    Button("Ouvrir les réglages d'iOS") {
                        if let url = URL(string: UIApplication.openNotificationSettingsURLString) {
                            openURL(url)
                        }
                    }
                default:
                    EmptyView()
                }
            }
            .sharpitListRows()

            Section(
                eyebrow: "Ce que SharpIt t'envoie",
                footer: "Le choix de chaque notification et de l'heure du verdict arrive avec la prochaine version."
            ) {
                Label {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Verdict du matin")
                            .font(SharpitTypography.bodyEmphasis)
                        Text("Ta lecture du jour, une fois ta nuit synchronisée.")
                            .font(SharpitTypography.meta)
                            .foregroundStyle(SharpitColor.mutedForeground)
                    }
                } icon: {
                    SharpitRowIcon(symbol: "sun.horizon")
                }
            }
            .sharpitListRows()
        }
        .sharpitGroupedList()
        .navigationTitle("Notifications")
        .navigationBarTitleDisplayMode(.inline)
        .task { await refresh() }
    }

    private func refresh() async {
        status = await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
    }

    private var statusLabel: String {
        switch status {
        case .authorized, .provisional, .ephemeral: "Activées"
        case .denied: "Refusées"
        case .notDetermined: "Pas encore demandées"
        default: "—"
        }
    }

    private var statusTone: Color {
        status == .denied ? SharpitColor.signalCaution : SharpitColor.mutedForeground
    }
}

// MARK: - Synchronisation iCloud

/// Whether the iCloud copy of the cache works, and when it last moved (`docs/adr/0007`).
struct ICloudSyncView: View {
    let monitor: CloudSyncMonitor

    var body: some View {
        List {
            Section(eyebrow: "Compte iCloud") {
                LabeledContent {
                    Text(ConnectionsReadout.iCloud(monitor.accountStatus))
                        .foregroundStyle(monitor.accountStatus == .available ? SharpitColor.signalRecovery : SharpitColor.mutedForeground)
                } label: {
                    Label {
                        Text("Statut")
                    } icon: {
                        SharpitRowIcon(symbol: "icloud")
                    }
                }
            }
            .sharpitListRows()

            Section(
                eyebrow: "Activité",
                footer: "iCloud garde une copie de ce que l'app a déjà lu, pour l'afficher hors ligne et sur tes autres appareils. Jamais tes réponses de journal ni tes réglages, qui restent sur le serveur."
            ) {
                ForEach([CloudSyncMonitor.Kind.exporting, .importing, .setup], id: \.self) { kind in
                    LabeledContent(kind.label) {
                        Text(eventLabel(monitor.events[kind]))
                            .foregroundStyle(monitor.events[kind]?.succeeded == false ? SharpitColor.signalCaution : SharpitColor.mutedForeground)
                    }
                }
                if let error = monitor.lastError {
                    Label(error, systemImage: "exclamationmark.triangle")
                        .font(SharpitTypography.meta)
                        .foregroundStyle(SharpitColor.signalCaution)
                }
            }
            .sharpitListRows()
        }
        .sharpitGroupedList()
        .navigationTitle("Synchronisation iCloud")
        .navigationBarTitleDisplayMode(.inline)
        .task { await monitor.refreshAccountStatus() }
        .refreshable { await monitor.refreshAccountStatus() }
    }

    private func eventLabel(_ event: CloudSyncMonitor.Event?) -> String {
        guard let event else { return "Jamais" }
        let when = Date.RelativeFormatStyle(presentation: .named, locale: SharpitLocale.french)
            .format(event.endedAt)
        return event.succeeded ? when.capitalizedFirst : "Échec · \(when)"
    }
}

// MARK: - Compte

/// Who the athlete is: the identity Clerk holds (name, e-mail, photo — edited in Clerk's own
/// profile) and the body facts the profile holds (height, birth date, age).
struct AccountView: View {
    let profileClient: any AthleteProfileServing
    let tokenProvider: () async throws -> String
    let modelContext: ModelContext?

    @Environment(Clerk.self) private var clerk
    @State private var store: AthleteProfileStore
    @State private var isEditingIdentity = false

    init(
        profileClient: any AthleteProfileServing,
        tokenProvider: @escaping () async throws -> String,
        modelContext: ModelContext?
    ) {
        self.profileClient = profileClient
        self.tokenProvider = tokenProvider
        self.modelContext = modelContext
        _store = State(initialValue: AthleteProfileStore(
            client: profileClient,
            tokenProvider: tokenProvider,
            modelContext: modelContext
        ))
    }

    var body: some View {
        List {
            Section {
                HStack {
                    Spacer()
                    AccountAvatar(size: 88)
                    Spacer()
                }
                .listRowBackground(Color.clear)
            }

            Section(eyebrow: "Identité") {
                LabeledContent("Prénom", value: clerk.user?.firstName ?? "—")
                LabeledContent("Nom", value: clerk.user?.lastName ?? "—")
                LabeledContent("E-mail", value: clerk.user?.primaryEmailAddress?.emailAddress ?? "—")
                Button("Modifier le nom, la photo ou l'e-mail") { isEditingIdentity = true }
            }
            .sharpitListRows()

            Section(
                eyebrow: "Profil",
                footer: "Le sexe arrive avec la prochaine version du serveur : l'âge biologique et les normes de fréquence cardiaque en auront besoin."
            ) {
                LabeledContent("Taille", value: store.profile.heightCm.map { "\($0) cm" } ?? "—")
                LabeledContent("Date de naissance", value: store.profile.birthDate.map {
                    $0.formatted(.dateTime.day().month(.wide).year().locale(SharpitLocale.french))
                } ?? "—")
                LabeledContent("Âge", value: AccountAge.years(birthDate: store.profile.birthDate).map { "\($0) ans" } ?? "—")
                NavigationLink("Modifier le profil") {
                    ProfileView(client: profileClient, tokenProvider: tokenProvider, modelContext: modelContext)
                }
            }
            .sharpitListRows()
        }
        .sharpitGroupedList()
        .navigationTitle("Compte")
        .navigationBarTitleDisplayMode(.inline)
        .task { await store.load() }
        .sheet(isPresented: $isEditingIdentity) { SharpitUserProfileSheet() }
    }
}

nonisolated enum AccountAge {
    /// Whole years since the birth date, as the web's profile shows them.
    static func years(birthDate: Date?, now: Date = Date(), calendar: Calendar = .current) -> Int? {
        guard let birthDate, birthDate < now else { return nil }
        return calendar.dateComponents([.year], from: birthDate, to: now).year
    }
}

// MARK: - SharpIt Pro

/// The athlete's tier today. Buying and managing the subscription arrive with StoreKit once the
/// web can verify a purchase (`/api/v1/billing/apple/*`); until then the perks are the web's page,
/// which owns their wording.
struct ProView: View {
    let profileClient: any AthleteProfileServing
    let tokenProvider: () async throws -> String

    @State private var tier: String?

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: SharpitSpacing.xs) {
                    SharpitEyebrow("Ton palier", systemImage: "sparkle")
                    Text(tier == "PRO" ? "SharpIt Pro" : "Gratuit")
                        .font(SharpitTypography.pageTitle)
                        .tracking(SharpitTypography.pageTitleTracking)
                        .foregroundStyle(SharpitColor.foreground)
                        .contentTransition(.opacity)
                    Text(tier == "PRO"
                         ? "Tout ce que SharpIt fait est ouvert pour toi."
                         : "SharpIt Pro étend le coach et les analyses. L'abonnement arrive bientôt dans l'app.")
                        .font(SharpitTypography.body)
                        .foregroundStyle(SharpitColor.mutedForeground)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.vertical, SharpitSpacing.xs)
                .redacted(reason: tier == nil ? .placeholder : [])
            }
            .sharpitListRows()

            Section(eyebrow: "Avantages") {
                SharpitExternalLinkRow(
                    title: "Gratuit et Pro, en détail",
                    symbol: "list.bullet.rectangle",
                    destination: APIConfiguration.baseURL.appending(path: "/settings/pro")
                )
            }
            .sharpitListRows()
        }
        .sharpitGroupedList()
        .navigationTitle("SharpIt Pro")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            guard let token = try? await tokenProvider() else { return }
            tier = (try? await profileClient.athleteProfile(token: token))?.tier ?? "FREE"
        }
    }
}

private extension String {
    var capitalizedFirst: String { prefix(1).uppercased() + dropFirst() }
}
