import SwiftUI

/// A week the coach is writing or has written, shared by Plan's generator and the onboarding's
/// first week: the sessions appear one by one as the server streams them, with one line saying
/// where the coach is — never its raw reasoning.
struct GeneratedWeekView: View {
    let sessions: [V1GeneratedSession]
    /// Still streaming: a line under the sessions says the coach is writing the next one.
    var isWriting = false
    /// Indices kept for the plan; nil shows the sessions without a choice.
    var selection: Set<Int>?
    var onToggle: (Int) -> Void = { _ in }

    var body: some View {
        VStack(alignment: .leading, spacing: SharpitSpacing.xs) {
            ForEach(Array(sessions.enumerated()), id: \.offset) { index, session in
                if let selection {
                    Button {
                        SharpitHaptics.play(.light)
                        onToggle(index)
                    } label: {
                        GeneratedSessionRow(session: session, isSelected: selection.contains(index))
                    }
                    .buttonStyle(.plain)
                } else {
                    GeneratedSessionRow(session: session)
                }
            }
            if isWriting {
                HStack(spacing: SharpitSpacing.xs) {
                    ProgressView().controlSize(.small)
                    Text(sessions.isEmpty ? "Le coach lit ta semaine…" : "Le coach écrit la séance suivante…")
                        .font(SharpitTypography.meta)
                        .foregroundStyle(SharpitColor.mutedForeground)
                }
                .padding(.horizontal, SharpitSpacing.xxs)
                .padding(.top, SharpitSpacing.xxs)
                .transition(.opacity)
            }
        }
        .animation(SharpitMotion.fade, value: sessions.count)
        .animation(SharpitMotion.fade, value: isWriting)
    }
}

/// One generated session: its day, sport, title and duration. With `isSelected`, a check says
/// whether it goes into the plan.
struct GeneratedSessionRow: View {
    let session: V1GeneratedSession
    var isSelected: Bool?

    private var day: String {
        guard let date = TrainingDayId.date(session.date) else { return session.date }
        return date.sharpitFormatted(.dateTime.weekday(.wide).day()).capitalized
    }

    var body: some View {
        HStack(spacing: SharpitSpacing.sm) {
            ZStack {
                Circle().fill(SharpitSportTone.label(for: session.type).opacity(0.14)).frame(width: 38, height: 38)
                Image(systemName: session.type.symbolName)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(SharpitSportTone.label(for: session.type))
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(day)
                    .font(SharpitTypography.label)
                    .tracking(SharpitTypography.labelTracking)
                    .textCase(.uppercase)
                    .foregroundStyle(SharpitColor.mutedForeground)
                Text(session.title)
                    .font(SharpitTypography.bodyEmphasis)
                    .foregroundStyle(SharpitColor.foreground)
                    .lineLimit(2)
            }
            Spacer(minLength: 0)
            if session.durationMin > 0 {
                Text("\(Int(session.durationMin)) min")
                    .font(SharpitTypography.instrument)
                    .foregroundStyle(SharpitColor.foreground)
            }
            if let isSelected {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(isSelected ? SharpitColor.primary : SharpitColor.mutedForeground.opacity(0.4))
                    .contentTransition(.symbolEffect(.replace))
            }
        }
        .padding(SharpitSpacing.sm + 2)
        .sharpitSurface(.panel)
        .opacity(isSelected == false ? 0.55 : 1)
        .contentShape(.rect)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isSelected == true ? .isSelected : [])
    }
}
