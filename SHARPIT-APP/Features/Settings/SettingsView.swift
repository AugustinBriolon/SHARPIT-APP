import ClerkKit
import SwiftData
import SwiftUI

/// Paramètres, opened as a sheet from the avatar in Résumé and Corps.
///
/// Built like the system's Settings: the account first, then short groups — the subscription,
/// the general settings, training preferences, privacy. What used to live in Moi and belongs
/// elsewhere moved: the body to the Corps tab, goals to Plan, the coach's memory to Coach.
struct SettingsView: View {
    let appleHealth: AppleHealthSource
    let syncClient: any SyncServing
    let profileClient: any AthleteProfileServing & BodyCompositionServing
    let displayMode: DisplayModeStore
    let tokenProvider: () async throws -> String
    let modelContext: ModelContext?
    var privacyClient: any PrivacyConsentServing = PrivacyConsentClient()
    var cloudSync: CloudSyncMonitor = .shared

    @Environment(\.dismiss) private var dismiss
    @AppStorage(AppearancePreference.storageKey) private var appearance: AppearancePreference = .system

    var body: some View {
        NavigationStack {
            List {
                Section {
                    NavigationLink {
                        AccountView(profileClient: profileClient, tokenProvider: tokenProvider, modelContext: modelContext)
                    } label: {
                        AccountSummaryRow()
                    }
                }
                .sharpitListRows()

                Section {
                    NavigationLink {
                        ProView(profileClient: profileClient, tokenProvider: tokenProvider)
                    } label: {
                        rowLabel("SharpIt Pro", symbol: "sparkle", background: SettingsTone.pro)
                    }
                }
                .sharpitListRows()

                Section(eyebrow: "Général") { generalRows }.sharpitListRows()
                Section(eyebrow: "Entraînement") { trainingRows }.sharpitListRows()
                Section(eyebrow: "Confidentialité", footer: versionLine) {
                    NavigationLink {
                        PrivacySettingsView(client: privacyClient, tokenProvider: tokenProvider)
                    } label: {
                        rowLabel("Confidentialité & conditions", symbol: "hand.raised.fill", background: SettingsTone.privacy)
                    }
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
        }
        .sharpitSheet()
    }

    @ViewBuilder
    private var generalRows: some View {
        NavigationLink {
            AppearanceView()
        } label: {
            LabeledContent {
                Text(appearance.label)
                    .font(SharpitTypography.body)
                    .foregroundStyle(SharpitColor.mutedForeground)
            } label: {
                rowLabel("Apparence", symbol: "circle.lefthalf.filled", background: SettingsTone.appearance)
            }
        }
        NavigationLink {
            NotificationsView()
        } label: {
            rowLabel("Notifications", symbol: "bell.badge.fill", background: SettingsTone.notifications)
        }
        NavigationLink {
            ConnectionsView(appleHealth: appleHealth, syncClient: syncClient, tokenProvider: tokenProvider)
        } label: {
            rowLabel("Sources de données", symbol: "link", background: SettingsTone.sources)
        }
        NavigationLink {
            ICloudSyncView(monitor: cloudSync)
        } label: {
            rowLabel("Synchronisation iCloud", symbol: "icloud.fill", background: SettingsTone.iCloud)
        }
    }

    @ViewBuilder
    private var trainingRows: some View {
        NavigationLink {
            EquipmentView(client: profileClient, tokenProvider: tokenProvider, modelContext: modelContext)
        } label: {
            rowLabel("Sports & équipement", symbol: "figure.run.square.stack", background: SettingsTone.gear)
        }
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
                rowLabel("Densité de lecture", symbol: "eye.fill", background: SettingsTone.density)
            }
        }
    }

    private var versionLine: String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "—"
        let build = info?["CFBundleVersion"] as? String ?? "—"
        return "SharpIt \(version) (\(build))"
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

/// The account row at the top, as Settings opens on the Apple Account: avatar, name, e-mail.
private struct AccountSummaryRow: View {
    @Environment(Clerk.self) private var clerk
    @ScaledMetric(relativeTo: .title2) private var avatarSize: CGFloat = 56

    var body: some View {
        HStack(spacing: SharpitSpacing.md) {
            AccountAvatar(size: avatarSize)
            VStack(alignment: .leading, spacing: 2) {
                Text(name)
                    .font(SharpitTypography.sectionTitle)
                    .foregroundStyle(SharpitColor.foreground)
                if let email = clerk.user?.primaryEmailAddress?.emailAddress {
                    Text(email)
                        .font(SharpitTypography.meta)
                        .foregroundStyle(SharpitColor.mutedForeground)
                        .lineLimit(1)
                }
            }
        }
        .padding(.vertical, SharpitSpacing.xxs)
    }

    private var name: String {
        let parts = [clerk.user?.firstName, clerk.user?.lastName]
            .compactMap { $0?.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        return parts.isEmpty ? "Ton compte" : parts.joined(separator: " ")
    }
}

private enum SettingsTone {
    static let pro = SharpitColor.primary
    static let appearance = Color(red: 0.34, green: 0.44, blue: 0.86)
    static let notifications = Color(red: 0.94, green: 0.38, blue: 0.42)
    static let sources = Color(red: 0.12, green: 0.68, blue: 0.62)
    static let iCloud = Color(red: 0.20, green: 0.50, blue: 0.95)
    static let gear = SharpitColor.primary
    static let density = Color(red: 0.58, green: 0.36, blue: 0.88)
    static let privacy = Color(red: 0.44, green: 0.50, blue: 0.58)
}
