import CloudKit
import ClerkKit
import SwiftData
import SwiftUI

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
