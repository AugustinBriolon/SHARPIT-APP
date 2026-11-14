import SwiftUI

/// How Résumé's fold reads in Clinique terms (`docs/adr/0034`).
enum CliniqueResumeReadout {
    /// The verdict's status, from the same tone the ink plate's dot used.
    static func status(for plate: InkPlateModel) -> CliniqueStatus {
        switch PackTierTone.statusDot(for: plate.statusLabel, stateCode: plate.stateCode) {
        case .highlight: .good
        case .caution: .watch
        case .muted: .unknown
        }
    }

    static func wash(for status: CliniqueStatus) -> CliniqueWash {
        switch status {
        case .good: .good
        case .watch: .watch
        case .alert: .alert
        case .unknown, .protect, .pro: .neutral
        }
    }

    /// A score out of 100 as a ring fraction; « — » or any non-number is no data.
    static func fraction(score: String) -> Double? {
        Double(score.trimmingCharacters(in: .whitespaces)).map { $0 / 100 }
    }

    /// Days with an activity over the days of the window: the count the consistency strip drew.
    static func activeDays(_ consistency: V1TodayConsistency) -> (done: Int, of: Int) {
        (consistency.days.filter(\.hasActivity).count, consistency.days.count)
    }

    static func pillar(for key: V1TodaySignalKey) -> CliniquePillar {
        switch key {
        case .sleep: .sleep
        case .recovery: .recovery
        case .effort, .adaptation, .stress: .coach
        }
    }
}

/// Résumé in the Clinique look: the verdict as a status and a sentence on the sheet's wash,
/// the day's scores as rings, then the session and the night's proposal.
///
/// The pilot of the sweep: it draws the fold's verdict, gauges, consistency, sessions and
/// morning proposal. `TodayView` still owns the day switcher, the sheets and the other cards.
struct CliniqueResumeView: View {
    let fold: TodayFold
    let dayTitle: String
    var onAnswerProposal: (_ accept: Bool) -> Void = { _ in }

    @Environment(\.isExpertReading) private var isExpertReading

    private var status: CliniqueStatus { CliniqueResumeReadout.status(for: fold.plate) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Text(dayTitle)
                    .font(SharpitTypography.pageTitle)
                    .tracking(SharpitTypography.pageTitleTracking)
                    .foregroundStyle(SharpitColor.foreground)
                    .padding(.horizontal, SharpitSpacing.lg)
                    .padding(.top, SharpitSpacing.xs)
                hero
                scores
                if let proposal = fold.morningProposal {
                    section(String(localized: "Proposition du matin")) { proposalCard(proposal) }
                }
                section(String(localized: "Séance du jour")) { sessions }
            }
            .padding(.bottom, SharpitSpacing.xl)
        }
        .modifier(ScrollUnderGlass())
        .cliniqueSheet(wash: CliniqueResumeReadout.wash(for: status))
    }

    private var hero: some View {
        VStack(spacing: 10) {
            CliniqueStatusPill(fold.plate.statusLabel, status: status)
            if fold.plate.displaysHeadline {
                Text(fold.plate.headline)
                    .font(SharpitTypography.system(size: 24, weight: .semibold, relativeTo: .title2))
                    .foregroundStyle(SharpitColor.foreground)
                    .multilineTextAlignment(.center)
            }
            if let explanation = fold.plate.explanation(isExpert: isExpertReading) {
                Text(explanation)
                    .font(SharpitTypography.system(size: 15, weight: .regular, relativeTo: .subheadline))
                    .foregroundStyle(SharpitColor.slate)
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, SharpitSpacing.lg)
        .padding(.vertical, SharpitSpacing.lg)
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private var scores: some View {
        let consistency = fold.consistency.flatMap { $0.days.isEmpty ? nil : $0 }
        if !fold.gauges.isEmpty || consistency != nil {
            VStack(spacing: 0) {
                CliniqueDivider()
                HStack(alignment: .top, spacing: 0) {
                    ForEach(fold.gauges) { gauge in
                        score(
                            pillar: CliniqueResumeReadout.pillar(for: gauge.key),
                            fraction: CliniqueResumeReadout.fraction(score: gauge.score),
                            label: gauge.key.instrumentLabel,
                            value: gauge.score,
                            scale: "100"
                        )
                    }
                    if let consistency {
                        let days = CliniqueResumeReadout.activeDays(consistency)
                        score(
                            pillar: .coach,
                            fraction: Double(days.done) / Double(days.of),
                            label: String(localized: "Régularité"),
                            value: "\(days.done)",
                            scale: "\(days.of)"
                        )
                    }
                }
                .padding(.vertical, 18)
                CliniqueDivider()
            }
        }
    }

    private func score(pillar: CliniquePillar, fraction: Double?, label: String, value: String, scale: String) -> some View {
        VStack(spacing: 8) {
            CliniqueRing(pillar: pillar, fraction: fraction)
            Text(label)
                .font(SharpitTypography.meta)
                .foregroundStyle(SharpitColor.slate)
            if fraction != nil {
                (Text(value)
                    .font(SharpitTypography.system(size: 17, weight: .semibold, relativeTo: .body, digits: true))
                    .foregroundStyle(SharpitColor.foreground)
                    + Text(" / \(scale)").font(SharpitTypography.meta).foregroundStyle(SharpitColor.slate))
            } else {
                Text("Pas encore")
                    .font(SharpitTypography.meta)
                    .foregroundStyle(SharpitColor.slate)
            }
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
    }

    private func section(_ title: String, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(title)
                .font(SharpitTypography.sectionTitle)
                .tracking(SharpitTypography.sectionTitleTracking)
                .foregroundStyle(SharpitColor.foreground)
            content()
        }
        .padding(.horizontal, SharpitSpacing.lg)
        .padding(.top, 20)
    }

    private func proposalCard(_ proposal: V1TodayMorningProposal) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(MorningProposalReadout.change(from: proposal.from, to: proposal.to))
                    .font(SharpitTypography.system(size: 16, weight: .semibold, relativeTo: .body))
                    .foregroundStyle(SharpitColor.foreground)
                Text(proposal.why)
                    .font(SharpitTypography.meta)
                    .foregroundStyle(SharpitColor.slate)
                    .fixedSize(horizontal: false, vertical: true)
            }
            HStack(spacing: SharpitSpacing.md) {
                Button(proposal.direction == .down ? String(localized: "Alléger") : String(localized: "Augmenter")) {
                    onAnswerProposal(true)
                }
                .buttonStyle(.cliniquePrimary)
                Button("Garder le plan") { onAnswerProposal(false) }
                    .buttonStyle(.cliniquePlain)
            }
        }
        .cliniqueCard()
    }

    @ViewBuilder
    private var sessions: some View {
        if fold.sessions.isEmpty {
            Text("Pas de séance prévue")
                .font(SharpitTypography.system(size: 15, weight: .regular, relativeTo: .subheadline))
                .foregroundStyle(SharpitColor.slate)
        } else {
            VStack(spacing: 0) {
                ForEach(Array(fold.sessions.enumerated()), id: \.element.id) { index, session in
                    if index > 0 { CliniqueDivider() }
                    sessionRow(session)
                }
            }
        }
    }

    private func sessionRow(_ session: SessionCardModel) -> some View {
        HStack(spacing: 14) {
            Image(systemName: SharpitSportTone.symbolName(for: session.sport ?? ""))
                .font(.system(size: 18, weight: .regular))
                .foregroundStyle(SharpitColor.foreground)
                .frame(width: 44, height: 44)
                .background(SharpitColor.tile, in: Circle())
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                Text(session.title)
                    .font(SharpitTypography.system(size: 16, weight: .semibold, relativeTo: .body))
                    .foregroundStyle(SharpitColor.foreground)
                if let subtitle = session.subtitle {
                    Text(subtitle)
                        .font(SharpitTypography.meta)
                        .foregroundStyle(SharpitColor.slate)
                }
            }
            Spacer(minLength: SharpitSpacing.xs)
            if session.kind == .done {
                CliniqueStatusPill(String(localized: "Fait"), status: .good)
            }
        }
        .frame(minHeight: 64)
        .accessibilityElement(children: .combine)
    }
}
