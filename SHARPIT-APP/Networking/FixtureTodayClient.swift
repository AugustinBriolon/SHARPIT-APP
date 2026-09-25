import Foundation

protocol TodayServing: Sendable {
    func today(trainingDayId: String, token: String) async throws -> V1TodayResponse
}

enum SharpitAPIError: Error, Equatable, LocalizedError {
    case unauthorized
    case badRequest
    case server
    case transport
    /// The server refused because the same request ran moments ago.
    case rateLimited
    case message(String)

    var errorDescription: String? {
        switch self {
        case .message(let text):
            return text
        case .unauthorized:
            return "Session expirée ou non autorisée"
        case .badRequest:
            return "Requête invalide"
        case .rateLimited:
            return "Trop de requêtes, réessaie plus tard"
        case .server:
            return "Erreur serveur"
        case .transport:
            return "Problème de connexion réseau"
        }
    }
}

struct FixtureTodayClient: TodayServing {
    func today(trainingDayId: String, token _: String) async throws -> V1TodayResponse {
        V1TodayResponse(
            apiVersion: 1,
            trainingDayId: trainingDayId,
            empty: nil,
            verdict: V1TodayVerdict(
                eyebrow: "Ce matin",
                headline: "Séance prévue",
                subline: "Tenir",
                posture: .steady,
                confidencePct: 72,
                limitingCause: "Sommeil court",
                statusLabel: "FEU VERT",
                actionLine: "Entraîne-toi — légèrement",
                confidenceLabel: "ESTIMATION PARTIELLE",
                packTier: .partial,
                estimationGaps: ["Baseline HRV partielle (moins de 14 j)"]
            ),
            weather: V1TodayWeather(city: "Lyon", tempC: 12, condition: "Nuageux"),
            sessions: [
                V1TodaySession(
                    id: "s1",
                    kind: .planned,
                    title: "Seuil 40 min",
                    subtitle: "Course",
                    metrics: [V1TodayMetric(label: "Durée", value: "40", unit: "min")],
                    sport: "Course",
                    priority: true
                ),
            ],
            signals: [
                V1TodaySignal(key: .sleep, score: "78", caption: "Correct"),
                V1TodaySignal(key: .recovery, score: "61", caption: nil),
            ]
        )
    }
}
