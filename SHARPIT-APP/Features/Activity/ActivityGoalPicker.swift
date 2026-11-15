import SwiftUI

extension V1ActivityGoal {
    /// The link as the session page shows it before the server answers — which marks a race
    /// reached once its day has come and a session is linked to it.
    init(goal: V1Goal) {
        self.init(
            id: goal.id,
            title: goal.title,
            raceFormat: goal.raceFormat,
            targetPerformance: goal.targetPerformance,
            targetDate: goal.targetDate?.toAPI,
            achieved: goal.achieved || (goal.kind == .race && goal.isRaceDayReached)
        )
    }
}

enum ActivityGoalCandidates {
    /// The races a session can be linked to, the one nearest its day first; undated ones last.
    /// A race already run before the session cannot be what it was raced for: it is left out,
    /// unless it is the one linked now, which must stay there to be seen and changed.
    static func ordered(_ goals: [V1Goal], around date: Date, linked: String? = nil, calendar: Calendar = .current) -> [V1Goal] {
        let day = calendar.startOfDay(for: date)
        return goals
            .filter { $0.kind == .race }
            .filter { goal in goal.id == linked || goal.targetDate.map { $0 >= day } ?? true }
            .sorted { lhs, rhs in
                switch (lhs.targetDate, rhs.targetDate) {
                case let (l?, r?): abs(l.timeIntervalSince(date)) < abs(r.timeIntervalSince(date))
                case (.some, nil): true
                case (nil, .some): false
                case (nil, nil): lhs.title < rhs.title
                }
            }
    }
}

/// « Lier à un objectif »: the athlete's races still to run, the linked one checked; a tap links
/// and closes.
struct ActivityGoalPickerSheet: View {
    let currentGoalId: String?
    let activityDate: Date
    let loadGoals: () async throws -> [V1Goal]
    let onPick: (V1Goal) -> Void

    private enum Phase { case loading, loaded([V1Goal]), failed(String) }

    @State private var phase = Phase.loading
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 6) {
                CliniqueSheetTitle(String(localized: "Lier à un objectif"))
                Text("La course pour laquelle cette séance a été courue.")
                    .font(SharpitTypography.system(size: 15, weight: .regular, relativeTo: .subheadline))
                    .foregroundStyle(SharpitColor.slate)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 24)
            .padding(.top, 30)
            .padding(.bottom, 14)
            content
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(SharpitColor.card)
        .cliniqueSheetCross { dismiss() }
        .task { await load() }
    }

    @ViewBuilder
    private var content: some View {
        switch phase {
        case .loading:
            ProgressView()
                .frame(maxWidth: .infinity)
                .padding(.top, SharpitSpacing.xl)
        case .failed(let message):
            SharpitStateMessage.failed(message) { Task { await load() } }
                .embedded()
        case .loaded(let goals) where goals.isEmpty:
            SharpitStateMessage(
                title: String(localized: "Aucune course à venir"),
                symbol: "flag.checkered",
                detail: String(localized: "Ajoute ta course dans Objectifs pour y lier cette séance.")
            )
            .embedded()
        case .loaded(let goals):
            ScrollView {
                VStack(spacing: 0) {
                    CliniqueDivider()
                    ForEach(goals) { goal in
                        Button { onPick(goal) } label: { row(goal) }
                            .buttonStyle(.sharpitPressable)
                        CliniqueDivider()
                    }
                }
                .padding(.horizontal, 24)
                .padding(.bottom, SharpitSpacing.lg)
            }
        }
    }

    private func row(_ goal: V1Goal) -> some View {
        let isLinked = goal.id == currentGoalId
        return HStack(spacing: SharpitSpacing.sm) {
            Image(systemName: "flag.checkered")
                .font(.system(size: 16, weight: .regular))
                .foregroundStyle(isLinked ? SharpitColor.primaryForeground : SharpitColor.foreground)
                .frame(width: 40, height: 40)
                .background(isLinked ? SharpitColor.primary : .clear, in: Circle())
                .overlay(Circle().strokeBorder(SharpitColor.outline, lineWidth: isLinked ? 0 : 1))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(goal.title)
                    .font(SharpitTypography.system(size: 16, weight: .semibold, relativeTo: .callout))
                    .foregroundStyle(SharpitColor.foreground)
                    .multilineTextAlignment(.leading)
                Text(GoalFormat.raceLine(goal))
                    .font(SharpitTypography.system(size: 13, weight: .regular, relativeTo: .caption, digits: true))
                    .foregroundStyle(SharpitColor.slate)
            }
            Spacer(minLength: SharpitSpacing.xs)
            if isLinked {
                Image(systemName: "checkmark")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(SharpitColor.foreground)
                    .accessibilityHidden(true)
            }
        }
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, minHeight: 56, alignment: .leading)
        .contentShape(.rect)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isLinked ? [.isButton, .isSelected] : .isButton)
    }

    private func load() async {
        phase = .loading
        do {
            phase = .loaded(ActivityGoalCandidates.ordered(try await loadGoals(), around: activityDate, linked: currentGoalId))
        } catch {
            phase = .failed(SharpitErrorGuidance.message(for: error, subject: String(localized: "Tes objectifs")))
        }
    }
}
