import Foundation

struct TodayFold: Sendable, Equatable {
    var trainingDayId: String
    var plate: InkPlateModel
    var sessions: [SessionCardModel]
    var gauges: [OvernightGaugeModel]
    var weather: V1TodayWeather?
}

struct InkPlateModel: Sendable, Equatable {
    var statusLabel: String
    var headline: String
    var actionLine: String?
    var limitingCause: String?
    var confidencePct: Int?
    var confidenceLabel: String?
    var packTier: V1TodayPackTier?
    var estimationGaps: [String]
    var posture: V1TodayPosture
}

struct SessionCardModel: Sendable, Equatable, Identifiable {
    var id: String
    var kind: V1TodaySessionKind
    var title: String
    var subtitle: String?
    var metrics: [V1TodayMetric]
    var sport: String?
    var priority: Bool
}

struct OvernightGaugeModel: Sendable, Equatable, Identifiable {
    var key: V1TodaySignalKey
    var score: String
    var caption: String?

    var id: V1TodaySignalKey { key }
}

enum ConfidenceBars {
    static func filled(fromPct pct: Int?) -> Int {
        guard let pct else { return 0 }
        if pct >= 67 { return 3 }
        if pct >= 34 { return 2 }
        if pct > 0 { return 1 }
        return 0
    }
}

enum PackTierTone: Equatable {
    case highlight
    case caution
    case muted

    /// Confidence bars / trust chrome — mirrors web `packTierConfidenceBarsTone`.
    static func bars(for tier: V1TodayPackTier?) -> PackTierTone {
        switch tier {
        case .partial, .low:
            return .caution
        case .insufficient:
            return .muted
        case .full, .none:
            return .highlight
        }
    }

    /// Status row dot — follows the go/stop label, not packTier (PARTIAL stays amber on bars only).
    static func statusDot(for statusLabel: String) -> PackTierTone {
        let label = statusLabel.uppercased()
        if label.contains("ROUGE") || label.contains("STOP") {
            return .muted
        }
        if label.contains("ORANGE") || label.contains("JAUNE") || label.contains("AMBRE") {
            return .caution
        }
        return .highlight
    }
}

enum TodayFoldMapper {
    static func map(_ response: V1TodayResponse) -> TodayFold {
        let verdict = response.verdict
        return TodayFold(
            trainingDayId: response.trainingDayId,
            plate: InkPlateModel(
                statusLabel: verdict.statusLabel?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
                    ?? verdict.eyebrow,
                headline: verdict.headline,
                actionLine: verdict.actionLine?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
                    ?? verdict.subline.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty,
                limitingCause: verdict.limitingCause,
                confidencePct: verdict.confidencePct,
                confidenceLabel: verdict.confidenceLabel,
                packTier: verdict.packTier,
                estimationGaps: verdict.estimationGaps ?? [],
                posture: verdict.posture
            ),
            sessions: response.sessions.map { session in
                SessionCardModel(
                    id: session.id,
                    kind: session.kind,
                    title: session.title,
                    subtitle: session.subtitle,
                    metrics: session.metrics,
                    sport: session.sport,
                    priority: session.priority ?? false
                )
            },
            gauges: response.signals
                .filter { $0.key == .sleep || $0.key == .recovery }
                .map {
                    OvernightGaugeModel(key: $0.key, score: $0.score, caption: $0.caption)
                },
            weather: response.weather
        )
    }
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}
