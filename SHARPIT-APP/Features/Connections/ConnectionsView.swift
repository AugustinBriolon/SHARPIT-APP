import AuthenticationServices
import SwiftUI

/// Paramètres → Connexions, on its mock-up (`docs/adr/0035`): every source on one table — the
/// linked ones with their state as a pill, each opening a sheet to manage or disconnect it, the
/// others with « Connecter » (`docs/adr/0014`). Apple Health and Apple Calendar are the iPhone's
/// own; Strava / Withings / Google / Garmin go through an in-app OAuth handoff, and a
/// disconnection asks first, then `/api/v1/<source>/disconnect`. « Synchroniser » pulls them all.
struct ConnectionsView: View {
    let appleHealth: AppleHealthSource
    let appleCalendar: AppleCalendarSource
    let syncClient: any SyncServing
    let tokenProvider: () async throws -> String
    var oauthHandoffClient: any ProviderOAuthHandoffServing = SharpitClient()
    var disconnectClient: any SourceDisconnecting = SourceDisconnectClient()
    var sourcePrefsClient: any SourcePrefsServing = SharpitClient()

    @Environment(SharpitToastCenter.self) private var toastCenter
    @State private var status: V1SyncStatus?
    @State private var appleHealthToastToken: UUID?
    @Environment(\.webAuthenticationSession) private var webAuthenticationSession
    @State private var connectingOAuth: DisconnectableSource?
    @State private var disconnecting: DisconnectableSource?
    @State private var managing: ManagedSource?
    @State private var isSynchronizing = false

    private var linked: Set<ManagedSource> {
        ConnectionsReadout.linkedSources(
            providerKeys: status?.providers.map(\.key) ?? [],
            appleHealthEnabled: appleHealth.isEnabled,
            appleCalendarLinked: appleCalendar.isLinked
        )
    }

    private var sourceLists: (connected: [ManagedSource], available: [ManagedSource]) {
        ConnectionsReadout.split(linked: linked, unavailable: appleHealth.isAvailable ? [] : [.appleHealth])
    }

    var body: some View {
        let lists = sourceLists
        ScrollView {
            VStack(alignment: .leading, spacing: 26) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Connexions")
                        .font(SharpitTypography.system(size: 32, weight: .semibold, relativeTo: .largeTitle))
                        .tracking(-0.6)
                        .foregroundStyle(SharpitColor.foreground)
                        .accessibilityAddTraits(.isHeader)
                    Text(ConnectionsReadout.sourcesSummary(linked))
                        .font(SharpitTypography.system(size: 16, weight: .regular, relativeTo: .callout, digits: true))
                        .foregroundStyle(SharpitColor.slate)
                }
                VStack(alignment: .leading, spacing: 4) {
                    sectionTitle(String(localized: "Sources"))
                    VStack(spacing: 0) {
                        ForEach(lists.connected + lists.available) { source in
                            if source != (lists.connected + lists.available).first { CliniqueDivider() }
                            if lists.connected.contains(source) { connectedRow(source) } else { availableRow(source) }
                        }
                    }
                    Text(ConnectionsReadout.sourcesFooter)
                        .font(SharpitTypography.system(size: 13, weight: .regular, relativeTo: .footnote))
                        .foregroundStyle(SharpitColor.slate)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 8)
                }
                if ConnectionsReadout.offersPriorities(connectedCount: lists.connected.count) {
                    NavigationLink {
                        SourcePrioritiesView(tokenProvider: tokenProvider, appleCalendar: appleCalendar)
                    } label: {
                        HStack(alignment: .center, spacing: SharpitSpacing.sm) {
                            VStack(alignment: .leading, spacing: 3) {
                                sectionTitle(String(localized: "Quelle source pour quelle donnée"))
                                Text("Quand deux sources mesurent la même chose.")
                                    .font(SharpitTypography.system(size: 15, weight: .regular, relativeTo: .subheadline))
                                    .foregroundStyle(SharpitColor.slate)
                                    .multilineTextAlignment(.leading)
                            }
                            Spacer(minLength: 0)
                            Image(systemName: "arrow.right")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(SharpitColor.slate)
                                .accessibilityHidden(true)
                        }
                        .contentShape(.rect)
                    }
                    .buttonStyle(.sharpitPressable)
                }
            }
            .padding(.horizontal, 24)
            .padding(.top, SharpitSpacing.xs)
            .padding(.bottom, SharpitSpacing.xl)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .cliniqueSheet(wash: .neutral, height: 240)
        .navigationTitle("Connexions")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) { Text("") }
            ToolbarItem(placement: .topBarTrailing) {
                Button("Synchroniser") { Task { await synchronize() } }
                    .font(SharpitTypography.system(size: 16, weight: .semibold, relativeTo: .callout))
                    .foregroundStyle(SharpitColor.foreground)
                    .disabled(isSynchronizing)
            }
        }
        .task { await loadStatus() }
        .refreshable { await loadStatus() }
        .sheet(item: $managing) { source in
            SourceManageSheet(source: source, status: statusLine(source), calendarPicker: calendarPicker(for: source)) {
                managing = nil
                Task { await disconnectSource(source) }
            }
        }
        .onChange(of: appleHealth.state) { _, state in
            switch state {
            case .sending:
                appleHealthToastToken = toastCenter.show(
                    String(localized: "Import depuis Apple Santé…"),
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

    private func sectionTitle(_ title: String) -> some View {
        Text(title)
            .font(SharpitTypography.sectionTitle)
            .tracking(SharpitTypography.sectionTitleTracking)
            .foregroundStyle(SharpitColor.foreground)
            .accessibilityAddTraits(.isHeader)
    }

    private func sourceWords(_ source: ManagedSource, detail: String, isProblem: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(source.name)
                .font(SharpitTypography.system(size: 17, weight: .semibold, relativeTo: .body))
                .foregroundStyle(SharpitColor.foreground)
            Text(detail)
                .font(SharpitTypography.system(size: 14, weight: .regular, relativeTo: .footnote))
                .foregroundStyle(isProblem ? SharpitColor.statusAlertMark : SharpitColor.slate)
                .multilineTextAlignment(.leading)
                .lineLimit(2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// A linked source: what it brings, and its state as a pill. The line opens its sheet.
    private func connectedRow(_ source: ManagedSource) -> some View {
        let line = statusLine(source)
        let isBusy = source.oauth.map { disconnecting == $0 || connectingOAuth == $0 } ?? false
        return Button { managing = source } label: {
            HStack(spacing: SharpitSpacing.sm) {
                sourceWords(source, detail: line.text, isProblem: line.isProblem)
                if isBusy {
                    ProgressView()
                } else {
                    CliniqueStatusPill(
                        line.isProblem ? String(localized: "À vérifier") : String(localized: "Connecté"),
                        status: line.isProblem ? .watch : .good
                    )
                }
            }
            .padding(.vertical, 14)
            .contentShape(.rect)
        }
        .buttonStyle(.sharpitPressable)
        .disabled(isBusy)
        .accessibilityHint("Gérer ou déconnecter \(source.name)")
    }

    /// A source not linked yet: what it would bring, and the button that links it.
    private func availableRow(_ source: ManagedSource) -> some View {
        let isBusy = source.oauth.map { connectingOAuth == $0 } ?? false
        return HStack(spacing: SharpitSpacing.sm) {
            sourceWords(source, detail: source.purpose)
            if isBusy {
                ProgressView()
            } else {
                Button("Connecter") { Task { await connect(source) } }
                    .buttonStyle(CliniqueButtonStyle(kind: .outline))
                    .accessibilityLabel("Connecter \(source.name)")
            }
        }
        .padding(.vertical, 14)
    }

    /// « Synchroniser »: pulls every provider now, then reads the sources again.
    private func synchronize() async {
        guard !isSynchronizing else { return }
        isSynchronizing = true
        defer { isSynchronizing = false }
        if let token = try? await tokenProvider() {
            status = (try? await syncClient.sync(token: token)) ?? status
        }
        await loadStatus()
    }

    private func calendarPicker(for source: ManagedSource) -> AnyView? {
        switch source {
        case .google: AnyView(GoogleCalendarPickerView(tokenProvider: tokenProvider))
        case .appleCalendar: AnyView(AppleCalendarPickerView())
        default: nil
        }
    }

    private func statusLine(_ source: ManagedSource) -> ConnectionsReadout.Line {
        switch source {
        case .appleHealth:
            ConnectionsReadout.appleHealthSubtitle(isAvailable: appleHealth.isAvailable, state: appleHealth.state)
        case .appleCalendar:
            ConnectionsReadout.appleCalendarSubtitle(state: appleCalendar.state)
        case .withings, .google, .strava, .garmin:
            ConnectionsReadout.Line(text: source.purpose, isProblem: false)
        }
    }

    private func connect(_ source: ManagedSource) async {
        switch source {
        case .appleHealth:
            await appleHealth.enable(token: tokenProvider)
        case .appleCalendar:
            await appleCalendar.enable(token: tokenProvider)
        case .withings, .google, .strava, .garmin:
            guard let oauth = source.oauth else { return }
            await connectOAuth(oauth)
        }
    }

    private func disconnectSource(_ source: ManagedSource) async {
        switch source {
        case .appleHealth:
            await appleHealth.disable(token: tokenProvider)
        case .appleCalendar:
            await appleCalendar.disable(token: tokenProvider)
        case .withings, .google, .strava, .garmin:
            guard let oauth = source.oauth else { return }
            await disconnect(oauth)
        }
    }

    private func connectOAuth(_ source: DisconnectableSource) async {
        guard connectingOAuth == nil else { return }
        connectingOAuth = source
        defer { connectingOAuth = nil }
        let outcome = await ProviderOAuthConnect.run(
            source: source,
            client: oauthHandoffClient,
            tokenProvider: tokenProvider,
            authenticate: webAuthenticationSession.providerOAuthConnect
        )
        if outcome.isLinked {
            await loadStatus()
        }
        toastCenter.show(
            outcome.message(for: source),
            symbol: outcome.symbol,
            tone: outcome.tone,
            autoDismissAfter: outcome.toastDuration
        )
        guard outcome == .connected else { return }
        do {
            status = try await syncClient.sync(token: try await tokenProvider())
        } catch {
            guard let message = ProviderOAuthConnect.followUpSyncFailureMessage(for: error) else { return }
            toastCenter.show(
                message,
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
            String(localized: "Vérification des sources…"),
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
                SharpitErrorGuidance.message(for: error, subject: String(localized: "L’état des connexions")),
                symbol: "exclamationmark.triangle",
                tone: .error,
                autoDismissAfter: 4
            )
        }
    }
}
