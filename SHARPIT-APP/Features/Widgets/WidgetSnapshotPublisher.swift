import ClerkKit
import Foundation
import WidgetKit

extension WidgetSnapshot {
    /// Résumé's day as the widgets show it — the fold already mapped for the screen, so the
    /// widgets say what Résumé says.
    init(fold: TodayFold, writtenAt: Date = .now) {
        self.init(
            trainingDayId: fold.trainingDayId,
            writtenAt: writtenAt,
            verdict: Verdict(
                status: fold.plate.statusLabel,
                headline: fold.plate.headline,
                action: fold.plate.actionLine,
                posture: fold.plate.posture
            ),
            sessions: fold.sessions.map { card in
                Session(
                    id: card.id,
                    isDone: card.kind == .done,
                    title: card.title,
                    sport: V1ActivityType(sportLabel: card.sport ?? ""),
                    figures: card.metrics.prefix(2).map { $0.unit.isEmpty ? $0.value : "\($0.value) \($0.unit)" }
                )
            }
        )
    }
}

/// Writes the widgets' snapshot and asks WidgetKit to redraw them.
enum WidgetSnapshotPublisher {
    /// Only today's fold reaches the home screen.
    static func publish(_ fold: TodayFold, now: Date = .now) {
        guard fold.trainingDayId == TrainingDayId.today(now: now) else { return }
        let snapshot = WidgetSnapshot(fold: fold, writtenAt: now)
        guard snapshot != WidgetSnapshotStore.read() ?? nil else { return }
        try? WidgetSnapshotStore.write(snapshot)
        WidgetCenter.shared.reloadAllTimelines()
    }

    static func erase() {
        WidgetSnapshotStore.erase()
        WidgetCenter.shared.reloadAllTimelines()
    }

    /// Reads today in the background — a silent push after a server sync — and publishes it.
    /// Returns whether anything was read.
    @MainActor
    static func refreshInBackground(client: any TodayServing = SharpitClient()) async -> Bool {
        guard let token = try? await Clerk.shared.auth.getToken(),
              let payload = try? await client.today(trainingDayId: TrainingDayId.today(), token: token),
              case .loaded(let response) = TodayModel.state(from: payload)
        else { return false }
        publish(TodayFoldMapper.map(response))
        return true
    }
}
