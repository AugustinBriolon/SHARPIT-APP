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
        self.summary = brick.totalDurationMin.map { DoneBrickFormat.duration($0 * 60) + String(localized: " au total") }
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

    /// « 1 h 20 », « 30 min ».
    static func duration(_ seconds: Int) -> String {
        SharpitFigureFormat.duration(seconds: Double(seconds))
    }

    /// A done leg's line: « 1h20 · RPE 6 », or « À faire » while it is not done.
    static func legMeta(_ leg: DoneBrickPreview.Leg) -> String {
        guard leg.isDone else { return String(localized: "À faire") }
        let parts = [
            leg.actual?.durationSec.map(duration),
            leg.actual?.rpe.map { "RPE \($0)" },
        ].compactMap { $0 }
        return parts.isEmpty ? String(localized: "Réalisée") : parts.joined(separator: " · ")
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
                VStack(alignment: .leading, spacing: 22) {
                    header
                    VStack(spacing: 0) {
                        ForEach(Array(brick.legs.enumerated()), id: \.element.id) { index, leg in
                            CliniqueDivider()
                            if index > 0 {
                                DoneBrickTransitionRow(index: index, seconds: brick.transition(before: index))
                                CliniqueDivider()
                            }
                            legPanel(index: index + 1, leg: leg)
                        }
                        CliniqueDivider()
                    }
                    if let evaluation {
                        BrickEvaluationTile(store: evaluation) { isEvaluating = true }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 24)
                .padding(.vertical, SharpitSpacing.md)
            }
            .cliniqueSheet(wash: brick.isComplete ? .good : .neutral, height: 220)
            .task { await loadEvaluation() }
            .sheet(isPresented: $isEvaluating) {
                if let evaluation {
                    BrickEvaluationSheet(store: evaluation)
                }
            }
            .navigationTitle("Enchaînement")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .principal) { Text("") } }
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

    /// How far the brick is as a pill, the chain as the title, its total, then the legs done as
    /// one bar in the data hues.
    private var header: some View {
        let timed = brick.legs.compactMap { leg in leg.actual?.durationSec.map { (leg, Double($0)) } }
        let total = timed.reduce(0) { $0 + $1.1 }
        return VStack(alignment: .leading, spacing: 10) {
            CliniqueStatusPill(
                brick.isComplete ? String(localized: "Enchaînement réalisé") : String(localized: "Enchaînement en cours"),
                status: brick.isComplete ? .good : .unknown
            )
            Text(brick.chain)
                .font(SharpitTypography.system(size: 24, weight: .semibold, relativeTo: .title2))
                .tracking(-0.4)
                .foregroundStyle(SharpitColor.foreground)
                .accessibilityAddTraits(.isHeader)
            if let summary = brick.summary {
                Text(summary)
                    .font(SharpitTypography.system(size: 16, weight: .regular, relativeTo: .callout, digits: true))
                    .foregroundStyle(SharpitColor.slate)
            }
            if total > 0, timed.count > 1 {
                GeometryReader { geo in
                    HStack(spacing: 3) {
                        ForEach(timed, id: \.0.id) { leg, seconds in
                            Capsule().fill(GoalsReadout.hue(V1ActivityType(sportLabel: leg.sport)))
                                .frame(width: max(4, (geo.size.width - CGFloat(timed.count - 1) * 3) * seconds / total))
                        }
                    }
                }
                .frame(height: 10)
                .padding(.top, 4)
                .accessibilityHidden(true)
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

/// One leg as a line: its sport over what it was, how it went at the trailing edge, and what
/// the athlete said of it under.
private struct DoneBrickLegPanel: View {
    let index: Int
    let leg: DoneBrickPreview.Leg
    let opens: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: SharpitSpacing.sm) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(leg.sport)
                        .font(SharpitTypography.system(size: 14, weight: .regular, relativeTo: .footnote))
                        .foregroundStyle(SharpitColor.slate)
                    Text(leg.title)
                        .font(SharpitTypography.system(size: 17, weight: .semibold, relativeTo: .body))
                        .foregroundStyle(SharpitColor.foreground)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                }
                Spacer(minLength: 0)
                Text(DoneBrickFormat.legMeta(leg))
                    .font(SharpitTypography.system(size: 16, weight: leg.isDone ? .semibold : .regular, relativeTo: .callout, digits: true))
                    .foregroundStyle(leg.isDone ? SharpitColor.foreground : SharpitColor.slate)
                if opens {
                    Image(systemName: "arrow.right")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(SharpitColor.slate)
                        .accessibilityHidden(true)
                }
            }
            if let feeling = leg.actual?.feeling?.trimmingCharacters(in: .whitespacesAndNewlines), !feeling.isEmpty {
                Text("« \(feeling) »")
                    .font(SharpitTypography.system(size: 14, weight: .regular, relativeTo: .footnote))
                    .foregroundStyle(SharpitColor.slate)
                    .multilineTextAlignment(.leading)
            }
        }
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(.rect)
        .accessibilityElement(children: .combine)
    }
}

/// The time between two legs as measured — T2 after the first leg.
private struct DoneBrickTransitionRow: View {
    let index: Int
    let seconds: Int?

    var body: some View {
        HStack {
            Text("Transition \(index + 1)")
                .font(SharpitTypography.system(size: 16, weight: .regular, relativeTo: .callout, digits: true))
                .foregroundStyle(SharpitColor.slate)
            Spacer(minLength: SharpitSpacing.xs)
            Text(seconds.map(DoneBrickFormat.transition) ?? String(localized: "non mesurée"))
                .font(SharpitTypography.system(size: 16, weight: seconds == nil ? .regular : .semibold, relativeTo: .callout, digits: true))
                .foregroundStyle(seconds == nil ? SharpitColor.slate : SharpitColor.foreground)
        }
        .padding(.vertical, 12)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(seconds.map { String(localized: "Transition \(index + 1), \(DoneBrickFormat.transition($0))") } ?? String(localized: "Transition non mesurée"))
    }
}
