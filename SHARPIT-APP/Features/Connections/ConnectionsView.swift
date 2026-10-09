import AuthenticationServices
import ClerkKit
import SwiftUI

/// Paramètres → Sources de données: every source the iPhone app links — Apple Health, and Garmin
/// when `ProviderAvailability` offers it; until then a Garmin watch reaches SHARPIT through Apple
/// Health. Withings and Google Agenda are linked on the web (their OAuth return has no native
/// handoff yet) and show here once connected, so they can be disconnected from the phone: a
/// connected row asks first (`DisconnectableSource`), then `/api/v1/<source>/disconnect`.
/// Apple Health is switched on here, because only the phone can read it.
///
/// Each source is one two-line row — its own mark, its name, one short status — so the rows
/// keep the same height whatever the status says. Recency surfaces on the toast shown while a
/// check is under way, not on a row read at rest (`docs/adr/0008`).
struct ConnectionsView: View {
    let appleHealth: AppleHealthSource
    let appleCalendar: AppleCalendarSource
    let syncClient: any SyncServing
    let tokenProvider: () async throws -> String
    var garminClient: any GarminHandoffServing = SharpitClient()
    var disconnectClient: any SourceDisconnecting = SourceDisconnectClient()
    var sourcePrefsClient: any SourcePrefsServing = SharpitClient()

    @Environment(SharpitToastCenter.self) private var toastCenter
    @Environment(Clerk.self) private var clerk
    /// Owned by `RootView`, which shows its progress and result as toasts wherever the athlete is.
    @Environment(GarminHistoryImport.self) private var historyImport: GarminHistoryImport?
    @State private var status: V1SyncStatus?
    @State private var appleHealthToastToken: UUID?
    @Environment(\.webAuthenticationSession) private var webAuthenticationSession
    @State private var isConnectingGarmin = false
    @State private var confirmingDisconnect: DisconnectableSource?
    @State private var disconnecting: DisconnectableSource?

    var body: some View {
        List {
            Section(eyebrow: "Sources", footer: ConnectionsReadout.webSourcesFooter(connected: webSources)) {
                if ProviderAvailability.garminInApp {
                    garminRow
                }
                appleHealthRow
                appleCalendarRow
                ForEach(webSources) { source in
                    connectedSourceRow(source)
                }
            }
            .sharpitListRows()

            Section {
                NavigationLink {
                    SourcePrioritiesView(tokenProvider: tokenProvider, appleCalendar: appleCalendar)
                } label: {
                    Label {
                        Text("Priorités par catégorie")
                            .font(SharpitTypography.bodyEmphasis)
                    } icon: {
                        SharpitRowIcon(symbol: "list.number")
                    }
                }
            } footer: {
                SharpitListFooter(
                    "Quand deux sources mesurent la même chose, choisis celle qui fait foi. L’Agenda Google (créneaux) n’est pas le calendrier des séances Sharpit dans Plan."
                )
            }
            .sharpitListRows()

            if ProviderAvailability.garminInApp, isGarminConnected, historyImport != nil {
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
        .confirmationDialog(
            confirmingDisconnect?.confirmationTitle ?? "",
            isPresented: Binding(
                get: { confirmingDisconnect != nil },
                set: { if !$0 { confirmingDisconnect = nil } }
            ),
            titleVisibility: .visible,
            presenting: confirmingDisconnect
        ) { source in
            Button(source.confirmLabel, role: .destructive) {
                Task { await disconnect(source) }
            }
            Button("Annuler", role: .cancel) {}
        } message: { source in
            Text(source.confirmationMessage)
        }
        .onChange(of: appleHealth.state) { _, state in
            switch state {
            case .sending:
                appleHealthToastToken = toastCenter.show(
                    "Import depuis Apple Santé…",
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
            if isGarminConnected {
                confirmingDisconnect = .garmin
            } else {
                Task { await connectGarmin() }
            }
        } label: {
            HStack(spacing: SharpitSpacing.sm) {
                ProviderLogo(provider: .garmin)
                sourceTitle("Garmin", status: badge.text, tone: badge.tone.color)
                Spacer(minLength: SharpitSpacing.xs)
                if disconnecting == .garmin {
                    ProgressView()
                } else if isGarminConnected {
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
        .disabled(disconnecting == .garmin)
        .accessibilityHint(
            isGarminConnected
                ? "Propose de déconnecter Garmin"
                : "Connecter Garmin directement dans l'application"
        )
    }

    /// The sources linked on the web that the phone can only disconnect.
    private var webSources: [DisconnectableSource] {
        DisconnectableSource.connected(in: status).filter { $0 != .garmin }
    }

    /// A source linked on the web: its mark, its name, what it brings; a tap asks to disconnect it.
    private func connectedSourceRow(_ source: DisconnectableSource) -> some View {
        let badge = ConnectionsReadout.connected(source)
        return Button {
            confirmingDisconnect = source
        } label: {
            HStack(spacing: SharpitSpacing.sm) {
                ProviderLogo(provider: source.logo)
                sourceTitle(source.name, status: badge.text, tone: badge.tone.color)
                Spacer(minLength: SharpitSpacing.xs)
                if disconnecting == source {
                    ProgressView()
                } else {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(SharpitColor.primary)
                }
            }
            .contentShape(.rect)
        }
        .foregroundStyle(SharpitColor.foreground)
        .disabled(disconnecting == source)
        .accessibilityHint("Propose de déconnecter \(source.name)")
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
                    Task { await appleHealth.disable(token: tokenProvider) }
                }
            }
        )
    }

    private var appleCalendarRow: some View {
        let line = ConnectionsReadout.appleCalendarSubtitle(state: appleCalendar.state)
        return Toggle(isOn: appleCalendarBinding) {
            HStack(spacing: SharpitSpacing.sm) {
                ProviderLogo(provider: .appleCalendar)
                sourceTitle(
                    "Calendrier Apple",
                    status: line.text,
                    tone: line.isProblem ? SharpitColor.signalRisk : SharpitColor.mutedForeground
                )
            }
        }
        .tint(SharpitColor.primary)
    }

    private var appleCalendarBinding: Binding<Bool> {
        Binding(
            get: { appleCalendar.isLinked },
            set: { on in
                if on {
                    Task { await appleCalendar.enable(token: tokenProvider) }
                } else {
                    Task { await appleCalendar.disable(token: tokenProvider) }
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
        guard outcome == .connected else { return }
        do {
            let token = try await tokenProvider()
            status = try await syncClient.sync(token: token)
            await historyImport?.runIfNeeded(userId: clerk.user?.id, tokenProvider: tokenProvider)
        } catch {
            toastCenter.show(
                SharpitErrorGuidance.message(for: error, subject: "La synchronisation"),
                symbol: "exclamationmark.triangle",
                tone: .error,
                autoDismissAfter: 4
            )
        }
    }

    /// Waits for the server — a disconnection revokes access at the provider, so the row only
    /// changes once it is done — retried through `SharpitRetry`, then the list is read again.
    private func disconnect(_ source: DisconnectableSource) async {
        guard disconnecting == nil else { return }
        disconnecting = source
        defer { disconnecting = nil }
        do {
            try await SharpitRetry.run {
                try await disconnectClient.disconnect(source, token: try await tokenProvider())
            }
            await loadStatus()
            toastCenter.show(
                source.disconnectedMessage,
                symbol: "checkmark.circle.fill",
                tone: .success,
                autoDismissAfter: 3
            )
        } catch {
            toastCenter.show(
                ConnectionsReadout.disconnectFailure(source, error: error),
                symbol: "exclamationmark.triangle",
                tone: .error,
                autoDismissAfter: 4
            )
        }
    }

    private func loadStatus() async {
        let token = toastCenter.show(
            "Vérification de Garmin…",
            symbol: "arrow.triangle.2.circlepath",
            autoDismissAfter: nil
        )
        defer { toastCenter.dismiss(token) }
        do {
            let tok = try await tokenProvider()
            status = try await syncClient.syncStatus(token: tok)
            let answer = try await sourcePrefsClient.sourcePrefs(token: tok)
            appleCalendar.syncLinkedFromServer(answer.connected.contains(AppleCalendarSync.providerId))
        } catch {
            toastCenter.show(
                SharpitErrorGuidance.message(for: error, subject: "L’état des connexions"),
                symbol: "exclamationmark.triangle",
                tone: .error,
                autoDismissAfter: 4
            )
        }
    }
}
