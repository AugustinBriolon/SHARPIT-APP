import SwiftUI

/// The joint mobility before a session, or the stretches after it (SHARPIT ADR-114, ADR-115).
///
/// Folded to one line by default: the steps are the session, the routine its margin. A plain
/// list once opened, not the step rail — the moves are run through in any order, not a
/// sequence with targets. Once the session's day has come, the athlete says under the moves
/// whether they did it, which the coach reads beside the session's first block.
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
            Button {
                withAnimation(SharpitMotion.reveal) { isExpanded.toggle() }
            } label: {
                header
            }
            .buttonStyle(.plain)
            .accessibilityValue(isExpanded ? String(localized: "Ouvert") : String(localized: "Fermé"))
            .accessibilityHint(isExpanded ? String(localized: "Replie les mouvements") : String(localized: "Montre les mouvements"))

            if isExpanded {
                VStack(alignment: .leading, spacing: SharpitSpacing.md) {
                    moves
                    if onStatus != nil {
                        // A group carrying the question, so each button keeps its own word.
                        SharpitSegmentedChoice(
                            options: V1RoutineStatus.allCases,
                            label: \.label,
                            selection: $status,
                            allowsDeselection: true
                        )
                        .accessibilityElement(children: .contain)
                        .accessibilityLabel(String(localized: "Ce que tu en as fait"))
                    }
                }
                .padding(.top, SharpitSpacing.md)
                .transition(.opacity)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(SharpitSpacing.cardPadding)
        .sharpitSurface(.panel)
        .onChange(of: status) { _, newValue in
            onStatus?(newValue)
        }
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
            .font(SharpitTypography.bodyEmphasis)
            .foregroundStyle(SharpitColor.foreground)
    }

    private var chevron: some View {
        Image(systemName: "chevron.down")
            .font(SharpitTypography.label)
            .foregroundStyle(SharpitColor.mutedForeground)
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
            .foregroundStyle(SharpitColor.mutedForeground)
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
