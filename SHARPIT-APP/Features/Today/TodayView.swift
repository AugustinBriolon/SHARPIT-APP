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
                    TodayLoadingView()
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
            .background(TodayCanvasBackground(posture: loadedPosture))
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

private struct TodayCanvasBackground: View {
    let posture: V1TodayPosture?

    var body: some View {
        LinearGradient(
            colors: [
                (posture?.accentColor ?? Color.accentColor).opacity(0.18),
                Color(.systemBackground),
            ],
            startPoint: .top,
            endPoint: .center
        )
        .ignoresSafeArea()
    }
}

private struct TodayLoadingView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(.quaternary)
                .frame(height: 168)
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(.quaternary)
                .frame(height: 96)
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(.quaternary)
                .frame(height: 72)
        }
        .padding(20)
        .redacted(reason: .placeholder)
    }
}

private struct TodayInstrumentView: View {
    let payload: V1TodayResponse

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                verdictBlock
                if !payload.sessions.isEmpty {
                    sessionsBlock
                }
                if !payload.signals.isEmpty {
                    signalsBlock
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 28)
        }
        .modifier(ScrollUnderGlass())
    }

    private var verdictBlock: some View {
        VStack(alignment: .leading, spacing: 14) {
            SharpitEyebrow(payload.verdict.eyebrow)
            Text(payload.verdict.headline)
                .font(.system(size: 36, weight: .semibold))
                .tracking(-0.8)
                .lineSpacing(2)
            Text(payload.verdict.subline)
                .font(.body)
                .foregroundStyle(.primary.opacity(0.82))
            HStack(spacing: 16) {
                if let cause = payload.verdict.limitingCause {
                    Label(cause, systemImage: "target")
                }
                if let confidence = payload.verdict.confidencePct {
                    HStack(spacing: 4) {
                        Text("\(confidence)%")
                            .font(.body.monospacedDigit().weight(.semibold))
                        Text("confiance")
                            .font(.body)
                    }
                }
            }
            .font(.footnote)
            .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, 8)
        .padding(.bottom, 4)
    }

    private var sessionsBlock: some View {
        VStack(alignment: .leading, spacing: 10) {
            SharpitEyebrow("Séance")
            ForEach(payload.sessions) { session in
                VStack(alignment: .leading, spacing: 14) {
                    HStack(alignment: .firstTextBaseline) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(session.title)
                                .font(.headline)
                            if let subtitle = session.subtitle {
                                Text(subtitle)
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        Spacer()
                        Text(session.kind == .done ? "Faite" : "Prévue")
                            .font(.system(size: 11, weight: .semibold))
                            .tracking(1.2)
                            .textCase(.uppercase)
                            .foregroundStyle(.secondary)
                    }
                    if !session.metrics.isEmpty {
                        HStack(spacing: 16) {
                            ForEach(session.metrics, id: \.label) { metric in
                                VStack(alignment: .leading, spacing: 2) {
                                    HStack(alignment: .firstTextBaseline, spacing: 3) {
                                        Text(metric.value)
                                            .font(.title3.monospacedDigit().weight(.semibold))
                                        Text(metric.unit)
                                            .font(.footnote.weight(.medium))
                                            .foregroundStyle(.secondary)
                                    }
                                    Text(metric.label)
                                        .font(.system(size: 10, weight: .semibold))
                                        .tracking(0.8)
                                        .textCase(.uppercase)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            Spacer(minLength: 0)
                        }
                    }
                }
                .padding(18)
                .sharpitGlassCard()
            }
        }
    }

    private var signalsBlock: some View {
        VStack(alignment: .leading, spacing: 10) {
            SharpitEyebrow("Signaux")
            HStack(spacing: 8) {
                ForEach(payload.signals) { signal in
                    VStack(spacing: 6) {
                        Text(signal.score)
                            .font(.title3.monospacedDigit().weight(.semibold))
                        Text(signal.key.label)
                            .font(.system(size: 10, weight: .semibold))
                            .tracking(0.8)
                            .textCase(.uppercase)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .sharpitGlassCard()
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

private extension V1TodaySignalKey {
    var label: String {
        switch self {
        case .sleep: "Nuit"
        case .recovery: "Récup"
        case .effort: "Effort"
        case .adaptation: "Adapt."
        }
    }
}

private extension V1TodayPosture {
    var accentColor: Color {
        switch self {
        case .protect: .orange
        case .steady: Color.accentColor
        case .push: .green
        case .uncertain: .secondary
        }
    }
}
