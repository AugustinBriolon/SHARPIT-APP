import SwiftUI

extension V1ActivityGoal {
    /// The link as the session page shows it before the server answers.
    init(goal: V1Goal) {
        self.init(
            id: goal.id,
            title: goal.title,
            raceFormat: goal.raceFormat,
            targetPerformance: goal.targetPerformance,
            targetDate: goal.targetDate?.toAPI
        )
    }
}

enum ActivityGoalCandidates {
    /// The races a session can be linked to, the one nearest its day first; undated ones last.
    static func ordered(_ goals: [V1Goal], around date: Date) -> [V1Goal] {
        goals
            .filter { $0.kind == .race }
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

/// « Lier à un objectif »: the athlete's races, the linked one checked; a tap links and closes.
struct ActivityGoalPickerSheet: View {
    let currentGoalId: String?
    let activityDate: Date
    let loadGoals: () async throws -> [V1Goal]
    let onPick: (V1Goal) -> Void

    private enum Phase { case loading, loaded([V1Goal]), failed }

    @State private var phase = Phase.loading
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            content
                .navigationTitle("Lier à un objectif")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Annuler") { dismiss() }
                    }
                }
        }
        .task { await load() }
    }

    @ViewBuilder
    private var content: some View {
        switch phase {
        case .loading:
            ProgressView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .failed:
            SharpitStateMessage(
                title: "Objectifs indisponibles",
                symbol: "wifi.slash",
                detail: "Vérifie ta connexion, puis réessaie.",
                retry: { Task { await load() } }
            )
        case .loaded(let goals) where goals.isEmpty:
            SharpitStateMessage(
                title: "Aucune course",
                symbol: "flag.checkered",
                detail: "Ajoute ta course dans Objectifs pour y lier cette séance."
            )
        case .loaded(let goals):
            List(goals) { goal in
                Button { onPick(goal) } label: { row(goal) }
                    .buttonStyle(.plain)
            }
            .scrollContentBackground(.hidden)
        }
    }

    private func row(_ goal: V1Goal) -> some View {
        HStack(spacing: SharpitSpacing.sm) {
            VStack(alignment: .leading, spacing: 3) {
                Text(goal.title)
                    .font(SharpitTypography.bodyEmphasis)
                    .foregroundStyle(SharpitColor.foreground)
                Text(GoalFormat.raceLine(goal))
                    .font(SharpitTypography.meta)
                    .foregroundStyle(SharpitColor.mutedForeground)
            }
            Spacer(minLength: SharpitSpacing.xs)
            if goal.id == currentGoalId {
                Image(systemName: "checkmark")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(SharpitColor.primary)
            }
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(goal.id == currentGoalId ? [.isButton, .isSelected] : .isButton)
    }

    private func load() async {
        phase = .loading
        do {
            phase = .loaded(ActivityGoalCandidates.ordered(try await loadGoals(), around: activityDate))
        } catch {
            phase = .failed
        }
    }
}
