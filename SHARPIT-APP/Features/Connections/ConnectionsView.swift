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

    @Environment(SharpitToastCenter.self) private var toastCenter
    @State private var status: V1SyncStatus?
    @State private var appleHealthToastToken: UUID?

    var body: some View {
        List {
            Section(eyebrow: "Sources") {
                garminRow
                appleHealthRow
            }
            .sharpitListRows()
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
        return Link(destination: APIConfiguration.baseURL.appending(path: "/connect/garmin")) {
            HStack(spacing: SharpitSpacing.sm) {
                ProviderLogo(provider: .garmin)
                sourceTitle("Garmin", status: badge.text, tone: badge.tone.color)
                Spacer(minLength: SharpitSpacing.xs)
                Image(systemName: "arrow.up.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.tertiary)
                    .accessibilityHidden(true)
            }
            .contentShape(.rect)
        }
        .foregroundStyle(SharpitColor.foreground)
        .accessibilityHint("Connecter Garmin sur le web")
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
