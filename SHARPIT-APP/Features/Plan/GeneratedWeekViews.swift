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
    /// The server's safety verdict per index, when it has one.
    var verdicts: [Int: V1GateVerdict] = [:]
    var onToggle: (Int) -> Void = { _ in }

    @Environment(\.isExpertReading) private var isExpertReading
    @Namespace private var zoom
    /// The session read in full. A draft is not opened: it is still being written.
    @State private var opened: V1GeneratedSession?

    var body: some View {
        VStack(alignment: .leading, spacing: SharpitSpacing.xs) {
            ForEach(Array(sessions.enumerated()), id: \.offset) { index, session in
                row(index: index, session: session)
                    .matchedTransitionSource(id: session.id, in: zoom)
                    .onTapGesture {
                        guard !isWriting else { return }
                        SharpitHaptics.play(.light)
                        opened = session
                    }
                    .accessibilityAddTraits(isWriting ? [] : .isButton)
                    .accessibilityHint(isWriting ? "" : "Ouvre le détail de la séance")
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
        .sheet(item: $opened) { session in
            PlannedSessionDrawer(
                preview: PlannedSessionPreview(generated: session, isExpertReading: isExpertReading),
                detents: [.large],
                title: "Séance proposée",
                onDiscussWithCoach: { _ in }
            )
            .navigationTransition(.zoom(sourceID: session.id, in: zoom))
        }
    }

    @ViewBuilder
    private func row(index: Int, session: V1GeneratedSession) -> some View {
        if let verdict = verdicts[index], verdict.isRejected {
            GeneratedSessionRow(session: session, rejection: verdict.reason ?? "Écartée par le contrôle de sécurité.")
        } else if let selection {
            GeneratedSessionRow(
                session: session,
                isSelected: selection.contains(index),
                warning: verdicts[index]?.reason,
                onToggle: {
                    SharpitHaptics.play(.light)
                    onToggle(index)
                }
            )
        } else {
            GeneratedSessionRow(session: session)
        }
    }
}

/// One generated session: its day, sport, title and duration. With `isSelected`, a check says
/// whether it goes into the plan — a button of its own, since the row itself opens the session.
struct GeneratedSessionRow: View {
    let session: V1GeneratedSession
    var isSelected: Bool?
    /// A caution from the safety check, shown under the title.
    var warning: String?
    /// Why the safety check set the session aside: shown instead of a choice, the row dimmed.
    var rejection: String?
    var onToggle: () -> Void = {}

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
                if let note = rejection ?? warning {
                    Label(note, systemImage: rejection != nil ? "nosign" : "exclamationmark.triangle")
                        .font(SharpitTypography.meta)
                        .foregroundStyle(rejection != nil ? SharpitColor.signalRisk : SharpitColor.mutedForeground)
                        .lineLimit(3)
                }
            }
            Spacer(minLength: 0)
            if session.durationMin > 0 {
                Text("\(Int(session.durationMin)) min")
                    .font(SharpitTypography.instrument)
                    .foregroundStyle(SharpitColor.foreground)
            }
            if let isSelected {
                Button(action: onToggle) {
                    Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundStyle(isSelected ? SharpitColor.primary : SharpitColor.mutedForeground.opacity(0.4))
                        .contentTransition(.symbolEffect(.replace))
                        .frame(width: 44, height: 44)
                        .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .padding(.vertical, -SharpitSpacing.sm)
                .accessibilityLabel(isSelected ? "Retirer de la semaine" : "Garder dans la semaine")
            }
        }
        .padding(SharpitSpacing.sm + 2)
        .sharpitSurface(.panel)
        .opacity(isSelected == false || rejection != nil ? 0.55 : 1)
        .contentShape(.rect)
        .accessibilityElement(children: .contain)
    }
}
