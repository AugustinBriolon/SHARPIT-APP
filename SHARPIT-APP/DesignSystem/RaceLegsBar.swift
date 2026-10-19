import SwiftUI

/// A race's legs as one bar, each stretch as wide as its share of the time, then each leg's
/// name and time under it — Natation · T1 · Vélo · T2 · Course. Résumé's race card and the
/// session page draw the same one.
struct RaceLegsBar: View {
    let segments: [RaceLegSegment]
    /// A thin bar without its legend, for a summary; VoiceOver still reads every leg.
    var compact = false

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    /// A transition is a minute or two of a race: drawn honestly it would vanish.
    private static let minimumWidth: Double = 3
    private static let gap: Double = 2

    private var primaryText: Color { SharpitColor.foreground }
    private var secondaryText: Color { SharpitColor.mutedForeground }

    var body: some View {
        VStack(alignment: .leading, spacing: SharpitSpacing.xs) {
            bar
                .frame(height: compact ? 4 : 8)
            if !compact {
                legend
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
    }

    private var bar: some View {
        GeometryReader { proxy in
            let widths = RaceLegsTimeline.widths(
                segments, in: proxy.size.width, minimum: Self.minimumWidth, gap: Self.gap
            )
            HStack(spacing: CGFloat(Self.gap)) {
                ForEach(Array(zip(segments, widths)), id: \.0.id) { segment, width in
                    Capsule()
                        .fill(fill(for: segment))
                        .frame(width: width)
                }
            }
        }
    }

    private var legend: some View {
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: SharpitSpacing.xxs))
            : AnyLayout(HStackLayout(alignment: .top, spacing: SharpitSpacing.sm))
        return layout {
            ForEach(segments) { segment in
                VStack(alignment: .leading, spacing: 1) {
                    Text(segment.label)
                        .font(SharpitTypography.meta)
                        .foregroundStyle(segment.isTransition ? secondaryText : primaryText)
                    Text(RaceTime.clock(segment.durationSec))
                        .font(SharpitTypography.meta)
                        .monospacedDigit()
                        .foregroundStyle(secondaryText)
                }
                .lineLimit(1)
                .fixedSize(horizontal: !dynamicTypeSize.isAccessibilitySize, vertical: false)
            }
        }
    }

    private func fill(for segment: RaceLegSegment) -> Color {
        guard let sport = segment.sport else { return primaryText.opacity(0.28) }
        return SharpitSportTone.accent(for: sport)
    }

    private var accessibilityLabel: String {
        let legs = segments
            .map { "\($0.label) \(RaceTime.spoken($0.durationSec))" }
            .joined(separator: ", ")
        return String(localized: "Enchaînement : \(legs)")
    }
}

/// The final time, big, with how far it landed from the target beside it.
struct RaceTimeReadout: View {
    let result: RaceResultModel

    private var primaryText: Color { SharpitColor.foreground }

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .lastTextBaseline, spacing: SharpitSpacing.xs) { time; delta }
            VStack(alignment: .leading, spacing: SharpitSpacing.xxs) { time; delta }
        }
    }

    private var time: some View {
        Text(RaceTime.clock(result.durationSec))
            .font(SharpitTypography.heroScore)
            .tracking(SharpitTypography.heroScoreTracking)
            .monospacedDigit()
            .foregroundStyle(primaryText)
            .lineLimit(1)
            .minimumScaleFactor(0.6)
            .accessibilityLabel("Temps final \(RaceTime.spoken(result.durationSec))")
    }

    @ViewBuilder
    private var delta: some View {
        if let delta = result.delta {
            Text(delta.label)
                .font(SharpitTypography.bodyEmphasis)
                .monospacedDigit()
                .foregroundStyle(delta.isAhead ? primaryText : primaryText.opacity(0.7))
                .lineLimit(1)
                .accessibilityLabel(delta.spokenLabel)
        }
    }
}
