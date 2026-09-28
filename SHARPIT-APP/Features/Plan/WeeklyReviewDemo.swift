#if DEBUG
import SwiftUI

/// The weekly review on a fixed week, to check its layout in the simulator without an account.
/// Debug builds only: `-SharpitWeeklyReviewDemo`.
enum WeeklyReviewDemo {
    static var isRequested: Bool {
        ProcessInfo.processInfo.arguments.contains("-SharpitWeeklyReviewDemo")
    }
}

struct WeeklyReviewDemoHost: View {
    var body: some View {
        NavigationStack {
            WeeklyReviewView(store: WeeklyReviewStore(client: DemoReviewClient(), tokenProvider: { "demo" }))
        }
    }
}

private struct DemoReviewClient: WeeklyReviewServing {
    func latestReview(token: String) async throws -> V1WeeklyReview? {
        V1WeeklyReview(
            id: "demo",
            weekStart: "2026-09-21",
            content: """
            ## Bilan d'entraînement
            Tu as bouclé **4 séances sur 5**, pour une charge en hausse de 12 %.

            ## Sommeil & récupération
            Nuits régulières autour de **7 h**, avec une nuit courte mercredi.

            ## Ce qui a bien marché
            - Seuil de jeudi tenu à 4:05/km du début à la fin
            - Quatre séances sur cinq, sans trou dans la semaine

            ## À surveiller
            - Nuit courte mercredi avant la séance de seuil

            ## Plan pour la semaine prochaine
            - Une sortie longue de 1 h 30 en endurance
            - Garder le renforcement du mardi
            """,
            stats: V1WeeklyStats(
                weekStart: "2026-09-21",
                dailyLoad: [45, nil, 72, 40, nil, 95, 60],
                dailySleepScore: [80, 76, 58, 82, 79, 85, 81],
                byType: [.init(type: "RUN", count: 3, durationMin: 190), .init(type: "STRENGTH", count: 1, durationMin: 45), .init(type: "BIKE", count: 1, durationMin: 55)],
                sessionsDone: 4,
                sessionsPlanned: 5,
                totalLoad: 312,
                totalDurationMin: 290,
                prevTotalLoad: 278,
                sleep: .init(avgDurationMin: 431, avgScore: 78),
                recovery: .init(avgReadiness: 71, avgHrv: 55)
            )
        )
    }

    func generateReview(token: String) async throws -> V1WeeklyReview {
        try await latestReview(token: token)!
    }
}
#endif
