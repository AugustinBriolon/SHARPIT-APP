import SwiftUI

/// The athlete's own space: the account, and where their data comes from.
///
/// Garmin is connected on the web, where its sign-in lives; Apple Health is switched on
/// here, because only the phone can read it. Both can feed SHARPIT at once.
struct MeView<Account: View>: View {
    let appleHealth: AppleHealthSource
    let syncClient: any SyncServing
    let tokenProvider: () async throws -> String
    @ViewBuilder let account: Account

    @Environment(\.openURL) private var openURL
    @State private var status: V1SyncStatus?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: SharpitSpacing.section) {
                    account
                    VStack(alignment: .leading, spacing: SharpitSpacing.sm) {
                        SharpitEyebrow("Sources de données")
                        garminRow
                        appleHealthRow
                    }
                    NavigationLink {
                        HealthCoverageView(reader: HealthKitReader())
                    } label: {
                        SourceRow(
                            symbol: "stethoscope",
                            tone: SharpitColor.primary,
                            title: "Diagnostic Apple Santé",
                            detail: "Ce qu'Apple Santé contient, signal par signal"
                        ) {
                            Image(systemName: "chevron.right")
                                .font(SharpitTypography.label)
                                .foregroundStyle(SharpitColor.mutedForeground)
                        }
                    }
                    .buttonStyle(.sharpitPressable)
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

    private var garmin: V1SyncProvider? {
        status?.providers.first { $0.key == "garmin" }
    }

    private var garminRow: some View {
        Button {
            openURL(APIConfiguration.baseURL.appending(path: "/settings/integrations"))
        } label: {
            SourceRow(
                symbol: "applewatch.radiowaves.left.and.right",
                tone: garmin == nil ? SharpitColor.mutedForeground : SharpitColor.signalRecovery,
                title: "Garmin",
                detail: garminDetail
            ) {
                Image(systemName: "arrow.up.right")
                    .font(SharpitTypography.label)
                    .foregroundStyle(SharpitColor.mutedForeground)
            }
        }
        .buttonStyle(.sharpitPressable)
        .accessibilityHint("Ouvre les intégrations sur le web")
    }

    private var garminDetail: String {
        guard status != nil else { return "Lecture du statut…" }
        guard let garmin else { return "Non connecté — se connecte sur le web" }
        guard let last = garmin.lastSyncAt else { return "Connecté" }
        return "Connecté · synchronisé " + SyncReadout.age(of: last, now: .now)
    }

    private var appleHealthRow: some View {
        SourceRow(
            symbol: "heart.text.square.fill",
            tone: appleHealth.isEnabled ? SharpitColor.signalRisk : SharpitColor.mutedForeground,
            title: "Apple Santé",
            detail: appleHealthDetail
        ) {
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

private struct SourceRow<Accessory: View>: View {
    let symbol: String
    let tone: Color
    let title: String
    let detail: String
    @ViewBuilder let accessory: Accessory

    var body: some View {
        HStack(spacing: SharpitSpacing.sm) {
            Image(systemName: symbol)
                .font(SharpitTypography.bodyEmphasis)
                .foregroundStyle(tone)
                .frame(width: 36, height: 36)
                .background(tone.opacity(0.12), in: Circle())
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(SharpitTypography.bodyEmphasis)
                    .foregroundStyle(SharpitColor.foreground)
                Text(detail)
                    .font(SharpitTypography.meta)
                    .foregroundStyle(SharpitColor.mutedForeground)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: SharpitSpacing.xs)
            accessory
        }
        .padding(SharpitSpacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .sharpitSurface(.panel)
        .accessibilityElement(children: .combine)
    }
}
