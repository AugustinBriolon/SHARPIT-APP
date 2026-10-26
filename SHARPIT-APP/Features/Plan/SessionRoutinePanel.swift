import SwiftUI

/// The joint warm-up before a session, or the stretches after it (SHARPIT ADR-114).
///
/// A plain list on a panel, not the step rail: the moves are a routine to run through in
/// any order, not a sequence with targets.
struct SessionRoutinePanel: View {
    let title: String
    let routine: V1SessionRoutine

    var body: some View {
        VStack(alignment: .leading, spacing: SharpitSpacing.sm) {
            HStack(spacing: SharpitSpacing.xs) {
                SharpitEyebrow(title)
                Spacer(minLength: 0)
                if routine.isCustom {
                    SharpitInlineTag(String(localized: "Sur mesure"))
                }
                Text("~\(routine.minutes) min")
                    .font(SharpitTypography.meta)
                    .monospacedDigit()
                    .foregroundStyle(SharpitColor.mutedForeground)
            }
            VStack(alignment: .leading, spacing: SharpitSpacing.xs) {
                ForEach(routine.moves, id: \.name) { move in
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(alignment: .firstTextBaseline, spacing: SharpitSpacing.xs) {
                            Text(move.name)
                                .font(SharpitTypography.body)
                                .foregroundStyle(SharpitColor.foreground)
                            Spacer(minLength: SharpitSpacing.xs)
                            Text(move.dose)
                                .font(SharpitTypography.meta)
                                .foregroundStyle(SharpitColor.mutedForeground)
                                .multilineTextAlignment(.trailing)
                        }
                        if let cue = move.cue, !cue.isEmpty {
                            Text(cue)
                                .font(SharpitTypography.meta)
                                .foregroundStyle(SharpitColor.mutedForeground)
                        }
                    }
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityElement(children: .combine)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(SharpitSpacing.cardPadding)
        .sharpitSurface(.panel)
    }
}
