import Foundation

struct TodayFold: Sendable, Equatable {
    var trainingDayId: String
    var plate: InkPlateModel
    var sessions: [SessionCardModel]
    var gauges: [OvernightGaugeModel]
    var consistency: V1TodayConsistency?
    var weather: V1TodayWeather?
    var morningProposal: V1TodayMorningProposal? = nil
    /// The next week SharpIt wrote as the plan runs out (ADR-095).
    var planHorizon: V1TodayPlanHorizon? = nil
    /// Race day, or the result in the days after it.
    var race: RaceMomentModel? = nil
    /// ADR-079. Callers: WidgetSnapshotPublisher. API: V1TodayResponse.energyBank.
    var energyBank: V1TodayEnergyBank? = nil
    /// Day timeline. Callers: TodayView. API: V1TodayResponse.timeline. User: fix all.
    var timeline: [V1DayTimelineEvent] = []
    /// Painted from the on-disk snapshot, which keeps the verdict only (no health measures):
    /// sessions and gauges are unknown, not empty, until the network answers.
    var isPlateOnly = false
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
    /// Additive verdict fields (PR #154) — optional so a cached legacy day still paints.
    var explanationEssential: String? = nil
    var explanationExpert: String? = nil
    var instruction: String? = nil
    var limiterSignals: [LimiterSignalCode] = []
    var vsYesterdayLabel: String? = nil
    var showHeadline: Bool = true
    var stateCode: VerdictStateCode? = nil

    /// Explanation for the current reading density — plain text only.
    func explanation(isExpert: Bool) -> String? {
        let raw = isExpert ? explanationExpert : explanationEssential
        return VerdictCopySanitizer.display(raw, fallback: VerdictCopySanitizer.fallbackExplanation)
    }

    /// Instruction, with placeholder guard.
    var safeInstruction: String? {
        VerdictCopySanitizer.display(instruction, fallback: VerdictCopySanitizer.fallbackInstruction)
            ?? VerdictCopySanitizer.display(actionLine, fallback: VerdictCopySanitizer.fallbackInstruction)
    }

    func limiterChip(isExpert: Bool) -> String? {
        LimiterChipCopy.text(codes: limiterSignals, isExpert: isExpert)
    }

    /// Whether the large headline should paint (false when the server says so, or empty).
    var displaysHeadline: Bool {
        guard showHeadline else { return false }
        return !headline.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

struct SessionCardModel: Sendable, Equatable, Identifiable {
    var id: String
    var kind: V1TodaySessionKind
    var title: String
    var subtitle: String?
    var metrics: [V1TodayMetric]
    var sport: String?
    var priority: Bool
    /// Set on a planned line, and only when the prescription can be addressed on its own.
    var plannedSessionId: String?
    /// A brick's legs, in order — two at least, else nil.
    var brickLegs: [V1TodayBrickLeg]? = nil
    /// A brick under way: seconds between legs, nil where unknown.
    var brickTransitionsSec: [Int?]? = nil
    /// A brick's group, which addresses the brick as a whole.
    var brickGroupId: String? = nil
    /// One of the week's key sessions (SHARPIT F2).
    var isKey = false
    /// Why the coach wrote this session — Decision Memory rationale.
    var rationale: String? = nil
    /// A planned strength session's exercises, when the server sent them.
    var strengthPrescription: JSONValue? = nil
    /// A done session's match to its plan, 0–100.
    var complianceScore: Int? = nil
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

    /// Status row dot — prefers the stable state code; falls back to legacy go/stop labels.
    static func statusDot(for statusLabel: String, stateCode: VerdictStateCode? = nil) -> PackTierTone {
        if let stateCode {
            return stateCode.statusTone
        }
        let label = statusLabel.uppercased()
        if label.contains("ROUGE") || label.contains("STOP") || label.contains("REPOS") {
            return .muted
        }
        if label.contains("ORANGE") || label.contains("JAUNE") || label.contains("AMBRE")
            || label.contains("PRUDENCE")
        {
            return .caution
        }
        return .highlight
    }
}

enum TodayFoldMapper {
    /// Prefer the array; fall back to the singular code for older additive payloads.
    static func resolvedLimiterSignals(_ verdict: V1TodayVerdict) -> [LimiterSignalCode] {
        if let signals = verdict.limiterSignals, !signals.isEmpty {
            return signals
        }
        if let signal = verdict.limiterSignal {
            return [signal]
        }
        return []
    }

    static func resolvedStateCode(_ code: VerdictStateCode?) -> VerdictStateCode? {
        guard let code else { return nil }
        if case .unknown(let raw) = code, raw.isEmpty { return nil }
        return code
    }

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
                posture: verdict.posture,
                explanationEssential: verdict.explanation?.essential,
                explanationExpert: verdict.explanation?.expert,
                instruction: verdict.instruction?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty,
                limiterSignals: Self.resolvedLimiterSignals(verdict),
                vsYesterdayLabel: verdict.vsYesterdayLabel?
                    .trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty,
                showHeadline: verdict.showHeadline ?? true,
                stateCode: Self.resolvedStateCode(verdict.stateCode)
            ),
            sessions: response.sessions.map { session in
                SessionCardModel(
                    id: session.id,
                    kind: session.kind,
                    title: session.title,
                    subtitle: session.subtitle,
                    metrics: session.metrics,
                    sport: session.sport,
                    priority: session.priority ?? false,
                    plannedSessionId: session.plannedSessionId,
                    brickLegs: (session.brickLegs?.count ?? 0) > 1 ? session.brickLegs : nil,
                    brickTransitionsSec: session.brickTransitionsSec,
                    brickGroupId: session.brickGroupId,
                    isKey: session.isKey ?? false,
                    rationale: session.rationale,
                    strengthPrescription: session.strengthPrescription,
                    complianceScore: session.complianceScore
                )
            },
            gauges: response.signals
                .filter { $0.key == .sleep || $0.key == .recovery }
                .map {
                    OvernightGaugeModel(key: $0.key, score: $0.score, caption: $0.caption)
                },
            consistency: response.consistency,
            weather: response.weather,
            morningProposal: response.morningProposal,
            planHorizon: response.planHorizon,
            race: RaceMomentMapper.map(response.race, trainingDayId: response.trainingDayId),
            energyBank: response.energyBank,
            timeline: response.timeline ?? []
        )
    }
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}
