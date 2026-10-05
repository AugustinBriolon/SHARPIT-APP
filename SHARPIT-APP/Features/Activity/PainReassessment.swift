import SwiftUI

/// After a session, the pains and injuries owed a word — the web's `dueReassessments`
/// « after_session » rule (`reassessment-due.ts`): an open pain or injury, active or under watch,
/// with no reading since the session started. A session the athlete did is the moment their body
/// answered the question; asked while it is fresh, so only for a session of the last week.
nonisolated struct PainReassessment: Identifiable, Equatable, Sendable {
    let zone: V1SensitiveZone
    var id: String { zone.id }

    var question: String { "Comment va « \(zone.title) » après cette séance ?" }

    static let followedCategories: Set<String> = ["PAIN", "INJURY"]
    static let followedStatuses: Set<String> = ["ACTIVE", "MONITORING"]
    static let freshness: TimeInterval = 7 * 86_400

    /// Worst first, as the web orders them.
    static func due(after sessionStart: Date, zones: [V1SensitiveZone], now: Date = .now) -> [PainReassessment] {
        guard sessionStart <= now, now.timeIntervalSince(sessionStart) <= freshness else { return [] }
        return zones
            .filter { zone in
                zone.resolvedAt == nil
                    && followedCategories.contains(zone.category)
                    && followedStatuses.contains(zone.status)
                    && !zone.timeline.contains { $0.kind == .reading && $0.date >= sessionStart }
            }
            .sorted { ($0.severity ?? 0) > ($1.severity ?? 0) }
            .map(PainReassessment.init)
    }
}

/// « Réévaluer une douleur », under the session's figures: one row per zone owed a word, each
/// opening the check-in the zone's own page uses. Answered, the row leaves.
struct PainReassessmentSection: View {
    let items: [PainReassessment]
    let onAnswer: (PainReassessment) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: SharpitSpacing.xs) {
            SharpitEyebrow("Réévaluer une douleur")
            ForEach(items) { item in
                Button { onAnswer(item) } label: {
                    HStack(spacing: SharpitSpacing.sm) {
                        Image(systemName: "heart.text.square")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(SharpitColor.signalCaution)
                            .frame(width: 36, height: 36)
                            .background(SharpitColor.signalCaution.opacity(0.14), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                        VStack(alignment: .leading, spacing: 2) {
                            Text(item.question)
                                .font(SharpitTypography.bodyEmphasis)
                                .foregroundStyle(SharpitColor.foreground)
                                .multilineTextAlignment(.leading)
                            Text(item.zone.place)
                                .font(SharpitTypography.meta)
                                .foregroundStyle(SharpitColor.mutedForeground)
                        }
                        Spacer(minLength: 0)
                        Image(systemName: "chevron.right")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(SharpitColor.mutedForeground)
                    }
                    .padding(SharpitSpacing.cardPadding)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .sharpitSurface(.panel)
                }
                .buttonStyle(.sharpitPressable)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }
}
