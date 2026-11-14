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
        String(localized: "Lecture de tes séances récentes"),
        String(localized: "Comparaison prévu et réalisé"),
        String(localized: "Lecture de ta forme"),
        String(localized: "Prise en compte des blessures"),
        String(localized: "Choix des ajustements"),
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Ajuster ton plan")
                        .font(SharpitTypography.system(size: 26, weight: .semibold, relativeTo: .title))
                        .tracking(-0.4)
                        .foregroundStyle(SharpitColor.foreground)
                        .accessibilityAddTraits(.isHeader)
                    Text(lead)
                        .font(SharpitTypography.system(size: 16, weight: .regular, relativeTo: .callout))
                        .foregroundStyle(SharpitColor.slate)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.trailing, 56)
                content
            }
            .padding(.horizontal, 24)
            .padding(.top, 34)
            .padding(.bottom, SharpitSpacing.md)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .scrollDismissesKeyboard(.interactively)
        .safeAreaInset(edge: .bottom, spacing: 0) { actions }
        .background(SharpitColor.card)
        .overlay(alignment: .topTrailing) {
            Button { dismiss() } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(SharpitColor.foreground)
                    .frame(width: 44, height: 44)
                    .background(SharpitColor.tile, in: Circle())
            }
            .buttonStyle(.sharpitPressable)
            .accessibilityLabel("Fermer")
            .padding(.trailing, 22)
            .padding(.top, 22)
        }
        .presentationDragIndicator(.visible)
        .sharpitSheet()
    }

    /// The coach's summary once it has one; before, what the sheet does.
    private var lead: String {
        switch store.phase {
        case .ready(let result, _), .applying(let result, _):
            if !result.summary.isEmpty { return result.summary }
        default: break
        }
        return String(localized: "Le coach relit ce que tu as fait ces derniers jours et propose de modifier tes séances des deux prochaines semaines, sans tout effacer.")
    }

    @ViewBuilder
    private var content: some View {
        if store.needsPro {
            SharpitProTeaser(
                title: String(localized: "Plan qui s’adapte"),
                message: String(localized: "Le coach réajuste tes séances à venir avec SharpIt Pro. Tes séances déjà au plan restent à toi.")
            )
        } else {
            phaseContent
        }
    }

    @ViewBuilder
    private var phaseContent: some View {
        switch store.phase {
        case .idle:
            request(error: nil)
        case .failed(let message):
            request(error: message)
        case .analyzing:
            VStack(alignment: .leading, spacing: SharpitSpacing.md) {
                CoachWorkingHeader(
                    readingSteps: Self.readingSteps,
                    readingDetail: String(localized: "Il part de ce que tu as vraiment fait, pas du plan seul.")
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
            SharpitFormField(
                String(localized: "Ce qui a changé (optionnel)"),
                placeholder: String(localized: "Fatigue, douleur, déplacement…"),
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
        VStack(alignment: .leading, spacing: 12) {
            if result.changes.isEmpty {
                ContentUnavailableView(
                    String(localized: "Rien à changer"),
                    systemImage: "checkmark.circle",
                    description: Text("Tes séances prévues tiennent compte de ce que tu as fait.")
                )
            } else {
                Text("Ce que je te propose")
                    .font(SharpitTypography.sectionTitle)
                    .tracking(SharpitTypography.sectionTitleTracking)
                    .foregroundStyle(SharpitColor.foreground)
                    .accessibilityAddTraits(.isHeader)
                ForEach(Array(result.changes.enumerated()), id: \.offset) { index, change in
                    AdjustmentRow(change: change, isSelected: selected.contains(index)) {
                        store.toggle(index)
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
            if !store.needsPro {
                dock {
                    Button { Task { await store.start() } } label: { Text("Proposer des ajustements").frame(maxWidth: .infinity) }
                        .buttonStyle(CliniqueButtonStyle(kind: .primary, isLarge: true))
                }
            }
        case .analyzing:
            EmptyView()
        case .ready(let result, let selected), .applying(let result, let selected):
            let busy = if case .applying = store.phase { true } else { false }
            dock {
                if result.changes.isEmpty {
                    Button {
                        store.reset()
                        dismiss()
                    } label: { Text("Terminé").frame(maxWidth: .infinity) }
                        .buttonStyle(CliniqueButtonStyle(kind: .primary, isLarge: true))
                } else {
                    Button { Task { await apply() } } label: {
                        Group {
                            if busy { ProgressView().tint(SharpitColor.primaryForeground) } else { Text(PlanAdapterReadout.apply(selected.count)) }
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(CliniqueButtonStyle(kind: .primary, isLarge: true))
                    .disabled(selected.isEmpty || busy)
                    Button("Recommencer") { store.reset() }
                        .buttonStyle(CliniqueButtonStyle(kind: .plain))
                        .disabled(busy)
                }
            }
        }
    }

    private func dock<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        VStack(spacing: 4) { content() }
            .padding(.horizontal, 24)
            .padding(.top, SharpitSpacing.xs)
            .padding(.bottom, SharpitSpacing.xs)
            .background(SharpitColor.card)
    }

    private func apply() async {
        guard let count = await store.apply() else {
            return
        }
        toastCenter?.show(
            String(localized: "\(count) modification\(count > 1 ? "s" : "") appliquée\(count > 1 ? "s" : "")"),
            symbol: "slider.horizontal.3",
            tone: .success,
            autoDismissAfter: 3.0
        )
        onPlanChanged()
        dismiss()
    }
}

/// How the adapter words its counts.
nonisolated enum PlanAdapterReadout {
    /// « Appliquer le changement », « Appliquer les 2 changements ».
    static func apply(_ count: Int) -> String {
        count == 1 ? String(localized: "Appliquer le changement") : String(localized: "Appliquer les \(count) changements")
    }
}

/// One change the coach proposes, in a bordered card: its day and what it does as a pill, the
/// session and why, then whether it is applied.
private struct AdjustmentRow: View {
    let change: V1AdaptChange
    var isSelected: Bool?
    var onToggle: () -> Void = {}

    private var day: String {
        change.date.flatMap(TrainingDayId.date)?.sharpitFormatted(.dateTime.weekday(.wide).day().month(.wide)).capitalizedFirst ?? ""
    }

    private var detail: String {
        let duration = change.durationMin.flatMap { $0 > 0 && change.action != .remove ? "\(Int($0)) min" : nil }
        return [duration, change.reason.isEmpty ? nil : change.reason].compactMap(\.self).joined(separator: " · ")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .firstTextBaseline) {
                    Text(day)
                        .font(SharpitTypography.system(size: 14, weight: .regular, relativeTo: .footnote, digits: true))
                        .foregroundStyle(SharpitColor.slate)
                    Spacer(minLength: SharpitSpacing.xs)
                    CliniqueStatusPill(change.action.verb, status: change.action == .remove ? .alert : .watch)
                }
                VStack(alignment: .leading, spacing: 3) {
                    Text(change.title ?? String(localized: "Séance prévue"))
                        .font(SharpitTypography.system(size: 17, weight: .semibold, relativeTo: .body))
                        .foregroundStyle(change.action == .remove ? SharpitColor.slate : SharpitColor.foreground)
                        .strikethrough(change.action == .remove)
                    if !detail.isEmpty {
                        Text(detail)
                            .font(SharpitTypography.system(size: 14, weight: .regular, relativeTo: .footnote, digits: true))
                            .foregroundStyle(SharpitColor.slate)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .padding(.bottom, 14)
            if let isSelected {
                CliniqueDivider()
                Button(action: onToggle) {
                    HStack {
                        Text("Appliquer ce changement")
                            .font(SharpitTypography.system(size: 16, weight: .regular, relativeTo: .callout))
                            .foregroundStyle(SharpitColor.foreground)
                        Spacer(minLength: SharpitSpacing.xs)
                        Image(systemName: isSelected ? "checkmark.square.fill" : "square")
                            .font(.system(size: 24, weight: .regular))
                            .foregroundStyle(isSelected ? SharpitColor.foreground : SharpitColor.outline)
                            .contentTransition(.symbolEffect(.replace))
                    }
                    .padding(.top, 14)
                    .contentShape(.rect)
                }
                .buttonStyle(.sharpitPressable)
                .accessibilityAddTraits(isSelected ? .isSelected : [])
            }
        }
        .cliniqueCard()
        .accessibilityElement(children: .contain)
    }
}

private extension V1AdaptAction {
    /// The change as a heading: what happens to the session.
    var verb: String {
        switch self {
        case .add: String(localized: "Ajout")
        case .modify: String(localized: "Modification")
        case .remove: String(localized: "Suppression")
        }
    }
}

private extension V1AdaptChange {
    static let placeholder = V1AdaptChange(
        action: .modify, date: "2026-01-05", type: .run, title: String(localized: "Séance en cours d'ajustement"),
        durationMin: 45, reason: String(localized: "Le coach relit ta semaine.")
    )
}
