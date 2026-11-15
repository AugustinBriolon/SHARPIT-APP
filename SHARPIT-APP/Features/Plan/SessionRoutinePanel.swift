import SwiftUI

/// The joint mobility before a session, or the stretches after it (SHARPIT ADR-114, ADR-115).
///
/// Folded to one line by default: the steps are the session, the routine its margin. A plain
/// list once opened, not the step rail — the moves are run through in any order, not a
/// sequence with targets. Once the session's day has come, the athlete says right under the
/// line whether they did it, which the coach reads beside the session's first block.
struct SessionRoutinePanel: View {
    let title: String
    let routine: V1SessionRoutine
    /// Records what the athlete did with it; nil where it cannot be said (a day ahead, a
    /// surface that cannot write).
    var onStatus: ((V1RoutineStatus?) -> Void)?
    @State private var isExpanded: Bool
    @State private var status: V1RoutineStatus?
    @Environment(\.dynamicTypeSize) private var typeSize

    /// `isExpanded` opens it from the start: a snapshot or a demo showing the moves.
    init(
        title: String,
        routine: V1SessionRoutine,
        onStatus: ((V1RoutineStatus?) -> Void)? = nil,
        isExpanded: Bool = false
    ) {
        self.title = title
        self.routine = routine
        self.onStatus = onStatus
        _isExpanded = State(initialValue: isExpanded)
        _status = State(initialValue: routine.routineStatus)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            CliniqueDivider()
            Button {
                withAnimation(SharpitMotion.reveal) { isExpanded.toggle() }
            } label: {
                header
            }
            .buttonStyle(.sharpitPressable)
            .accessibilityValue(isExpanded ? String(localized: "Ouvert") : String(localized: "Fermé"))
            .accessibilityHint(isExpanded ? String(localized: "Replie les mouvements") : String(localized: "Montre les mouvements"))

            // Said at the line, not behind it: where the session can be answered, so can this.
            if onStatus != nil {
                statusChoice
                    .padding(.bottom, SharpitSpacing.sm)
            }

            if isExpanded {
                moves
                    .padding(.bottom, SharpitSpacing.sm)
                    .transition(.opacity)
            }
            CliniqueDivider()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .onChange(of: status) { _, newValue in
            onStatus?(newValue)
        }
    }

    /// « Fait · Raccourci · Sauté », each a chip of its own; a second tap takes the answer back.
    private var statusChoice: some View {
        HStack(spacing: 8) {
            ForEach(V1RoutineStatus.allCases, id: \.self) { option in
                let isChosen = status == option
                Button {
                    SharpitMotion.run(SharpitMotion.selection) { status = isChosen ? nil : option }
                } label: {
                    Text(option.label)
                        .font(SharpitTypography.system(size: 14, weight: .semibold, relativeTo: .footnote))
                        .foregroundStyle(isChosen ? SharpitColor.primaryForeground : SharpitColor.foreground)
                        .padding(.horizontal, 14)
                        .frame(minHeight: 36)
                        .background(isChosen ? SharpitColor.primary : .clear, in: Capsule())
                        .overlay(Capsule().strokeBorder(isChosen ? .clear : SharpitColor.outline, lineWidth: 1))
                        .contentShape(Capsule())
                }
                .buttonStyle(.sharpitPressable)
                .accessibilityAddTraits(isChosen ? [.isButton, .isSelected] : .isButton)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(String(localized: "Ce que tu en as fait"))
    }

    /// Title and figures beside the chevron; at the accessibility sizes the chevron keeps to the
    /// title's line and the figures and tags take the full width, where side by side they broke
    /// mid-phrase.
    private var header: some View {
        VStack(alignment: .leading, spacing: SharpitSpacing.xxs) {
            if typeSize.isAccessibilitySize {
                HStack(alignment: .firstTextBaseline, spacing: SharpitSpacing.sm) {
                    titleText
                    Spacer(minLength: 0)
                    chevron
                }
                summaryLine
            } else {
                HStack(spacing: SharpitSpacing.sm) {
                    VStack(alignment: .leading, spacing: 2) {
                        titleText
                        summaryLine
                    }
                    Spacer(minLength: 0)
                    chevron
                }
            }
            tags
        }
        .frame(minHeight: 44)
        .contentShape(.rect)
    }

    private var titleText: some View {
        Text(title)
            .font(SharpitTypography.system(size: 16, weight: .semibold, relativeTo: .callout))
            .foregroundStyle(SharpitColor.foreground)
    }

    private var chevron: some View {
        Image(systemName: "chevron.down")
            .font(SharpitTypography.label)
            .foregroundStyle(SharpitColor.slate)
            .rotationEffect(.degrees(isExpanded ? 180 : 0))
            .accessibilityHidden(true)
    }

    /// Both can hold: stretches the coach wrote are still optional.
    @ViewBuilder
    private var tags: some View {
        if routine.isCustom || routine.isOptional {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: SharpitSpacing.xs) { tagViews }
                VStack(alignment: .leading, spacing: SharpitSpacing.xs) { tagViews }
            }
            .padding(.top, SharpitSpacing.xxs)
        }
    }

    @ViewBuilder
    private var tagViews: some View {
        if routine.isCustom {
            SharpitInlineTag(String(localized: "Sur mesure"))
        }
        if routine.isOptional {
            SharpitInlineTag(String(localized: "Facultatif"))
        }
    }

    private var summaryLine: Text {
        let base = Text("^[\(routine.moves.count) mouvement](inflect: true) · ~\(routine.minutes) min")
        let line = status.map { base + Text(verbatim: " · \($0.label)") } ?? base
        return line
            .font(SharpitTypography.meta)
            .monospacedDigit()
            .foregroundStyle(SharpitColor.slate)
    }

    /// The name on its own line, the dose and the cue under it, each move a line split by a
    /// hairline: a long French name no longer wraps beside a dose pinned to the right.
    private var moves: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(routine.moves.enumerated()), id: \.offset) { index, move in
                if index > 0 { CliniqueDivider() }
                VStack(alignment: .leading, spacing: 2) {
                    Text(move.name)
                        .font(SharpitTypography.system(size: 15, weight: .regular, relativeTo: .body))
                        .foregroundStyle(SharpitColor.foreground)
                    doseLine(move)
                        .font(SharpitTypography.system(size: 13, weight: .regular, relativeTo: .footnote, digits: true))
                }
                .padding(.vertical, 10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityElement(children: .combine)
            }
        }
        .padding(.leading, 12)
    }

    private func doseLine(_ move: V1RoutineMove) -> Text {
        let dose = Text(move.dose).foregroundStyle(SharpitColor.foreground)
        guard let cue = move.cue, !cue.isEmpty else { return dose }
        return dose + Text(" · \(cue)").foregroundStyle(SharpitColor.slate)
    }
}
