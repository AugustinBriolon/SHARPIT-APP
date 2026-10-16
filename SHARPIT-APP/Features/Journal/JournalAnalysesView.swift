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
                group("Ce qui t'aide", analyses.lifts, kind: .lift)
            }
            if !analyses.drags.isEmpty {
                group("Ce qui te freine", analyses.drags, kind: .drag)
            }
            if !analyses.leads.isEmpty {
                group(
                    "Pistes à confirmer",
                    analyses.leads,
                    kind: .lead,
                    hint: "Écart encore fragile : continue à noter avant de changer quoi que ce soit."
                )
            }

            SharpitListFooter(
                "Une association n'est pas une cause : ce qui va avec une habitude, pas forcément ce qu'elle provoque. Médianes des jours avec et sans l'habitude."
            )
        }
    }

    private func group(
        _ title: String,
        _ domains: [V1JournalAnalysesDomain],
        kind: JournalAnalysesKind,
        hint: String? = nil
    ) -> some View {
        JournalSection(title: title, hint: hint) {
            VStack(spacing: SharpitSpacing.sm) {
                ForEach(domains) { domain in
                    JournalAnalysesDomainCard(domain: domain, kind: kind)
                }
            }
        }
    }
}

/// Which list a habit sits in, which sets its pill: lime for what helps, caution for what
/// drags, neutral for what is still to confirm.
enum JournalAnalysesKind {
    case lift, drag, lead

    var pill: SharpitPill.Style {
        switch self {
        case .lift: .limeSoft
        case .drag, .lead: .neutral
        }
    }

    var tone: Color {
        switch self {
        case .lift: SharpitColor.foreground
        case .drag: SharpitColor.signalCaution
        case .lead: SharpitColor.mutedForeground
        }
    }
}

// MARK: - Plate

/// « À retenir »: one sentence to act on, how much it rests on, and what already holds.
private struct JournalAnalysesPlate: View {
    let reading: V1JournalAnalysesReading

    private var ink: Color { SharpitColor.inkSurfaceForeground }

    /// The verdict and the hint often say the same thing; the hint is the one to act on.
    private var sentence: String {
        reading.actionHint.isEmpty ? reading.verdict : reading.actionHint
    }

    var body: some View {
        VStack(alignment: .leading, spacing: SharpitSpacing.md) {
            HStack(spacing: SharpitSpacing.sm) {
                Image(systemName: "lightbulb")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(SharpitColor.highlightForeground)
                    .frame(width: SharpitTokens.tileSize, height: SharpitTokens.tileSize)
                    .sharpitConcentricBackground(SharpitColor.highlight, minimum: SharpitRadius.tile)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text("À retenir")
                        .font(SharpitTypography.cardTitle)
                        .foregroundStyle(ink)
                    Text(reading.summary)
                        .font(SharpitTypography.meta)
                        .foregroundStyle(ink.opacity(0.6))
                        .monospacedDigit()
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Text(sentence)
                .font(SharpitTypography.system(size: 22, weight: .bold, relativeTo: .title2))
                .tracking(-0.3)
                .foregroundStyle(ink)
                .fixedSize(horizontal: false, vertical: true)

            if !reading.strengths.isEmpty {
                VStack(alignment: .leading, spacing: SharpitSpacing.xs) {
                    ForEach(reading.strengths, id: \.self) { strength in
                        HStack(alignment: .firstTextBaseline, spacing: SharpitSpacing.xs) {
                            Circle()
                                .fill(SharpitColor.highlight)
                                .frame(width: 6, height: 6)
                                .alignmentGuide(.firstTextBaseline) { $0[.bottom] - 1 }
                            Text(strength)
                                .font(SharpitTypography.system(size: 15, weight: .regular, relativeTo: .subheadline))
                                .foregroundStyle(ink.opacity(0.8))
                                .fixedSize(horizontal: false, vertical: true)
                        }
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

/// One outcome — Sommeil, Récupération, Body Battery — and each habit that goes with it as a
/// row: its name and the gap, then « sans → avec » on two points.
private struct JournalAnalysesDomainCard: View {
    let domain: V1JournalAnalysesDomain
    let kind: JournalAnalysesKind

    var body: some View {
        VStack(alignment: .leading, spacing: SharpitSpacing.md) {
            SharpitCardHeader(title: domain.title, symbol: domain.outcome.symbol, showsChevron: false)
            SharpitInsetGroup {
                ForEach(domain.rows) { row in
                    JournalAnalysesRowView(row: row, kind: kind)
                }
            }
        }
        .padding(SharpitSpacing.cardPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .sharpitSurface(.panel)
    }
}

private struct JournalAnalysesRowView: View {
    let row: V1JournalAnalysesRow
    let kind: JournalAnalysesKind

    var body: some View {
        VStack(alignment: .leading, spacing: SharpitSpacing.xs) {
            HStack(alignment: .center, spacing: SharpitSpacing.xs) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(row.habit)
                        .font(SharpitTypography.system(size: 17, weight: .semibold, relativeTo: .body))
                        .foregroundStyle(SharpitColor.foreground)
                    if let lag = row.lagLabel {
                        Text(lag)
                            .font(SharpitTypography.meta)
                            .foregroundStyle(SharpitColor.mutedForeground)
                    }
                }
                Spacer(minLength: SharpitSpacing.xs)
                SharpitPill(row.deltaLabel, style: kind.pill)
            }

            // Two points on one line, no day dots or grid: the gap is the reading.
            SharpitDumbbellTrack(
                withoutPct: row.withoutPct,
                withPct: row.withPct,
                tone: kind.tone,
                dashed: row.weak
            )
            .frame(height: 22)

            HStack(alignment: .firstTextBaseline) {
                Text(row.mediansLabel)
                    .font(SharpitTypography.system(size: 15, weight: .medium, relativeTo: .subheadline, digits: true))
                    .foregroundStyle(SharpitColor.foreground)
                    .lineLimit(1)
                    .fixedSize()
                Spacer(minLength: SharpitSpacing.xs)
                Text(JournalAnalysesReadout.sample(row))
                    .font(SharpitTypography.meta)
                    .foregroundStyle(SharpitColor.mutedForeground)
                    .monospacedDigit()
                    .multilineTextAlignment(.trailing)
            }
        }
        .padding(.horizontal, SharpitSpacing.rowPaddingX)
        .padding(.vertical, SharpitSpacing.sm)
        .sharpitSurface(.row)
        .accessibilityElement(children: .combine)
        .accessibilityHint(row.overlapSentence)
    }
}
