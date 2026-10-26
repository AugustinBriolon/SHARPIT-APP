import SwiftUI

/// The joint mobility before a session, or the stretches after it (SHARPIT ADR-114).
///
/// Folded to one line by default: the steps are the session, the routine its margin. A plain
/// list once opened, not the step rail — the moves are run through in any order, not a
/// sequence with targets.
struct SessionRoutinePanel: View {
    let title: String
    let routine: V1SessionRoutine
    @State private var isExpanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(SharpitMotion.reveal) { isExpanded.toggle() }
            } label: {
                header
            }
            .buttonStyle(.plain)
            .accessibilityValue(isExpanded ? String(localized: "Ouvert") : String(localized: "Fermé"))
            .accessibilityHint(isExpanded ? String(localized: "Replie les mouvements") : String(localized: "Montre les mouvements"))

            if isExpanded {
                moves
                    .padding(.top, SharpitSpacing.md)
                    .transition(.opacity)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(SharpitSpacing.cardPadding)
        .sharpitSurface(.panel)
    }

    private var header: some View {
        HStack(spacing: SharpitSpacing.sm) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(SharpitTypography.bodyEmphasis)
                    .foregroundStyle(SharpitColor.foreground)
                Text("^[\(routine.moves.count) mouvement](inflect: true) · ~\(routine.minutes) min")
                    .font(SharpitTypography.meta)
                    .monospacedDigit()
                    .foregroundStyle(SharpitColor.mutedForeground)
            }
            Spacer(minLength: 0)
            if routine.isCustom {
                SharpitInlineTag(String(localized: "Sur mesure"))
            }
            Image(systemName: "chevron.down")
                .font(SharpitTypography.label)
                .foregroundStyle(SharpitColor.mutedForeground)
                .rotationEffect(.degrees(isExpanded ? 180 : 0))
                .accessibilityHidden(true)
        }
        .frame(minHeight: 44)
        .contentShape(.rect)
    }

    /// The name on its own line, the dose and the cue under it: a long French name no longer
    /// wraps beside a dose pinned to the right.
    private var moves: some View {
        VStack(alignment: .leading, spacing: SharpitSpacing.sm) {
            ForEach(routine.moves, id: \.name) { move in
                VStack(alignment: .leading, spacing: 2) {
                    Text(move.name)
                        .font(SharpitTypography.body)
                        .foregroundStyle(SharpitColor.foreground)
                    doseLine(move)
                        .font(SharpitTypography.meta)
                }
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityElement(children: .combine)
            }
        }
    }

    private func doseLine(_ move: V1RoutineMove) -> Text {
        let dose = Text(move.dose).foregroundStyle(SharpitColor.foreground)
        guard let cue = move.cue, !cue.isEmpty else { return dose }
        return dose + Text(" · \(cue)").foregroundStyle(SharpitColor.mutedForeground)
    }
}
