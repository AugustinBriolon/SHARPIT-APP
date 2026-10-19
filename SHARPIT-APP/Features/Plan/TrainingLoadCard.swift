import Charts
import SwiftUI

/// « Forme » at the top of this week in Plan, in the expert reading only (ADR 0006): the web's
/// Effort markers — chronic form, acute fatigue, net form against its usual band — the six-week
/// curve they come from, and eight weeks of load. Where load is planned is where it is read.
struct TrainingLoadCard: View {
    let load: V1TrainingLoad

    private var today: V1TrainingLoad.Day? { load.days.last }

    var body: some View {
        VStack(alignment: .leading, spacing: SharpitSpacing.md) {
            SharpitCardHeader(title: String(localized: "Forme"), symbol: "chart.xyaxis.line", showsChevron: false)
            if let calibration = load.calibration, calibration.isCalibrating {
                Text(calibrationCaption(calibration))
                    .font(SharpitTypography.meta)
                    .foregroundStyle(SharpitColor.signalCaution)
            }
            if let today {
                HStack(alignment: .top, spacing: SharpitSpacing.md) {
                    figure(String(localized: "Forme chronique"), value: "\(Int(today.ctl.rounded()))", caption: "CTL", tone: SharpitColor.foreground)
                    figure(String(localized: "Fatigue aiguë"), value: "\(Int(today.atl.rounded()))", caption: "ATL", tone: SharpitColor.foreground)
                    figure(
                        String(localized: "Forme nette"),
                        value: TrainingLoadReadout.signed(today.tsb),
                        caption: "TSB",
                        tone: TrainingLoadReadout.isInFormBand(today.tsb) ? SharpitColor.foreground : SharpitColor.signalCaution
                    )
                }
            }
            VStack(alignment: .leading, spacing: SharpitSpacing.xs) {
                curve
                legend
            }
            weeks
            Text("Forme nette habituelle entre −20 et +10. Six semaines de courbe, huit de charge.")
                .font(SharpitTypography.meta)
                .foregroundStyle(SharpitColor.mutedForeground)
        }
        .padding(SharpitSpacing.cardPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .sharpitSurface(.panel)
    }

    private func calibrationCaption(_ calibration: V1TrainingLoad.Calibration) -> String {
        let remaining = max(0, calibration.daysNeeded - calibration.daysWithLoad)
        if remaining == 0 {
            return String(localized: "En calibration — encore quelques jours de charge.")
        }
        return remaining == 1
            ? String(localized: "En calibration — encore 1 jour de charge pour fiabiliser la forme.")
            : String(localized: "En calibration — encore \(remaining) jours de charge pour fiabiliser la forme.")
    }

    private func figure(_ label: String, value: String, caption: String, tone: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(SharpitTypography.label)
                .tracking(SharpitTypography.labelTracking)
                .textCase(.uppercase)
                .foregroundStyle(SharpitColor.mutedForeground)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            Text(value)
                .font(SharpitTypography.data)
                .tracking(SharpitTypography.dataTracking)
                .foregroundStyle(tone)
                .monospacedDigit()
            Text(caption)
                .font(SharpitTypography.meta)
                .foregroundStyle(SharpitColor.mutedForeground)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    /// Chronic form and acute fatigue as lines, net form as the band it should stay in.
    private var curve: some View {
        Chart {
            RectangleMark(
                yStart: .value(String(localized: "Bas"), TrainingLoadReadout.formBand.lowerBound),
                yEnd: .value(String(localized: "Haut"), TrainingLoadReadout.formBand.upperBound)
            )
            .foregroundStyle(SharpitColor.analysisSurfaceAlt)
            ForEach(load.days) { day in
                LineMark(x: .value(String(localized: "Jour"), day.date), y: .value("CTL", day.ctl), series: .value(String(localized: "Série"), "CTL"))
                    .foregroundStyle(SharpitColor.primary)
                LineMark(x: .value(String(localized: "Jour"), day.date), y: .value("ATL", day.atl), series: .value(String(localized: "Série"), "ATL"))
                    .foregroundStyle(SharpitColor.signalVo2)
                LineMark(x: .value(String(localized: "Jour"), day.date), y: .value("TSB", day.tsb), series: .value(String(localized: "Série"), "TSB"))
                    .foregroundStyle(SharpitColor.mutedForeground)
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
            }
        }
        .chartYScale(domain: yDomain)
        .chartXAxis(.hidden)
        .chartYAxis {
            AxisMarks(position: .trailing, values: .automatic(desiredCount: 3)) { _ in
                AxisValueLabel().font(SharpitTypography.meta)
            }
        }
        .chartLegend(.hidden)
        .frame(height: 110)
        .accessibilityLabel("Courbe de forme sur six semaines")
    }

    /// The curves' own range, the form band always in view — never a fixed ±100 that flattens them.
    private var yDomain: ClosedRange<Double> {
        let values = load.days.flatMap { [$0.ctl, $0.atl, $0.tsb] }
            + [TrainingLoadReadout.formBand.lowerBound, TrainingLoadReadout.formBand.upperBound]
        let low = (values.min() ?? 0) - 5
        let high = (values.max() ?? 0) + 5
        return low...high
    }

    private var legend: some View {
        HStack(spacing: SharpitSpacing.md) {
            legendItem("CTL", tone: SharpitColor.primary, dashed: false)
            legendItem("ATL", tone: SharpitColor.signalVo2, dashed: false)
            legendItem("TSB", tone: SharpitColor.mutedForeground, dashed: true)
            Spacer(minLength: 0)
        }
        .accessibilityHidden(true)
    }

    private func legendItem(_ label: String, tone: Color, dashed: Bool) -> some View {
        HStack(spacing: 5) {
            Capsule()
                .stroke(tone, style: StrokeStyle(lineWidth: 2, dash: dashed ? [3, 2] : []))
                .frame(width: 14, height: 2)
            Text(label)
                .font(SharpitTypography.meta)
                .foregroundStyle(SharpitColor.mutedForeground)
        }
    }

    private var weeks: some View {
        let peak = max(load.weeks.map(\.tss).max() ?? 0, 1)
        return VStack(alignment: .leading, spacing: SharpitSpacing.xs) {
            HStack {
                Text("TSS par semaine")
                    .font(SharpitTypography.bodyEmphasis)
                    .foregroundStyle(SharpitColor.foreground)
                Spacer()
                if let current = load.weeks.last {
                    Text("\(Int(current.tss.rounded())) cette semaine")
                        .font(SharpitTypography.meta.monospacedDigit())
                        .foregroundStyle(SharpitColor.mutedForeground)
                }
            }
            HStack(alignment: .bottom, spacing: 6) {
                ForEach(Array(load.weeks.enumerated()), id: \.element.id) { index, week in
                    VStack(spacing: 4) {
                        RoundedRectangle(cornerRadius: 3, style: .continuous)
                            .fill(index == load.weeks.count - 1 ? SharpitColor.primary : SharpitColor.primary.opacity(0.35))
                            .frame(height: max(3, 44 * week.tss / peak))
                            .frame(height: 44, alignment: .bottom)
                        Text("\(Int(week.tss.rounded()))")
                            .font(SharpitTypography.meta.monospacedDigit())
                            .foregroundStyle(SharpitColor.mutedForeground)
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Charge des huit dernières semaines")
        }
    }
}
