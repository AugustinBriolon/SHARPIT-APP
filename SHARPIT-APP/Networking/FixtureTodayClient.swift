import Foundation

protocol TodayServing: Sendable {
    func today(trainingDayId: String, token: String) async throws -> V1TodayResponse
}

/// Answers the morning recalibration: accepting rewrites today's session on the server.
protocol MorningProposalServing: Sendable {
    func respondToMorningProposal(decisionId: String, accept: Bool, token: String) async throws
}

nonisolated struct V1MorningProposalAnswer: Decodable, Sendable {
    let ok: Bool
}

enum SharpitAPIError: Error, Equatable, LocalizedError {
    case unauthorized
    case badRequest
    case server
    case transport
    /// The server refused because the same request ran moments ago.
    case rateLimited
    case message(String)
    /// Google OAuth token expired or revoked — relink Google Agenda, not the SharpIt session.
    case googleNeedsReconnect(String)
    /// `403 { error: 'pro_required' }`: coaching is SharpIt Pro (SHARPIT ADR-097). A screen shows
    /// `SharpitProTeaser` for it, never an error line.
    case proRequired

    /// Whether a refusal's body is the server's `pro_required` — or, for the session analysis,
    /// its older word for the same refusal, `402 { error: 'locked' }`.
    nonisolated static func isProRequired(_ body: Data, code: String = "pro_required") -> Bool {
        let json = try? JSONSerialization.jsonObject(with: body) as? [String: Any]
        return json?["error"] as? String == code
    }

    var errorDescription: String? {
        switch self {
        case .proRequired:
            return String(localized: "Réservé à SharpIt Pro.")
        case .message(let text), .googleNeedsReconnect(let text):
            return text
        case .unauthorized:
            return String(localized: "Session expirée ou non autorisée")
        case .badRequest:
            return String(localized: "Requête invalide")
        case .rateLimited:
            return String(localized: "Trop de requêtes, réessaie plus tard")
        case .server:
            return String(localized: "Erreur serveur")
        case .transport:
            return String(localized: "Problème de connexion réseau")
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
                eyebrow: String(localized: "Ce matin"),
                headline: String(localized: "Journée légère"),
                subline: String(localized: "Tenir"),
                posture: .steady,
                confidencePct: 72,
                limitingCause: String(localized: "Sommeil court"),
                statusLabel: String(localized: "Léger"),
                actionLine: String(localized: "Reste en endurance facile."),
                confidenceLabel: "ESTIMATION PARTIELLE",
                packTier: .partial,
                estimationGaps: [String(localized: "Baseline HRV partielle (moins de 14 j)")],
                explanation: V1TodayExplanation(
                    essential: String(localized: "Ton corps est prêt pour une séance légère."),
                    expert: String(localized: "TSB stable · VFC dans la norme.")
                ),
                instruction: String(localized: "Reste en endurance facile."),
                limiterSignals: [.sleepShort],
                limiterSignal: .sleepShort,
                vsYesterdayLabel: String(localized: "Comme hier"),
                showHeadline: false,
                stateCode: .trainEasy
            ),
            weather: V1TodayWeather(city: String(localized: "Lyon"), tempC: 12, condition: String(localized: "Nuageux")),
            sessions: [
                V1TodaySession(
                    id: "s1",
                    kind: .planned,
                    title: String(localized: "Seuil 40 min"),
                    subtitle: String(localized: "Course"),
                    metrics: [V1TodayMetric(label: String(localized: "Durée"), value: "40", unit: "min")],
                    sport: String(localized: "Course"),
                    priority: true
                ),
            ],
            signals: [
                V1TodaySignal(key: .sleep, score: "78", caption: String(localized: "Correct")),
                V1TodaySignal(key: .recovery, score: "61", caption: nil),
            ]
        )
    }
}
