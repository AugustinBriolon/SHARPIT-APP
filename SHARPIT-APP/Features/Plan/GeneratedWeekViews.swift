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
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(sessions.enumerated()), id: \.offset) { index, session in
                CliniqueDivider()
                row(index: index, session: session)
                    .onTapGesture {
                        guard !isWriting else { return }
                        opened = session
                    }
                    .accessibilityAddTraits(isWriting ? [] : .isButton)
                    .accessibilityHint(isWriting ? "" : String(localized: "Ouvre le détail de la séance"))
            }
        }
        .animation(SharpitMotion.fade, value: sessions.count)
        .modifier(ProposedSessionPresenter(opened: $opened, opening: opening))
    }

    @ViewBuilder
    private func row(index: Int, session: V1GeneratedSession) -> some View {
        if let verdict = verdicts[index], verdict.isRejected {
            GeneratedSessionRow(session: session, rejection: verdict.reason ?? String(localized: "Écartée par le contrôle de sécurité."))
        } else if let selection {
            GeneratedSessionRow(
                session: session,
                isSelected: selection.contains(index),
                warning: verdicts[index]?.reason,
                onToggle: {
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
        String(localized: "Analyse de ton profil"),
        String(localized: "Lecture de ta charge"),
        String(localized: "Lecture de ta récupération"),
        String(localized: "Prise en compte des blessures"),
        String(localized: "Lecture de ton agenda"),
        String(localized: "Choix des séances clés"),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: SharpitSpacing.md) {
            CoachWorkingHeader(
                readingSteps: Self.readingSteps,
                readingDetail: String(localized: "Le coach part de tes données, pas d'un modèle type."),
                writingTitle: drafts.isEmpty ? nil : String(localized: "Rédaction des séances"),
                writingDetail: drafts.isEmpty
                    ? nil
                    : String(localized: "\(drafts.count) séance\(drafts.count > 1 ? "s" : "") écrite\(drafts.count > 1 ? "s" : ""), la suite arrive."),
                note: note
            )

            VStack(alignment: .leading, spacing: 0) {
                GeneratedWeekView(sessions: drafts, isWriting: true)
                ForEach(0..<(drafts.isEmpty ? 3 : 1), id: \.self) { index in
                    CliniqueDivider()
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
        date: "2026-01-05", type: .run, intensity: "ENDURANCE", title: String(localized: "Séance en cours d'écriture"),
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

/// One generated session as a line: its day, « Sport · Titre » over its length and load, and at
/// the trailing edge « Clé » or its length. With `isSelected`, a check says whether it goes into
/// the plan — a button of its own, since the line itself opens the session.
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
        return date.sharpitFormatted(.dateTime.weekday(.abbreviated)).capitalizedFirst
    }

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Text(day)
                .font(SharpitTypography.system(size: 14, weight: session.isKey ? .semibold : .regular, relativeTo: .footnote))
                .foregroundStyle(session.isKey ? SharpitColor.foreground : SharpitColor.slate)
                .frame(width: 44, alignment: .leading)
            VStack(alignment: .leading, spacing: 2) {
                Text(PlannedSessionReadout.title(sport: session.type.label, title: session.title))
                    .font(SharpitTypography.system(size: 16, weight: .semibold, relativeTo: .callout, digits: true))
                    .foregroundStyle(SharpitColor.foreground)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                Text(GeneratedWeekReadout.detail(session))
                    .font(SharpitTypography.system(size: 14, weight: .regular, relativeTo: .footnote, digits: true))
                    .foregroundStyle(SharpitColor.slate)
                if let note = rejection ?? warning {
                    Text(note)
                        .font(SharpitTypography.system(size: 13, weight: .regular, relativeTo: .footnote))
                        .foregroundStyle(rejection != nil ? SharpitColor.statusAlertMark : SharpitColor.slate)
                        .lineLimit(3)
                }
            }
            Spacer(minLength: 0)
            if session.isKey {
                CliniqueStatusPill(String(localized: "Clé"), status: .pro)
            }
            if let isSelected {
                Button(action: onToggle) {
                    Image(systemName: isSelected ? "checkmark.square.fill" : "square")
                        .font(.system(size: 24, weight: .regular))
                        .foregroundStyle(isSelected ? SharpitColor.foreground : SharpitColor.outline)
                        .contentTransition(.symbolEffect(.replace))
                        .frame(width: 44, height: 44)
                        .contentShape(.rect)
                }
                .buttonStyle(.sharpitPressable)
                .accessibilityLabel(isSelected ? String(localized: "Gardée") : String(localized: "Écartée"))
                .accessibilityAddTraits(isSelected ? .isSelected : [])
            }
        }
        .padding(.vertical, 12)
        .opacity(isSelected == false || rejection != nil ? 0.55 : 1)
        .contentShape(.rect)
        .accessibilityElement(children: .contain)
    }
}

/// How a generated week words its lines and its total.
nonisolated enum GeneratedWeekReadout {
    /// « 55 min · charge 68 »; the length alone without a load.
    static func detail(_ session: V1GeneratedSession) -> String {
        [session.durationMin > 0 ? duration(session.durationMin) : nil,
         session.load > 0 ? String(localized: "charge \(Int(session.load.rounded()))") : nil]
            .compactMap(\.self).joined(separator: " · ")
    }

    /// « 6 séances · 7 h 40 · charge 435 ».
    static func total(_ sessions: [V1GeneratedSession]) -> String {
        let count = sessions.count == 1 ? String(localized: "1 séance") : String(localized: "\(sessions.count) séances")
        let minutes = sessions.reduce(0) { $0 + $1.durationMin }
        let load = sessions.reduce(0) { $0 + $1.load }
        return [count, minutes > 0 ? duration(minutes) : nil, load > 0 ? String(localized: "charge \(Int(load.rounded()))") : nil]
            .compactMap(\.self).joined(separator: " · ")
    }

    /// « Ajouter à mon plan », or how many when some were set aside.
    static func add(_ count: Int) -> String {
        count == 1 ? String(localized: "Ajouter 1 séance") : String(localized: "Ajouter \(count) séances")
    }

    /// « 45 min », « 1 h 30 », « 2 h ».
    static func duration(_ minutes: Double) -> String {
        let whole = Int(minutes.rounded())
        if whole < 60 { return "\(whole) min" }
        return whole % 60 == 0 ? "\(whole / 60) h" : "\(whole / 60) h \(String(format: "%02d", whole % 60))"
    }

    /// « Semaine du 17 novembre », from the first session's day; nil when it cannot be read.
    @MainActor static func title(_ sessions: [V1GeneratedSession], locale: Locale = SharpitLocale.current) -> String? {
        guard let first = sessions.compactMap({ TrainingDayId.date($0.date) }).min() else { return nil }
        return String(localized: "Semaine du \(first.formatted(.dateTime.day().month(.wide).locale(locale)))")
    }
}
