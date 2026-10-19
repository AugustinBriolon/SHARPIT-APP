import SwiftUI

/// One leg of a triathlon under the course map: a sport leg reads as a session of its sport,
/// through the page's own sections; a transition as one compact card.
struct TriathlonLegSections: View {
    let track: TriathlonLegTrack
    /// The race the leg belongs to: its date and its race reading (the leg's heart-rate zones).
    let race: V1ActivityDetail

    @Environment(\.isExpertReading) private var isExpertReading
    @State private var chartSelection: [ActivityChartMetric]

    init(track: TriathlonLegTrack, race: V1ActivityDetail) {
        self.track = track
        self.race = race
        _chartSelection = State(initialValue: Array(ActivityChartMetric.available(in: track.samples).prefix(1)))
    }

    var body: some View {
        if track.segment.isTransition {
            TriathlonTransitionCard(track: track)
        } else {
            sportSections
        }
    }

    private var sportSections: some View {
        let detail = race.leg(track.leg)
        let tone = activityTone(detail.type)
        let splits = detail.type.supportsSplits
            ? ActivitySplit.make(samples: track.samples, totalDuration: detail.duration, segmentDistance: detail.type.splitDistance)
            : []
        let chartMetrics = ActivityChartMetric.available(in: track.samples)
        let zones = race.raceAnalysis.map(RaceAnalysisReadout.zoneRows)?.filter { $0.id == track.id } ?? []
        return VStack(alignment: .leading, spacing: SharpitSpacing.section) {
            ActivityMetricGrid(
                title: String(localized: "Résumé de l’étape"),
                metrics: ActivityHeroMetricData.primary(
                    for: detail,
                    distanceM: detail.distanceM ?? track.samples.last?.d,
                    isExpertReading: isExpertReading
                )
            )
            if !zones.isEmpty {
                RaceZonesBlock(rows: zones)
            }
            if isExpertReading, let analysis = track.analysis, !ActivityTechnicalSection(analysis: analysis).isEmpty {
                ActivityTechnicalSection(analysis: analysis)
            }
            if !splits.isEmpty {
                ActivitySplitsSection(splits: splits, tone: tone, segmentDistance: detail.type.splitDistance)
            }
            if !chartMetrics.isEmpty {
                ActivityChartsSection(samples: track.samples, metrics: chartMetrics, selection: $chartSelection, tone: tone)
            }
        }
    }
}

/// A transition: its time, then where it went — distance, moving against stopped, heart rate.
/// The map above frames it when it carries GPS.
private struct TriathlonTransitionCard: View {
    let track: TriathlonLegTrack

    var body: some View {
        VStack(alignment: .leading, spacing: SharpitSpacing.md) {
            SharpitEyebrow(String(localized: "Transition · \(track.segment.label)"), systemImage: "arrow.triangle.2.circlepath")
            Text(RaceTime.clock(track.leg.durationSec))
                .font(SharpitTypography.heroScore)
                .tracking(SharpitTypography.heroScoreTracking)
                .monospacedDigit()
                .foregroundStyle(SharpitColor.foreground)
                .accessibilityLabel(RaceTime.spoken(track.leg.durationSec))
            let rows = TriathlonTransitionReadout.rows(track.leg)
            if !rows.isEmpty {
                ActivityTechnicalGrid(rows: rows)
            }
        }
        .padding(SharpitSpacing.cardPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .sharpitSurface(.panel)
    }
}

/// How a transition's figures are worded; each row only when the recording carries it.
enum TriathlonTransitionReadout {
    static func rows(_ leg: V1MultisportLeg) -> [ActivityTechnicalRow] {
        var rows: [ActivityTechnicalRow] = []
        if let distance = leg.distanceM, distance > 0 {
            rows.append(ActivityTechnicalRow(label: String(localized: "Distance"), value: "\(Int(distance.rounded())) m"))
        }
        if let moving = leg.movingDurationSec, moving > 0 {
            let moving = min(moving, leg.durationSec)
            rows.append(ActivityTechnicalRow(label: String(localized: "En mouvement"), value: RaceTime.clock(moving)))
            rows.append(ActivityTechnicalRow(label: String(localized: "À l’arrêt"), value: RaceTime.clock(leg.durationSec - moving)))
        }
        if let hr = leg.avgHr, hr > 0 {
            rows.append(ActivityTechnicalRow(label: String(localized: "FC moyenne"), value: "\(Int(hr.rounded())) bpm"))
        }
        return rows
    }
}
