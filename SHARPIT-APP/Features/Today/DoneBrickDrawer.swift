import SwiftUI

/// A brick under way, as Résumé opens it: the chain it was, each leg beside the activity that
/// realized it — its duration, RPE and feeling — and the transitions between legs as measured.
struct DoneBrickPreview: Identifiable, Equatable {
    struct Leg: Equatable, Identifiable {
        let id: String
        let sport: String
        let title: String
        let activityId: String?
        let actual: V1TodayBrickLegActual?

        var isDone: Bool { activityId != nil }
    }

    let id: String
    /// The brick's group, which its evaluation is saved under; nil from servers that predate it.
    let brickGroupId: String?
    let summary: String?
    let legs: [Leg]
    /// Seconds from each leg's end to the next's start; nil where unknown.
    let transitionsSec: [Int?]

    var chain: String { legs.map(\.sport).joined(separator: " → ") }

    /// Every leg done — the brick can be judged as a whole.
    var isComplete: Bool { legs.allSatisfy(\.isDone) }

    /// Résumé's done brick line; nil for any other line.
    init?(card: SessionCardModel) {
        guard card.kind == .done, let legs = card.brickLegs, legs.count > 1 else { return nil }
        self.id = card.id
        self.brickGroupId = card.brickGroupId
        self.summary = card.subtitle
        self.legs = legs.map { leg in
            Leg(
                id: leg.id,
                sport: V1ActivityType(rawValue: leg.type)?.label ?? leg.type,
                title: leg.title,
                activityId: (leg.completed ?? false) ? leg.activityId : nil,
                actual: leg.actual
            )
        }
        self.transitionsSec = card.brickTransitionsSec ?? []
    }

    /// Plan's done brick: the prescribed legs beside the activities that realized them.
    init(planned brick: PlanDoneBrick) {
        self.id = brick.id
        self.brickGroupId = brick.id
        self.summary = brick.totalDurationMin.map { DoneBrickFormat.duration($0 * 60) + " au total" }
        self.legs = brick.legs.map { leg in
            Leg(
                id: leg.session.id,
                sport: leg.activity?.type.label ?? leg.session.displayType,
                title: leg.session.title ?? leg.activity?.title ?? leg.session.displayType,
                activityId: leg.activity?.id,
                actual: leg.activity.map { activity in
                    V1TodayBrickLegActual(
                        durationSec: activity.duration.map { Int($0.rounded()) },
                        load: activity.load,
                        rpe: activity.rpe.map { Int($0.rounded()) },
                        feeling: nil
                    )
                }
            )
        }
        self.transitionsSec = zip(brick.legs, brick.legs.dropFirst()).map { previous, next in
            Self.transitionSec(from: previous.activity, to: next.activity)
        }
    }

    /// From one leg's end to the next's start; nil when either is unknown or they overlap.
    static func transitionSec(from previous: V1ActivityListItem?, to next: V1ActivityListItem?) -> Int? {
        guard let previous, let next, let duration = previous.duration else { return nil }
        let gap = next.date.timeIntervalSince(previous.date.addingTimeInterval(duration))
        return gap >= 0 ? Int(gap.rounded()) : nil
    }

    /// The transition before leg `index` (1 is T2), when measured.
    func transition(before index: Int) -> Int? {
        let position = index - 1
        guard position >= 0, position < transitionsSec.count else { return nil }
        return transitionsSec[position]
    }
}

enum DoneBrickFormat {
    /// « 2 min 04 », « 45 s » — as the web writes it.
    static func transition(_ seconds: Int) -> String {
        guard seconds >= 60 else { return "\(seconds) s" }
        return "\(seconds / 60) min \(String(format: "%02d", seconds % 60))"
    }

    /// « 1h20 », « 30 min ».
    static func duration(_ seconds: Int) -> String {
        let hours = seconds / 3600
        let minutes = (seconds % 3600) / 60
        return hours > 0 ? "\(hours)h\(String(format: "%02d", minutes))" : "\(minutes) min"
    }

    /// A done leg's line: « 1h20 · RPE 6 », or « À faire » while it is not done.
    static func legMeta(_ leg: DoneBrickPreview.Leg) -> String {
        guard leg.isDone else { return "À faire" }
        let parts = [
            leg.actual?.durationSec.map(duration),
            leg.actual?.rpe.map { "RPE \($0)" },
        ].compactMap { $0 }
        return parts.isEmpty ? "Réalisée" : parts.joined(separator: " · ")
    }
}

struct DoneBrickDrawer: View {
    let brick: DoneBrickPreview
    let tokenProvider: (() async throws -> String)?

    @Environment(\.dismiss) private var dismiss
    @State private var evaluation: BrickEvaluationStore?
    @State private var isEvaluating = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: SharpitSpacing.lg) {
                    header
                    VStack(spacing: 0) {
                        ForEach(Array(brick.legs.enumerated()), id: \.element.id) { index, leg in
                            if index > 0 {
                                DoneBrickTransitionRow(index: index, seconds: brick.transition(before: index))
                            }
                            legPanel(index: index + 1, leg: leg)
                        }
                    }
                    if let evaluation {
                        BrickEvaluationTile(store: evaluation) { isEvaluating = true }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(SharpitSpacing.pageInset)
            }
            .background(SharpitCanvasBackground())
            .task { await loadEvaluation() }
            .sheet(isPresented: $isEvaluating) {
                if let evaluation {
                    BrickEvaluationSheet(store: evaluation)
                }
            }
            .navigationTitle("Enchaînement")
            .navigationBarTitleDisplayMode(.inline)
        }
        .presentationDetents([.large])
        .sharpitSheet()
        .presentationDragIndicator(.visible)
    }

    /// Only a fully done brick is evaluated: the web asks the same, every leg linked.
    private func loadEvaluation() async {
        guard evaluation == nil, brick.isComplete, let groupId = brick.brickGroupId, let tokenProvider else { return }
        let store = BrickEvaluationStore(
            brickGroupId: groupId,
            client: BrickEvaluationClient(),
            tokenProvider: tokenProvider
        )
        evaluation = store
        await store.load()
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: SharpitSpacing.sm) {
            SharpitEyebrow("Brick réalisé · \(brick.legs.count) étapes")
            BrickChainGlyphs(sports: brick.legs.map(\.sport))
            Text(brick.chain)
                .font(SharpitTypography.pageTitle)
                .tracking(SharpitTypography.pageTitleTracking)
                .foregroundStyle(SharpitColor.foreground)
            if let summary = brick.summary {
                Text(summary)
                    .font(SharpitTypography.meta)
                    .foregroundStyle(SharpitColor.mutedForeground)
            }
        }
    }

    @ViewBuilder
    private func legPanel(index: Int, leg: DoneBrickPreview.Leg) -> some View {
        if let activityId = leg.activityId, let tokenProvider {
            NavigationLink {
                ActivityDetailView(
                    activity: activityId,
                    initialActivity: nil,
                    client: ActivityClient(),
                    tokenProvider: tokenProvider
                )
            } label: {
                DoneBrickLegPanel(index: index, leg: leg, opens: true)
            }
            .buttonStyle(.sharpitPressable)
        } else {
            DoneBrickLegPanel(index: index, leg: leg, opens: false)
        }
    }
}

/// One leg: its place in the chain, its sport, what it was and how it felt.
private struct DoneBrickLegPanel: View {
    let index: Int
    let leg: DoneBrickPreview.Leg
    let opens: Bool

    private var tone: Color { SharpitSportTone.label(for: leg.sport) }

    var body: some View {
        VStack(alignment: .leading, spacing: SharpitSpacing.xs) {
            HStack(spacing: SharpitSpacing.sm) {
                Text("\(index)")
                    .font(SharpitTypography.instrument)
                    .foregroundStyle(tone)
                    .frame(width: 30, height: 30)
                    .background(tone.opacity(0.14), in: Circle())
                VStack(alignment: .leading, spacing: 1) {
                    Text(leg.sport)
                        .font(SharpitTypography.label)
                        .tracking(SharpitTypography.labelTracking)
                        .textCase(.uppercase)
                        .foregroundStyle(tone)
                    Text(leg.title)
                        .font(SharpitTypography.cardTitle)
                        .tracking(SharpitTypography.cardTitleTracking)
                        .foregroundStyle(SharpitColor.foreground)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                }
                Spacer(minLength: 0)
                Text(DoneBrickFormat.legMeta(leg))
                    .font(SharpitTypography.meta)
                    .foregroundStyle(leg.isDone ? SharpitColor.foreground : SharpitColor.mutedForeground)
                if opens {
                    Image(systemName: "chevron.right")
                        .font(SharpitTypography.label)
                        .foregroundStyle(SharpitColor.mutedForeground)
                }
            }
            if let feeling = leg.actual?.feeling?.trimmingCharacters(in: .whitespacesAndNewlines), !feeling.isEmpty {
                Text("« \(feeling) »")
                    .font(SharpitTypography.meta)
                    .italic()
                    .foregroundStyle(SharpitColor.mutedForeground)
                    .multilineTextAlignment(.leading)
            }
        }
        .padding(SharpitSpacing.cardPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .sharpitSurface(.panel)
        .contentShape(.rect)
    }
}

/// The time between two legs as measured — T2 after the first leg.
private struct DoneBrickTransitionRow: View {
    let index: Int
    let seconds: Int?

    var body: some View {
        HStack(spacing: SharpitSpacing.sm) {
            Rectangle()
                .fill(SharpitColor.primary.opacity(0.5))
                .frame(width: 2, height: 36)
                .padding(.leading, SharpitSpacing.cardPadding + 14)
            Text("T\(index + 1) · " + (seconds.map(DoneBrickFormat.transition) ?? "non mesurée"))
                .font(SharpitTypography.label)
                .tracking(SharpitTypography.labelTracking)
                .textCase(.uppercase)
                .foregroundStyle(SharpitColor.primary)
                .padding(.horizontal, SharpitSpacing.sm)
                .padding(.vertical, SharpitSpacing.xxs + 1)
                .background(SharpitColor.primary.opacity(0.10), in: Capsule())
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(seconds.map { "Transition \(index + 1), \(DoneBrickFormat.transition($0))" } ?? "Transition non mesurée")
    }
}
