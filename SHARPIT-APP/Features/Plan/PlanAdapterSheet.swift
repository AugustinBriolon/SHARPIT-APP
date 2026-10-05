import SwiftUI

/// Plan's « Ajuster le planning »: what changed for the athlete, then the coach's proposed
/// changes to the next two weeks, then the ones to apply. Laid out as « Remplir ma semaine » —
/// same wait, same rows, same docked actions — because it is the same conversation with the
/// coach about the same plan. The store is Plan's, so closing mid-analysis loses nothing.
struct PlanAdapterSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(SharpitToastCenter.self) private var toastCenter: SharpitToastCenter?
    @Bindable var store: PlanAdjustmentStore
    var onPlanChanged: () -> Void = {}

    /// What the coach reads before proposing anything, in order.
    static let readingSteps = [
        "Lecture de tes séances récentes",
        "Comparaison prévu et réalisé",
        "Lecture de ta forme",
        "Prise en compte des blessures",
        "Choix des ajustements",
    ]

    var body: some View {
        NavigationStack {
            ScrollView {
                content
                    .padding(.horizontal, SharpitSpacing.pageInset)
                    .padding(.vertical, SharpitSpacing.md)
            }
            .scrollDismissesKeyboard(.interactively)
            .safeAreaInset(edge: .bottom, spacing: 0) { actions }
            .background(SharpitCanvasBackground())
            .navigationTitle("Ajuster le planning")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Fermer") { dismiss() }
                }
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        switch store.phase {
        case .idle:
            request(error: nil)
        case .failed(let message):
            request(error: message)
        case .analyzing:
            VStack(alignment: .leading, spacing: SharpitSpacing.md) {
                CoachWorkingHeader(
                    readingSteps: Self.readingSteps,
                    readingDetail: "Il part de ce que tu as vraiment fait, pas du plan seul."
                )
                VStack(spacing: SharpitSpacing.xs) {
                    ForEach(0..<3, id: \.self) { index in
                        AdjustmentRow(change: .placeholder)
                            .redacted(reason: .placeholder)
                            .sharpitPlaceholderPulse(index: index)
                    }
                }
            }
        case .ready(let result, let selected), .applying(let result, let selected):
            proposal(result: result, selected: selected)
        }
    }

    private func request(error: String?) -> some View {
        VStack(alignment: .leading, spacing: SharpitSpacing.md) {
            Text("Le coach relit ce que tu as fait ces derniers jours et propose de modifier tes séances des deux prochaines semaines, sans tout effacer.")
                .font(SharpitTypography.meta)
                .foregroundStyle(SharpitColor.mutedForeground)
                .fixedSize(horizontal: false, vertical: true)
            SharpitFormField(
                "Ce qui a changé (optionnel)",
                placeholder: "Fatigue, douleur, déplacement…",
                text: $store.focus
            )
            if let error {
                Label(error, systemImage: "exclamationmark.triangle")
                    .font(SharpitTypography.meta)
                    .foregroundStyle(SharpitColor.signalRisk)
            }
        }
    }

    private func proposal(result: V1AdaptPlanResult, selected: Set<Int>) -> some View {
        VStack(alignment: .leading, spacing: SharpitSpacing.sm) {
            if !result.summary.isEmpty {
                Text(result.summary)
                    .font(SharpitTypography.body)
                    .foregroundStyle(SharpitColor.foreground)
                    .lineLimit(3)
            }
            if result.changes.isEmpty {
                ContentUnavailableView(
                    "Rien à changer",
                    systemImage: "checkmark.circle",
                    description: Text("Tes séances prévues tiennent compte de ce que tu as fait.")
                )
            } else {
                VStack(spacing: SharpitSpacing.xs) {
                    ForEach(Array(result.changes.enumerated()), id: \.offset) { index, change in
                        AdjustmentRow(change: change, isSelected: selected.contains(index)) {
                            store.toggle(index)
                        }
                    }
                }
            }
            if let applyError = store.applyError {
                Label(applyError, systemImage: "exclamationmark.triangle")
                    .font(SharpitTypography.meta)
                    .foregroundStyle(SharpitColor.signalRisk)
            }
        }
    }

    @ViewBuilder
    private var actions: some View {
        switch store.phase {
        case .idle, .failed:
            SharpitActionDock {
                SharpitPrimaryButton(title: "Proposer des ajustements") {
                    Task { await store.start() }
                }
            }
        case .analyzing:
            EmptyView()
        case .ready(let result, let selected), .applying(let result, let selected):
            let busy = if case .applying = store.phase { true } else { false }
            SharpitActionDock {
                if result.changes.isEmpty {
                    SharpitPrimaryButton(title: "Terminé") {
                        store.reset()
                        dismiss()
                    }
                } else {
                    SharpitPrimaryButton(
                        title: busy ? "Application…" : "Appliquer \(selected.count) modification\(selected.count > 1 ? "s" : "")",
                        isBusy: busy
                    ) {
                        Task { await apply() }
                    }
                    .disabled(selected.isEmpty || busy)
                    Button("Recommencer") { store.reset() }
                        .font(SharpitTypography.bodyEmphasis)
                        .foregroundStyle(SharpitColor.mutedForeground)
                        .disabled(busy)
                }
            }
        }
    }

    private func apply() async {
        guard let count = await store.apply() else {
            return
        }
        toastCenter?.show(
            "\(count) modification\(count > 1 ? "s" : "") appliquée\(count > 1 ? "s" : "")",
            symbol: "slider.horizontal.3",
            tone: .success,
            autoDismissAfter: 3.0
        )
        onPlanChanged()
        dismiss()
    }
}

/// One change the coach proposes: what it does and to which day, the session, why — and whether
/// it is kept. The same shape as a generated session's row.
private struct AdjustmentRow: View {
    let change: V1AdaptChange
    var isSelected: Bool?
    var onToggle: () -> Void = {}

    private var heading: String {
        guard let date = change.date.flatMap(TrainingDayId.date) else { return change.action.verb }
        return "\(change.action.verb) · \(date.sharpitFormatted(.dateTime.weekday(.wide).day()))"
    }

    var body: some View {
        HStack(alignment: .top, spacing: SharpitSpacing.sm) {
            SharpitSportBadge(type: change.type ?? .other)
            VStack(alignment: .leading, spacing: 2) {
                Text(heading)
                    .font(SharpitTypography.label)
                    .tracking(SharpitTypography.labelTracking)
                    .textCase(.uppercase)
                    .foregroundStyle(change.action == .remove ? SharpitColor.signalRisk : SharpitColor.mutedForeground)
                Text(change.title ?? "Séance prévue")
                    .font(SharpitTypography.bodyEmphasis)
                    .foregroundStyle(SharpitColor.foreground)
                    .strikethrough(change.action == .remove)
                    .lineLimit(2)
                if !change.reason.isEmpty {
                    Text(change.reason)
                        .font(SharpitTypography.meta)
                        .foregroundStyle(SharpitColor.mutedForeground)
                        .lineLimit(3)
                }
            }
            Spacer(minLength: 0)
            if let duration = change.durationMin, duration > 0, change.action != .remove {
                Text("\(Int(duration)) min")
                    .font(SharpitTypography.instrument)
                    .foregroundStyle(SharpitColor.foreground)
            }
            if let isSelected {
                SharpitKeepToggle(isSelected: isSelected, action: onToggle)
            }
        }
        .padding(SharpitSpacing.sm + 2)
        .sharpitSurface(.panel)
        .opacity(isSelected == false ? 0.55 : 1)
        .accessibilityElement(children: .contain)
    }
}

private extension V1AdaptAction {
    /// The change as a heading: what happens to the session.
    var verb: String {
        switch self {
        case .add: "Ajout"
        case .modify: "Modification"
        case .remove: "Suppression"
        }
    }
}

private extension V1AdaptChange {
    static let placeholder = V1AdaptChange(
        action: .modify, date: "2026-01-05", type: .run, title: "Séance en cours d'ajustement",
        durationMin: 45, reason: "Le coach relit ta semaine."
    )
}
