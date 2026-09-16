import SwiftUI

struct TodayView: View {
    @State private var store: TodayStore
    @State private var weather = LocationWeatherService()

    init(
        client: any TodayServing = FixtureTodayClient(),
        tokenProvider: (() async throws -> String)? = nil
    ) {
        _store = State(
            initialValue: TodayStore(client: client, tokenProvider: tokenProvider)
        )
    }

    var body: some View {
        NavigationStack {
            ZStack {
                switch store.phase {
                case .loading:
                    SharpitLoadingInstrument()
                        .transition(.opacity)
                case .loaded(let fold):
                    TodayFoldView(
                        fold: fold,
                        pulseScores: store.pulseScores,
                        sessionDoneCelebrations: store.sessionDoneCelebrations,
                        onArrival: { store.handleArrivalWins(fold: fold) }
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
                            Task { await store.load(resetToLoading: true) }
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
            .animation(SharpitMotion.fade, value: store.phaseIdentity)
            .background(SharpitCanvasBackground(posture: store.loadedPosture))
            .navigationTitle(store.navigationTitle)
            .navigationBarTitleDisplayMode(.large)
            .modifier(LiquidNavChrome())
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    WeatherToolbarChip(service: weather)
                }
            }
            .refreshable {
                await store.refresh()
                weather.start()
            }
            .task {
                await store.load(resetToLoading: true)
                weather.start()
            }
        }
    }
}

private struct TodayFoldView: View {
    let fold: TodayFold
    var pulseScores: Bool = false
    var sessionDoneCelebrations: Set<String> = []
    var onArrival: () -> Void = {}

    @State private var arrival: TodayArrivalPhase = .hidden
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: SharpitSpacing.section) {
                InkVerdictPlate(plate: fold.plate, revealed: arrival.showsPlate)
                evidenceSection
                    .opacity(arrival.showsSession ? 1 : 0)
                    .offset(y: arrival.showsSession ? 0 : 10)
                if !fold.gauges.isEmpty {
                    OvernightGaugePair(
                        gauges: fold.gauges,
                        revealed: arrival.showsGauges,
                        pulseScores: pulseScores
                    )
                }
            }
            .padding(.horizontal, SharpitSpacing.pageInset)
            .padding(.bottom, SharpitSpacing.lg)
        }
        .modifier(ScrollUnderGlass())
        .task {
            onArrival()
            await TodayArrivalDirector.run(
                reduceMotion: reduceMotion,
                gaugeCount: fold.gauges.count
            ) { phase in
                arrival = phase
            }
        }
    }

    @ViewBuilder
    private var evidenceSection: some View {
        if fold.sessions.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                SharpitEyebrow("Séance")
                RestDayPlate()
            }
        } else {
            VStack(alignment: .leading, spacing: 10) {
                SharpitEyebrow("Séance")
                ForEach(fold.sessions) { session in
                    SessionPlate(
                        session: session,
                        celebrateDone: sessionDoneCelebrations.contains(session.id)
                    )
                }
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
