import SwiftUI

/// Journal → Analyses: what the athlete's habits go with, as the web's `/journal/analyses` read
/// it — the one lever worth knowing on the ink plate, then the associations that help, those that
/// weigh, and the leads still to confirm. Each one is a dumbbell: the median night without the
/// habit, the median with it, every day behind them.
///
/// Closed until enough days are noted, and honest about it: an association is not a cause.
struct JournalAnalysesView: View {
    let store: JournalAnalysesStore

    var body: some View {
        ScrollView {
            content
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(SharpitSpacing.pageInset)
                .padding(.bottom, SharpitSpacing.section)
        }
        .scrollIndicators(.hidden)
        .background(SharpitCanvasBackground())
        .navigationTitle("Analyses")
        .navigationBarTitleDisplayMode(.inline)
        .task { await store.load() }
        .refreshable { await store.load() }
    }

    @ViewBuilder
    private var content: some View {
        switch store.phase {
        case .loading:
            ProgressView()
                .frame(maxWidth: .infinity)
                .containerRelativeFrame(.vertical)
        case .loaded(let analyses):
            if analyses.isReady {
                loaded(analyses)
            } else {
                notReady(analyses)
            }
        case .failed(let message):
            ContentUnavailableView {
                Label("Analyses indisponibles", systemImage: "wifi.slash")
            } description: {
                Text(message)
            } actions: {
                Button("Réessayer") { Task { await store.load() } }
            }
            .containerRelativeFrame(.vertical)
        case .unauthorized:
            ContentUnavailableView {
                Label("Session expirée", systemImage: "person.crop.circle.badge.exclamationmark")
            } description: {
                Text("Reconnecte-toi pour relire tes analyses.")
            }
            .containerRelativeFrame(.vertical)
        }
    }

    private func notReady(_ analyses: V1JournalAnalyses) -> some View {
        ContentUnavailableView {
            Label("Pas encore assez de données", systemImage: "chart.line.uptrend.xyaxis")
        } description: {
            Text("Il faut \(analyses.minDays) jours avec au moins un signal noté avant d'ouvrir les analyses.")
        } actions: {
            VStack(spacing: SharpitSpacing.xs) {
                ProgressView(value: Double(min(analyses.daysWithSignal, analyses.minDays)), total: Double(analyses.minDays))
                    .tint(SharpitColor.primary)
                    .frame(maxWidth: 220)
                Text(JournalAnalysesReadout.progress(analyses))
                    .font(SharpitTypography.meta)
                    .foregroundStyle(SharpitColor.mutedForeground)
                    .monospacedDigit()
            }
        }
        .containerRelativeFrame(.vertical)
    }

    private func loaded(_ analyses: V1JournalAnalyses) -> some View {
        VStack(alignment: .leading, spacing: SharpitSpacing.section) {
            if let reading = analyses.reading {
                JournalAnalysesPlate(reading: reading)
            }

            if !analyses.lifts.isEmpty {
                JournalSection(title: "Ce qui t'aide") {
                    domains(analyses.lifts, tone: SharpitColor.signalRecovery)
                }
            }
            if !analyses.drags.isEmpty {
                JournalSection(title: "Ce qui te freine") {
                    domains(analyses.drags, tone: SharpitColor.signalCaution)
                }
            }
            if !analyses.leads.isEmpty {
                JournalSection(
                    title: "Pistes à confirmer",
                    hint: "Écart encore fragile : continue à noter avant de changer quoi que ce soit."
                ) {
                    domains(analyses.leads, tone: SharpitColor.mutedForeground)
                }
            }

            SharpitListFooter(
                "Une association n'est pas une cause : ce qui va avec une habitude, pas forcément ce qu'elle provoque. Médianes des jours avec et sans l'habitude."
            )
        }
    }

    private func domains(_ domains: [V1JournalAnalysesDomain], tone: Color) -> some View {
        VStack(spacing: SharpitSpacing.sm) {
            ForEach(domains) { domain in
                JournalAnalysesDomainCard(domain: domain, tone: tone)
            }
        }
    }
}

// MARK: - Plate

/// « À retenir »: the verdict, its count, what to try, and what already holds.
private struct JournalAnalysesPlate: View {
    let reading: V1JournalAnalysesReading

    private var muted: Color { SharpitColor.inkSurfaceForeground.opacity(0.68) }

    var body: some View {
        VStack(alignment: .leading, spacing: SharpitSpacing.sm) {
            Text("À retenir")
                .font(SharpitTypography.label)
                .tracking(SharpitTypography.labelTracking)
                .textCase(.uppercase)
                .foregroundStyle(muted)

            Text(reading.verdict)
                .font(SharpitTypography.verdict)
                .tracking(SharpitTypography.verdictTracking)
                .foregroundStyle(SharpitColor.inkSurfaceForeground)
                .fixedSize(horizontal: false, vertical: true)

            Text(reading.summary)
                .font(SharpitTypography.meta)
                .foregroundStyle(muted)
                .monospacedDigit()

            Text(reading.actionHint)
                .font(SharpitTypography.bodyEmphasis)
                .foregroundStyle(SharpitColor.inkSurfaceForeground.opacity(0.86))
                .fixedSize(horizontal: false, vertical: true)

            if !reading.strengths.isEmpty {
                VStack(alignment: .leading, spacing: SharpitSpacing.xxs) {
                    ForEach(reading.strengths, id: \.self) { strength in
                        Text("Ce qui tient · \(strength)")
                            .font(SharpitTypography.meta)
                            .foregroundStyle(muted)
                    }
                }
            }
        }
        .padding(SharpitSpacing.cardPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .sharpitSurface(.ink)
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Domain

/// One outcome — Sommeil, Récupération, Body Battery — and its habits on a shared axis.
private struct JournalAnalysesDomainCard: View {
    let domain: V1JournalAnalysesDomain
    let tone: Color

    var body: some View {
        VStack(alignment: .leading, spacing: SharpitSpacing.md) {
            SharpitCardHeader(title: domain.title, symbol: domain.outcome.symbol, tint: tone, showsChevron: false)

            ForEach(Array(domain.rows.enumerated()), id: \.element.id) { index, row in
                if index > 0 { Divider() }
                JournalAnalysesRowView(row: row, gridPct: domain.ticks.map(\.pct), tone: tone)
            }

            axis
        }
        .padding(SharpitSpacing.cardPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .sharpitSurface(.panel)
    }

    /// The axis's labels, under the last row, placed where the grid lines fall.
    private var axis: some View {
        GeometryReader { proxy in
            ForEach(Array(domain.ticks.enumerated()), id: \.offset) { index, tick in
                Text(tick.label)
                    .font(SharpitTypography.meta)
                    .foregroundStyle(SharpitColor.mutedForeground)
                    .monospacedDigit()
                    .fixedSize()
                    .frame(width: proxy.size.width, alignment: alignment(for: index))
                    .offset(x: offset(for: tick, index: index, width: proxy.size.width))
            }
        }
        .frame(height: 16)
        .accessibilityHidden(true)
    }

    private func alignment(for index: Int) -> Alignment {
        if index == 0 { return .leading }
        if index == domain.ticks.count - 1 { return .trailing }
        return .center
    }

    /// The first and last labels hug the edges; the middle ones centre on their line.
    private func offset(for tick: V1JournalAnalysesDomain.Tick, index: Int, width: CGFloat) -> CGFloat {
        guard index > 0, index < domain.ticks.count - 1 else { return 0 }
        return width * CGFloat(tick.pct / 100) - width / 2
    }
}

private struct JournalAnalysesRowView: View {
    let row: V1JournalAnalysesRow
    let gridPct: [Double]
    let tone: Color

    var body: some View {
        VStack(alignment: .leading, spacing: SharpitSpacing.xs) {
            HStack(alignment: .firstTextBaseline, spacing: SharpitSpacing.xs) {
                Text(row.habit)
                    .font(SharpitTypography.cardTitle)
                    .tracking(SharpitTypography.cardTitleTracking)
                    .foregroundStyle(SharpitColor.foreground)
                if let lag = row.lagLabel {
                    Text(lag)
                        .font(SharpitTypography.meta)
                        .foregroundStyle(SharpitColor.mutedForeground)
                }
                Spacer(minLength: SharpitSpacing.xs)
                Text(row.deltaLabel)
                    .font(SharpitTypography.instrument)
                    .foregroundStyle(tone)
                    .monospacedDigit()
            }

            SharpitDumbbellTrack(
                withoutPct: row.withoutPct,
                withPct: row.withPct,
                withDaysPct: row.withDaysPct,
                withoutDaysPct: row.withoutDaysPct,
                gridPct: gridPct,
                tone: tone,
                dashed: row.weak
            )

            Text(row.mediansLabel)
                .font(SharpitTypography.meta)
                .foregroundStyle(SharpitColor.foreground)
                .monospacedDigit()
            Text(row.overlapSentence)
                .font(SharpitTypography.meta)
                .foregroundStyle(SharpitColor.mutedForeground)
                .fixedSize(horizontal: false, vertical: true)
            Text(JournalAnalysesReadout.sample(row))
                .font(SharpitTypography.meta)
                .foregroundStyle(SharpitColor.mutedForeground)
                .monospacedDigit()
        }
        .accessibilityElement(children: .combine)
    }
}
