import AuthenticationServices
import SwiftUI

/// Paramètres → Sources de données: the sources that are linked, each opening a sheet to manage
/// or disconnect it, and a « + » that offers the rest (`docs/adr/0014`). Apple Health and Apple
/// Calendar are the iPhone's own; Strava / Withings / Google go through an in-app OAuth handoff,
/// Garmin through a personal API key (`GarminKeySheet`),
/// and a disconnection asks first, then `/api/v1/<source>/disconnect`.
///
/// Each source is one two-line row — its own mark, its name, one short status — so the rows
/// keep the same height whatever the status says. Recency surfaces on the toast shown while a
/// check is under way, not on a row read at rest (`docs/adr/0008`).
struct ConnectionsView: View {
    let appleHealth: AppleHealthSource
    let appleCalendar: AppleCalendarSource
    let syncClient: any SyncServing
    let tokenProvider: () async throws -> String
    var oauthHandoffClient: any ProviderOAuthHandoffServing = SharpitClient()
    var disconnectClient: any SourceDisconnecting = SourceDisconnectClient()
    var sourcePrefsClient: any SourcePrefsServing = SharpitClient()
    var garminKeyClient: any GarminKeyServing = GarminKeyClient()

    @Environment(SharpitToastCenter.self) private var toastCenter
    @State private var status: V1SyncStatus?
    @State private var appleHealthToastToken: UUID?
    @Environment(\.webAuthenticationSession) private var webAuthenticationSession
    @State private var connectingOAuth: DisconnectableSource?
    @State private var disconnecting: DisconnectableSource?
    @State private var managing: ManagedSource?
    @State private var showingAdd = false
    @State private var garminStatus = V1GarminKeyStatus.unavailable
    @State private var enteringGarminKey = false

    private var linked: Set<ManagedSource> {
        ConnectionsReadout.linkedSources(
            providerKeys: status?.providers.map(\.key) ?? [],
            appleHealthEnabled: appleHealth.isEnabled,
            appleCalendarLinked: appleCalendar.isLinked
        )
    }

    private var sourceLists: (connected: [ManagedSource], available: [ManagedSource]) {
        var unavailable: Set<ManagedSource> = appleHealth.isAvailable ? [] : [.appleHealth]
        // Garmin's key form is open to the athletes the server allows (web ADR-103).
        if !garminStatus.available { unavailable.insert(.garmin) }
        return ConnectionsReadout.split(linked: linked, unavailable: unavailable)
    }

    var body: some View {
        let lists = sourceLists
        List {
            Section(eyebrow: String(localized: "Connectées"), footer: ConnectionsReadout.sourcesFooter) {
                if lists.connected.isEmpty {
                    emptyRow
                } else {
                    ForEach(lists.connected) { connectedRow($0) }
                }
            }
            .sharpitListRows()

            if ConnectionsReadout.offersPriorities(connectedCount: lists.connected.count) {
                Section {
                    NavigationLink {
                        SourcePrioritiesView(tokenProvider: tokenProvider, appleCalendar: appleCalendar)
                    } label: {
                        Label {
                            Text("Priorités par catégorie")
                                .font(SharpitTypography.bodyEmphasis)
                        } icon: {
                            SharpitRowIcon.tile("list.number")
                        }
                    }
                } footer: {
                    SharpitListFooter(
                        String(localized: "Quand deux sources mesurent la même chose, choisis celle qui fait foi. Le calendrier où SharpIt écrit tes séances se choisit en touchant la source.")
                    )
                }
                .sharpitListRows()
            }
        }
        .sharpitGroupedList()
        .navigationTitle("Sources de données")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { showingAdd = true } label: { Image(systemName: "plus") }
                    .accessibilityLabel("Ajouter une source")
            }
        }
        .task { await loadStatus() }
        .refreshable { await loadStatus() }
        .sheet(item: $managing) { source in
            SourceManageSheet(
                source: source,
                status: statusLine(source),
                calendarPicker: calendarPicker(for: source),
                onReplaceKey: source == .garmin ? { replaceGarminKey() } : nil
            ) {
                managing = nil
                Task { await disconnectSource(source) }
            }
        }
        .sheet(isPresented: $showingAdd) {
            SourceAddSheet(sources: lists.available) { source in
                showingAdd = false
                Task { await connect(source) }
            }
        }
        .sheet(isPresented: $enteringGarminKey) {
            GarminKeySheet { apiKey in await connectGarmin(apiKey: apiKey) }
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

    private func isOAuthConnected(_ source: DisconnectableSource) -> Bool {
        status?.providers.contains(where: { $0.key == source.statusKey }) ?? false
    }

    private var emptyRow: some View {
        VStack(alignment: .leading, spacing: SharpitSpacing.xs) {
            Text("Aucune source connectée")
                .font(SharpitTypography.bodyEmphasis)
            Text("Relie Apple Santé, Strava ou une balance pour que le coach lise tes données.")
                .font(SharpitTypography.meta)
                .foregroundStyle(SharpitColor.mutedForeground)
            Button("Ajouter une source") { showingAdd = true }
                .font(SharpitTypography.bodyEmphasis)
                .padding(.top, SharpitSpacing.xs)
        }
    }

    private func connectedRow(_ source: ManagedSource) -> some View {
        let line = statusLine(source)
        let isBusy = source.oauth.map { disconnecting == $0 || connectingOAuth == $0 } ?? false
        return Button { managing = source } label: {
            HStack(spacing: SharpitSpacing.sm) {
                ProviderLogo(provider: source.logo)
                VStack(alignment: .leading, spacing: 2) {
                    Text(source.name)
                    Text(line.text)
                        .font(SharpitTypography.meta)
                        .foregroundStyle(line.isProblem ? SharpitColor.signalRisk : SharpitColor.mutedForeground)
                        .lineLimit(1)
                }
                Spacer(minLength: SharpitSpacing.xs)
                if isBusy {
                    ProgressView()
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
        .disabled(isBusy)
        .accessibilityHint("Gérer ou déconnecter \(source.name)")
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
        case .withings, .google, .strava:
            ConnectionsReadout.Line(text: source.purpose, isProblem: false)
        case .garmin:
            ConnectionsReadout.garminKeyLine(last4: garminStatus.apiKeyLast4)
        }
    }

    /// The sheet is gone before a web authentication session is asked to present over the page.
    private func connect(_ source: ManagedSource) async {
        switch source {
        case .appleHealth:
            await appleHealth.enable(token: tokenProvider)
        case .appleCalendar:
            await appleCalendar.enable(token: tokenProvider)
        case .withings, .google, .strava:
            guard let oauth = source.oauth else { return }
            try? await Task.sleep(for: .milliseconds(400))
            await connectOAuth(oauth)
        case .garmin:
            try? await Task.sleep(for: .milliseconds(400))
            enteringGarminKey = true
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
            toastCenter.show(
                SharpitErrorGuidance.message(for: error, subject: String(localized: "La synchronisation")),
                symbol: "exclamationmark.triangle",
                tone: .error,
                autoDismissAfter: 4
            )
        }
    }

    /// The manage sheet is gone before the key sheet is asked to present.
    private func replaceGarminKey() {
        managing = nil
        Task {
            try? await Task.sleep(for: .milliseconds(400))
            enteringGarminKey = true
        }
    }

    /// Garmin checks the key before the server keeps it, so the answer is awaited, retried, and a
    /// refusal stays in the sheet. Once linked, the first pull runs like an OAuth source's.
    private func connectGarmin(apiKey: String) async -> String? {
        do {
            try await SharpitRetry.run {
                try await garminKeyClient.connect(apiKey: apiKey, token: try await tokenProvider())
            }
        } catch {
            return ConnectionsReadout.garminKeyFailure(error)
        }
        await loadStatus()
        toastCenter.show(
            String(localized: "Garmin connecté"),
            symbol: "checkmark.circle.fill",
            tone: .success,
            autoDismissAfter: 3
        )
        do {
            status = try await syncClient.sync(token: try await tokenProvider())
        } catch {
            toastCenter.show(
                SharpitErrorGuidance.message(for: error, subject: String(localized: "La synchronisation")),
                symbol: "exclamationmark.triangle",
                tone: .error,
                autoDismissAfter: 4
            )
        }
        return nil
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
            // An older server without the route reads as Garmin closed, never as a failure.
            garminStatus = (try? await garminKeyClient.status(token: tok)) ?? .unavailable
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
