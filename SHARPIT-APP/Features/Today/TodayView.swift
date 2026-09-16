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
            Group {
                switch controller.state {
                case .loading:
                    SharpitLoadingInstrument()
                case .loaded(let payload):
                    TodayInstrumentView(payload: payload)
                case .empty(let empty):
                    TodayEmptyView(empty: empty)
                case .failed(let message):
                    ContentUnavailableView {
                        Label("Résumé indisponible", systemImage: "wifi.slash")
                    } description: {
                        Text(message)
                    } actions: {
                        Button("Réessayer") {
                            Task { await controller.load() }
                        }
                    }
                case .unauthorized:
                    ContentUnavailableView {
                        Label("Session expirée", systemImage: "person.crop.circle.badge.exclamationmark")
                    } description: {
                        Text("Reconnecte-toi pour recharger le résumé.")
                    }
                }
            }
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
                await controller.load()
                weather.start()
            }
            .task {
                await controller.load()
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
    private let client: any TodayServing
    private let tokenProvider: (() async throws -> String)?

    init(
        client: any TodayServing = FixtureTodayClient(),
        tokenProvider: (() async throws -> String)? = nil
    ) {
        self.client = client
        self.tokenProvider = tokenProvider
    }

    func load() async {
        state = .loading
        do {
            let token: String
            if let tokenProvider {
                token = try await tokenProvider()
            } else {
                token = ""
            }
            let payload = try await client.today(trainingDayId: TrainingDayId.today(), token: token)
            state = TodayModel.state(from: payload)
        } catch let error as SharpitAPIError where error == .unauthorized {
            state = .unauthorized
        } catch {
            state = .failed(Self.failureMessage(for: error))
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

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: SharpitSpacing.section) {
                VerdictHero(verdict: payload.verdict)
                if !payload.sessions.isEmpty {
                    VStack(alignment: .leading, spacing: 10) {
                        SharpitEyebrow("Séance")
                        ForEach(payload.sessions) { session in
                            SessionPlate(session: session)
                        }
                    }
                }
                if !payload.signals.isEmpty {
                    SignalStrip(signals: payload.signals)
                }
            }
            .padding(.horizontal, SharpitSpacing.pageInset)
            .padding(.bottom, SharpitSpacing.lg)
        }
        .modifier(ScrollUnderGlass())
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
