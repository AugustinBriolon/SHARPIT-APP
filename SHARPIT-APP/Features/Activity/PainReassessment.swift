import SwiftUI

/// After a session, the pains and injuries owed a word — the web's `dueReassessments`
/// « after_session » rule (`reassessment-due.ts`): an open pain or injury, active or under watch,
/// with no reading since the session started. A session the athlete did is the moment their body
/// answered the question; asked while it is fresh, so only for a session of the last week.
nonisolated struct PainReassessment: Identifiable, Equatable, Sendable {
    let zone: V1SensitiveZone
    var id: String { zone.id }

    var question: String { String(localized: "Comment va « \(zone.title) » après cette séance ?") }

    /// « gêne 2 / 10 avant la séance », or where the zone is when it was never rated.
    var standing: String {
        zone.severity.map { String(localized: "gêne \($0) / 10 avant la séance") } ?? zone.place
    }

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

/// « Zones à réévaluer », under the session's figures, as its mock-up reads it: a line per zone
/// owed a word — its name over where it stood before the session — and « Faire le point », which
/// opens the check-in the zone's own page uses. Answered, the line leaves.
struct PainReassessmentSection: View {
    let items: [PainReassessment]
    let onAnswer: (PainReassessment) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Zones à réévaluer")
                .font(SharpitTypography.sectionTitle)
                .tracking(SharpitTypography.sectionTitleTracking)
                .foregroundStyle(SharpitColor.foreground)
                .accessibilityAddTraits(.isHeader)
                .padding(.bottom, 4)
            ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                if index > 0 { CliniqueDivider() }
                HStack(spacing: SharpitSpacing.sm) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(item.zone.title)
                            .font(SharpitTypography.system(size: 16, weight: .regular, relativeTo: .callout))
                            .foregroundStyle(SharpitColor.foreground)
                            .multilineTextAlignment(.leading)
                        Text(item.standing)
                            .font(SharpitTypography.system(size: 13, weight: .regular, relativeTo: .caption, digits: true))
                            .foregroundStyle(SharpitColor.slate)
                    }
                    .accessibilityElement(children: .combine)
                    Spacer(minLength: SharpitSpacing.xs)
                    Button("Faire le point") { onAnswer(item) }
                        .buttonStyle(CliniqueButtonStyle(kind: .outline))
                }
                .padding(.vertical, 12)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
