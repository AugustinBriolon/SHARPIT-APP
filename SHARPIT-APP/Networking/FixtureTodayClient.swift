import Foundation

protocol TodayServing: Sendable {
    func today(trainingDayId: String, token: String) async throws -> V1TodayResponse
}

enum SharpitAPIError: Error, Equatable {
    case unauthorized
    case badRequest
    case server
    case transport
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
                limitingCause: "Sommeil court"
            ),
            weather: V1TodayWeather(city: "Lyon", tempC: 12, condition: "Nuageux"),
            sessions: [
                V1TodaySession(
                    id: "s1",
                    kind: .planned,
                    title: "Seuil 40 min",
                    subtitle: "Course",
                    metrics: [V1TodayMetric(label: "Durée", value: "40", unit: "min")]
                ),
            ],
            signals: [
                V1TodaySignal(key: .sleep, score: "78", caption: "Correct"),
                V1TodaySignal(key: .recovery, score: "61", caption: nil),
                V1TodaySignal(key: .effort, score: "—", caption: nil),
                V1TodaySignal(key: .adaptation, score: "55", caption: nil),
            ]
        )
    }
}
