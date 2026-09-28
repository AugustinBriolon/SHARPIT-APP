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
                    SharpitHaptics.play(.soft)
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

    /// What the coach goes through before the first session, in the order it reads it.
    static let readingSteps = [
        "Analyse de ton profil",
        "Lecture de ta charge",
        "Lecture de ta récupération",
        "Prise en compte des blessures",
        "Lecture de ton agenda",
        "Choix des séances clés",
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: SharpitSpacing.md) {
            CoachWorkingHeader(
                readingSteps: Self.readingSteps,
                readingDetail: "Le coach part de tes données, pas d'un modèle type.",
                writingTitle: drafts.isEmpty ? nil : "Rédaction des séances",
                writingDetail: drafts.isEmpty
                    ? nil
                    : "\(drafts.count) séance\(drafts.count > 1 ? "s" : "") écrite\(drafts.count > 1 ? "s" : ""), la suite arrive.",
                note: note
            )

            VStack(alignment: .leading, spacing: SharpitSpacing.xs) {
                GeneratedWeekView(sessions: drafts, isWriting: true)
                ForEach(0..<(drafts.isEmpty ? 3 : 1), id: \.self) { index in
                    GeneratedSessionRow(session: .placeholder)
                        .redacted(reason: .placeholder)
                        .sharpitPlaceholderPulse(index: index)
                }
            }
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
            SharpitSportBadge(type: session.type)
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
                SharpitKeepToggle(isSelected: isSelected, action: onToggle)
            }
        }
        .padding(SharpitSpacing.sm + 2)
        .sharpitSurface(.panel)
        .opacity(isSelected == false || rejection != nil ? 0.55 : 1)
        .contentShape(.rect)
        .accessibilityElement(children: .contain)
    }
}
