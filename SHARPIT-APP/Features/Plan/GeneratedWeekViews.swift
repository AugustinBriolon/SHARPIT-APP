import SwiftUI

/// A week the coach has written, or the part of it written so far — shared by Plan's generator
/// and the onboarding's first week.
struct GeneratedWeekView: View {
    let sessions: [V1GeneratedSession]
    /// Still streaming: the sessions are shown but not opened, they are being written.
    var isWriting = false
    /// Indices kept for the plan; nil shows the sessions without a choice.
    var selection: Set<Int>?
    /// The server's safety verdict per index, when it has one.
    var verdicts: [Int: V1GateVerdict] = [:]
    var onToggle: (Int) -> Void = { _ in }
    /// Inside a sheet the session is pushed, never a second sheet on top (HIG: one sheet at a
    /// time); the onboarding, which is not a sheet, presents it as one.
    var opening: ProposedSessionOpening = .sheet

    /// The session read in full. A draft is not opened: it is still being written.
    @State private var opened: V1GeneratedSession?

    var body: some View {
        VStack(alignment: .leading, spacing: SharpitSpacing.xs) {
            ForEach(Array(sessions.enumerated()), id: \.offset) { index, session in
                row(index: index, session: session)
                    .onTapGesture {
                        guard !isWriting else { return }
                        SharpitHaptics.play(.light)
                        opened = session
                    }
                    .accessibilityAddTraits(isWriting ? [] : .isButton)
                    .accessibilityHint(isWriting ? "" : "Ouvre le détail de la séance")
            }
        }
        .animation(SharpitMotion.fade, value: sessions.count)
        .modifier(ProposedSessionPresenter(opened: $opened, opening: opening))
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

/// The wait while the coach writes a week: where it is, the sessions as they arrive, and the
/// rows still to come as placeholders — the shape of the result before the result. Never the
/// model's raw reasoning.
struct GeneratingWeekView: View {
    let drafts: [V1GeneratedSession]
    /// Under the stage line, e.g. that the sheet can close.
    var note: String?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// Which line of the reading stage is shown; it moves on while nothing is written yet.
    @State private var readingStep = 0

    /// What the coach goes through before the first session, in the order it reads it.
    static let readingSteps = [
        "Analyse de ton profil",
        "Lecture de ta charge et de ta récupération",
        "Prise en compte de tes blessures",
        "Lecture de ton agenda",
        "Choix des séances clés",
    ]

    private var stage: (title: String, detail: String) {
        if drafts.isEmpty {
            return (Self.readingSteps[readingStep], "Le coach part de tes données, pas d'un modèle type.")
        }
        let count = drafts.count
        return ("Rédaction des séances", "\(count) séance\(count > 1 ? "s" : "") écrite\(count > 1 ? "s" : ""), la suite arrive.")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: SharpitSpacing.md) {
            HStack(alignment: .top, spacing: SharpitSpacing.sm) {
                ProgressView()
                    .controlSize(.regular)
                    .padding(.top, 2)
                VStack(alignment: .leading, spacing: SharpitSpacing.xxs) {
                    Text(stage.title)
                        .font(SharpitTypography.sectionTitle)
                        .foregroundStyle(SharpitColor.foreground)
                        .id(stage.title)
                        .transition(reduceMotion ? .opacity : .push(from: .bottom).combined(with: .opacity))
                    Text(stage.detail)
                        .font(SharpitTypography.meta)
                        .foregroundStyle(SharpitColor.mutedForeground)
                        .contentTransition(.numericText())
                    if let note {
                        Text(note)
                            .font(SharpitTypography.meta)
                            .foregroundStyle(SharpitColor.mutedForeground)
                    }
                }
            }
            .accessibilityElement(children: .combine)
            .animation(SharpitMotion.fade, value: drafts.count)
            .animation(SharpitMotion.reveal, value: stage.title)
            .clipped()

            VStack(alignment: .leading, spacing: SharpitSpacing.xs) {
                GeneratedWeekView(sessions: drafts, isWriting: true)
                ForEach(0..<(drafts.isEmpty ? 3 : 1), id: \.self) { index in
                    GeneratedSessionRow(session: .placeholder)
                        .redacted(reason: .placeholder)
                        .phaseAnimator(reduceMotion ? [1.0] : [1.0, 0.45]) { row, opacity in
                            row.opacity(opacity)
                        } animation: { _ in
                            .easeInOut(duration: 0.9).delay(Double(index) * 0.15)
                        }
                        .accessibilityHidden(true)
                }
            }
        }
        .task(id: drafts.isEmpty) { await advanceReadingSteps() }
    }

    /// Moves through the reading lines until the first session arrives, stopping on the last.
    private func advanceReadingSteps() async {
        while drafts.isEmpty, readingStep < Self.readingSteps.count - 1 {
            try? await Task.sleep(for: .seconds(3))
            guard !Task.isCancelled, drafts.isEmpty else { return }
            readingStep += 1
        }
    }
}

private extension V1GeneratedSession {
    static let placeholder = V1GeneratedSession(
        date: "2026-01-05", type: .run, intensity: "ENDURANCE", title: "Séance en cours d'écriture",
        description: "", durationMin: 45, load: 0
    )
}

enum ProposedSessionOpening {
    /// Pushed on the enclosing `NavigationStack`.
    case push
    /// In a sheet of its own.
    case sheet
}

/// Opens the session read in full with the system's own transitions: a push slides in from the
/// side inside a sheet, a sheet rises from the bottom. A zoom from the row was tried and read as
/// the whole sheet vanishing and another appearing — inside a sheet it has no card to grow from.
private struct ProposedSessionPresenter: ViewModifier {
    @Binding var opened: V1GeneratedSession?
    let opening: ProposedSessionOpening

    func body(content: Content) -> some View {
        switch opening {
        case .push:
            content.navigationDestination(item: $opened) { session in
                ProposedSessionPage(session: session)
            }
        case .sheet:
            content.sheet(item: $opened) { session in
                NavigationStack {
                    ProposedSessionPage(session: session)
                        .toolbar {
                            ToolbarItem(placement: .confirmationAction) {
                                Button("Fermer") { opened = nil }
                            }
                        }
                }
                .sharpitSheet()
            }
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
