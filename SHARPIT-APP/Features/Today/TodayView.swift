import SwiftUI

struct TodayView: View {
    @State private var controller: TodayController
    @State private var weather = LocationWeatherService()

    init(
        client: any TodayServing = FixtureTodayClient(),
        tokenProvider: (() async throws -> String)? = nil
    ) {
        _controller = State(
            initialValue: TodayController(client: client, tokenProvider: tokenProvider)
        )
    }

    var body: some View {
        NavigationStack {
            ZStack {
                switch controller.state {
                case .loading:
                    SharpitLoadingInstrument()
                        .transition(.opacity)
                case .loaded(let payload):
                    TodayInstrumentView(
                        payload: payload,
                        pulseScores: controller.pulseScores,
                        sessionDoneCelebrations: controller.sessionDoneCelebrations,
                        onArrival: { controller.handleArrivalWins(payload: payload) }
                    )
                    .transition(.opacity)
                case .empty(let empty):
                    TodayEmptyView(empty: empty)
                        .transition(.opacity)
                case .failed(let message):
                    ContentUnavailableView {
                        Label("Résumé indisponible", systemImage: "wifi.slash")
                    } description: {
                        Text(message)
                    } actions: {
                        Button("Réessayer") {
                            Task { await controller.load(resetToLoading: true) }
                        }
                    }
                    .transition(.opacity)
                case .unauthorized:
                    ContentUnavailableView {
                        Label("Session expirée", systemImage: "person.crop.circle.badge.exclamationmark")
                    } description: {
                        Text("Reconnecte-toi pour recharger le résumé.")
                    }
                    .transition(.opacity)
                }
            }
            .animation(SharpitMotion.fade, value: controller.stateIdentity)
            .background(SharpitCanvasBackground(posture: loadedPosture))
            .navigationTitle(navigationTitle)
            .navigationBarTitleDisplayMode(.large)
            .modifier(LiquidNavChrome())
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    WeatherToolbarChip(service: weather)
                }
            }
            .refreshable {
                await controller.refresh()
                weather.start()
            }
            .task {
                await controller.load(resetToLoading: true)
                weather.start()
            }
        }
    }

    private var navigationTitle: String {
        if case .loaded(let payload) = controller.state {
            return TrainingDayId.displayName(payload.trainingDayId)
        }
        return "Résumé"
    }

    private var loadedPosture: V1TodayPosture? {
        if case .loaded(let payload) = controller.state {
            return payload.verdict.posture
        }
        return nil
    }
}

@Observable
final class TodayController {
    var state: TodayScreenState = .loading
    var pulseScores = false
    var sessionDoneCelebrations: Set<String> = []
    private let client: any TodayServing
    private let tokenProvider: (() async throws -> String)?

    init(
        client: any TodayServing = FixtureTodayClient(),
        tokenProvider: (() async throws -> String)? = nil
    ) {
        self.client = client
        self.tokenProvider = tokenProvider
    }

    var stateIdentity: String {
        switch state {
        case .loading: "loading"
        case .loaded: "loaded"
        case .empty: "empty"
        case .failed: "failed"
        case .unauthorized: "unauthorized"
        }
    }

    func load(resetToLoading: Bool) async {
        if resetToLoading {
            state = .loading
        }
        do {
            let token: String
            if let tokenProvider {
                token = try await tokenProvider()
            } else {
                token = ""
            }
            let payload = try await client.today(trainingDayId: TrainingDayId.today(), token: token)
            let previousConfidence: Int? = {
                if case .loaded(let prior) = state {
                    return prior.verdict.confidencePct
                }
                return SharpitWinStore.lastConfidence(trainingDayId: payload.trainingDayId)
            }()
            state = TodayModel.state(from: payload)
            if case .loaded(let loaded) = state {
                noteConfidence(payload: loaded, previous: previousConfidence)
            }
        } catch let error as SharpitAPIError where error == .unauthorized {
            state = .unauthorized
        } catch {
            state = .failed(Self.failureMessage(for: error))
        }
    }

    func refresh() async {
        await load(resetToLoading: false)
        if case .loaded(let payload) = state {
            SharpitHaptics.play(.light)
            flashScores()
            markNewSessionDones(in: payload)
        }
    }

    func handleArrivalWins(payload: V1TodayResponse) {
        let key = SharpitWinStore.arrivalKey(trainingDayId: payload.trainingDayId)
        if SharpitWinStore.consume(key) {
            SharpitHaptics.play(.soft)
        }
        markNewSessionDones(in: payload)
        if let confidence = payload.verdict.confidencePct {
            SharpitWinStore.setLastConfidence(confidence, trainingDayId: payload.trainingDayId)
        }
    }

    private func markNewSessionDones(in payload: V1TodayResponse) {
        var fresh: Set<String> = []
        for session in payload.sessions where session.kind == .done {
            let doneKey = SharpitWinStore.sessionDoneKey(
                trainingDayId: payload.trainingDayId,
                sessionId: session.id
            )
            if SharpitWinStore.consume(doneKey) {
                fresh.insert(session.id)
            }
        }
        if !fresh.isEmpty {
            sessionDoneCelebrations.formUnion(fresh)
        }
    }

    private func noteConfidence(payload: V1TodayResponse, previous: Int?) {
        guard let current = payload.verdict.confidencePct else { return }
        SharpitWinStore.setLastConfidence(current, trainingDayId: payload.trainingDayId)
        // ConfidenceRing animates fill when percent rises; no haptic (spec).
        _ = previous
    }

    private func flashScores() {
        SharpitMotion.run(.easeOut(duration: 0.18)) {
            pulseScores = true
        }
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(220))
            SharpitMotion.run(.easeOut(duration: 0.22)) {
                pulseScores = false
            }
        }
    }

    private static func failureMessage(for error: Error) -> String {
        guard let apiError = error as? SharpitAPIError else {
            return "Impossible de charger le résumé"
        }
        switch apiError {
        case .badRequest:
            return "Requête invalide"
        case .server:
            return "Le serveur n'a pas pu produire le résumé"
        case .transport:
            return "Réseau indisponible — vérifie yarn dev sur 127.0.0.1:3000"
        case .unauthorized:
            return "Session expirée"
        }
    }
}

private struct TodayInstrumentView: View {
    let payload: V1TodayResponse
    var pulseScores: Bool = false
    var sessionDoneCelebrations: Set<String> = []
    var onArrival: () -> Void = {}

    @State private var revealed = false
    @State private var evidenceRevealed = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: SharpitSpacing.section) {
                VerdictHero(
                    verdict: payload.verdict,
                    revealed: revealed,
                    pulseScores: pulseScores
                )
                if !payload.signals.isEmpty {
                    SignalStrip(
                        signals: payload.signals,
                        revealed: revealed,
                        pulseScores: pulseScores
                    )
                }
                evidenceSection
                    .opacity(evidenceRevealed ? 1 : 0)
                    .offset(y: evidenceRevealed ? 0 : 10)
            }
            .padding(.horizontal, SharpitSpacing.pageInset)
            .padding(.bottom, SharpitSpacing.lg)
        }
        .modifier(ScrollUnderGlass())
        .onAppear(perform: runArrival)
    }

    @ViewBuilder
    private var evidenceSection: some View {
        if payload.sessions.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                SharpitEyebrow("Séance")
                RestDayPlate()
            }
        } else {
            VStack(alignment: .leading, spacing: 10) {
                SharpitEyebrow("Séance")
                ForEach(payload.sessions) { session in
                    SessionPlate(
                        session: session,
                        celebrateDone: sessionDoneCelebrations.contains(session.id)
                    )
                }
            }
        }
    }

    private func runArrival() {
        onArrival()
        if SharpitMotion.reduceMotion || reduceMotion {
            revealed = true
            evidenceRevealed = true
            return
        }
        SharpitMotion.run {
            revealed = true
        }
        let evidenceDelay = SharpitMotion.staggerDelay(index: max(payload.signals.count, 1))
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(evidenceDelay + 0.08))
            SharpitMotion.run {
                evidenceRevealed = true
            }
        }
    }
}

private struct TodayEmptyView: View {
    let empty: V1TodayEmpty

    var body: some View {
        ContentUnavailableView {
            Label(empty.title, systemImage: "tray")
        } description: {
            if let message = empty.message {
                Text(message)
            }
        } actions: {
            if let url = URL(string: empty.webURL) {
                Link("Continuer sur le web", destination: url)
            }
        }
    }
}
