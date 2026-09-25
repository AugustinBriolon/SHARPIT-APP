import AuthenticationServices
import ClerkKit
import SwiftUI

/// Paramètres → Sources de données: every source SHARPIT reads from — Garmin and Apple Health.
///
/// Garmin is connected on the web, where its sign-in lives; Apple Health is switched on here,
/// because only the phone can read it. The iCloud copy of the cache has its own page,
/// Synchronisation iCloud (`docs/adr/0007`).
///
/// Each source is one two-line row — its own mark, its name, one short status — so the rows
/// keep the same height whatever the status says. Recency surfaces on the toast shown while a
/// check is under way, not on a row read at rest (`docs/adr/0008`).
struct ConnectionsView: View {
    let appleHealth: AppleHealthSource
    let syncClient: any SyncServing
    let tokenProvider: () async throws -> String
    var garminClient: any GarminHandoffServing = SharpitClient()

    @Environment(SharpitToastCenter.self) private var toastCenter
    @Environment(Clerk.self) private var clerk
    /// Owned by `RootView`, which shows its progress and result as toasts wherever the athlete is.
    @Environment(GarminHistoryImport.self) private var historyImport: GarminHistoryImport?
    @State private var status: V1SyncStatus?
    @State private var appleHealthToastToken: UUID?
    @Environment(\.webAuthenticationSession) private var webAuthenticationSession
    @State private var isConnectingGarmin = false

    var body: some View {
        List {
            Section(eyebrow: "Sources") {
                garminRow
                appleHealthRow
            }
            .sharpitListRows()

            if isGarminConnected, historyImport != nil {
                Section(
                    eyebrow: "Garmin",
                    footer: "Toutes tes activités Garmin, depuis la première. Celles déjà présentes ne sont pas dupliquées ; l'import peut prendre quelques minutes."
                ) {
                    historyRow
                }
                .sharpitListRows()
            }
        }
        .sharpitGroupedList()
        .navigationTitle("Sources de données")
        .navigationBarTitleDisplayMode(.inline)
        .task { await loadStatus() }
        .refreshable { await loadStatus() }
        .onChange(of: appleHealth.state) { _, state in
            switch state {
            case .sending:
                appleHealthToastToken = toastCenter.show(
                    "Envoi vers Apple Santé…",
                    symbol: "heart.text.square",
                    autoDismissAfter: nil
                )
            case .failed(let message):
                appleHealthToastToken = toastCenter.show(
                    message,
                    symbol: "exclamationmark.triangle",
                    tone: .error,
                    autoDismissAfter: 4
                )
            case .idle:
                if let appleHealthToastToken { toastCenter.dismiss(appleHealthToastToken) }
                appleHealthToastToken = nil
            }
        }
    }

    private var garminRow: some View {
        let badge = ConnectionsReadout.garmin(status: status)
        return Button {
            SharpitHaptics.play(.light)
            Task { await connectGarmin() }
        } label: {
            HStack(spacing: SharpitSpacing.sm) {
                ProviderLogo(provider: .garmin)
                sourceTitle("Garmin", status: badge.text, tone: badge.tone.color)
                Spacer(minLength: SharpitSpacing.xs)
                if isGarminConnected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(SharpitColor.primary)
                } else {
                    Image(systemName: "chevron.right")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.tertiary)
                        .accessibilityHidden(true)
                }
            }
            .contentShape(.rect)
        }
        .foregroundStyle(SharpitColor.foreground)
        .accessibilityHint("Connecter Garmin directement dans l'application")
    }

    private var isGarminConnected: Bool {
        status?.providers.contains(where: { $0.key == "garmin" }) ?? false
    }

    private var historyRow: some View {
        let isImporting = historyImport?.state == .importing
        return Button {
            Task { await historyImport?.importAll(userId: clerk.user?.id, tokenProvider: tokenProvider) }
        } label: {
            HStack(spacing: SharpitSpacing.sm) {
                Image(systemName: "clock.arrow.circlepath")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(SharpitColor.primary)
                    .frame(width: 28)
                sourceTitle(
                    "Importer tout l'historique",
                    status: ConnectionsReadout.garminHistory(historyImport?.state ?? .idle),
                    tone: historyImport?.state == .failed ? SharpitColor.signalRisk : SharpitColor.mutedForeground
                )
                Spacer(minLength: SharpitSpacing.xs)
                if isImporting {
                    ProgressView()
                }
            }
            .contentShape(.rect)
        }
        .foregroundStyle(SharpitColor.foreground)
        .disabled(isImporting)
    }

    /// No "Activé" beside the switch: the switch already says it. The second line says what
    /// the source is for, and turns into the reason only when the switch alone would mislead.
    private var appleHealthRow: some View {
        let line = ConnectionsReadout.appleHealthSubtitle(
            isAvailable: appleHealth.isAvailable,
            state: appleHealth.state
        )
        return Toggle(isOn: appleHealthBinding) {
            HStack(spacing: SharpitSpacing.sm) {
                ProviderLogo(provider: .appleHealth)
                sourceTitle(
                    "Apple Santé",
                    status: line.text,
                    tone: line.isProblem ? SharpitColor.signalRisk : SharpitColor.mutedForeground
                )
            }
        }
        .tint(SharpitColor.primary)
        .disabled(!appleHealth.isAvailable)
    }

    private func sourceTitle(_ name: String, status: String, tone: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(name)
            Text(status)
                .font(SharpitTypography.meta)
                .foregroundStyle(tone)
                .lineLimit(1)
        }
    }

    private var appleHealthBinding: Binding<Bool> {
        Binding(
            get: { appleHealth.isEnabled },
            set: { on in
                if on {
                    Task { await appleHealth.enable(token: tokenProvider) }
                } else {
                    appleHealth.disable()
                }
            }
        )
    }

    /// Garmin opens in an in-app sheet (SHARPIT ADR-047); a new link is synced and its whole
    /// history imported, as the universal-link return does.
    private func connectGarmin() async {
        guard !isConnectingGarmin else { return }
        isConnectingGarmin = true
        defer { isConnectingGarmin = false }
        let outcome = await GarminConnect.run(
            client: garminClient,
            tokenProvider: tokenProvider,
            authenticate: webAuthenticationSession.garminConnect
        )
        if outcome.isLinked {
            await loadStatus()
        }
        toastCenter.show(
            outcome.message,
            symbol: outcome.symbol,
            tone: outcome.tone,
            autoDismissAfter: outcome.toastDuration
        )
        guard outcome == .connected, let token = try? await tokenProvider() else { return }
        status = try? await syncClient.sync(token: token)
        await historyImport?.runIfNeeded(userId: clerk.user?.id, tokenProvider: tokenProvider)
    }

    private func loadStatus() async {
        let token = toastCenter.show(
            "Vérification de Garmin…",
            symbol: "arrow.triangle.2.circlepath",
            autoDismissAfter: nil
        )
        defer { toastCenter.dismiss(token) }
        guard let tok = try? await tokenProvider() else { return }
        status = try? await syncClient.syncStatus(token: tok)
    }
}
