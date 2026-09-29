import SwiftUI

/// Santé's headline, standing on the page rather than in a card: one very large number on a halo
/// whose colour is the reading's, a pill that says what it means, and a ruler that places it.
///
/// With a biological age, the number is that age and the ruler runs ten years either side of the
/// civil age. Without one — below Pro, or before the data it needs — the number is how many markers
/// sit in their norm and the ruler has one tick per marker, in its tone. The halo is the page's
/// one departure from "no decorative wash": it carries the reading's tone, nothing else.
struct SanteHero: View {
    let synthesis: V1HealthSynthesis
    /// Every normed marker's tone, in page order, for the fallback ruler.
    let tones: [V1HealthTone]
    let watchCount: Int

    @State private var hasAppeared = false

    var body: some View {
        VStack(spacing: SharpitSpacing.md) {
            Text(caption)
                .font(SharpitTypography.label)
                .tracking(SharpitTypography.labelTracking)
                .textCase(.uppercase)
                .foregroundStyle(SharpitColor.mutedForeground)
            figure
            if let pill {
                Text(pill)
                    .font(SharpitTypography.bodyEmphasis)
                    .foregroundStyle(tone)
                    .padding(.horizontal, SharpitSpacing.md)
                    .padding(.vertical, SharpitSpacing.xs)
                    .overlay(Capsule().strokeBorder(tone.opacity(0.55), lineWidth: 1))
                    .background(tone.opacity(0.1), in: Capsule())
            }
            ruler
                .frame(height: 56)
                .padding(.top, SharpitSpacing.sm)
            if !synthesis.highlights.isEmpty {
                highlights
            }
            if synthesis.biologicalAge != nil {
                Text(BiologicalAgeReadout.disclaimer)
                    .font(SharpitTypography.meta)
                    .foregroundStyle(SharpitColor.mutedForeground)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.horizontal, SharpitSpacing.pageInset)
        .padding(.top, SharpitSpacing.lg)
        .padding(.bottom, SharpitSpacing.xl)
        .frame(maxWidth: .infinity)
        .background(halo)
        .onAppear { hasAppeared = true }
        .accessibilityElement(children: .combine)
    }

    // MARK: - What it shows

    private var caption: String {
        synthesis.biologicalAge != nil ? "Âge biologique" : "Repères dans leur norme"
    }

    @ViewBuilder
    private var figure: some View {
        if let age = synthesis.biologicalAge {
            Text(BiologicalAgeReadout.years(hasAppeared ? age.years : (age.chronologicalYears ?? age.years)))
                .font(SharpitTypography.showcaseScore)
                .tracking(SharpitTypography.showcaseScoreTracking)
                .foregroundStyle(SharpitColor.foreground)
                .contentTransition(.numericText())
                .animation(SharpitMotion.reveal, value: hasAppeared)
                .minimumScaleFactor(0.6)
                .lineLimit(1)
        } else {
            HStack(alignment: .lastTextBaseline, spacing: SharpitSpacing.xxs) {
                Text("\(synthesis.inNorm)")
                    .font(SharpitTypography.showcaseScore)
                    .tracking(SharpitTypography.showcaseScoreTracking)
                    .foregroundStyle(SharpitColor.foreground)
                Text("/ \(synthesis.normed)")
                    .font(SharpitTypography.gaugeScore)
                    .foregroundStyle(SharpitColor.mutedForeground)
            }
            .lineLimit(1)
        }
    }

    private var pill: String? {
        if let age = synthesis.biologicalAge { return BiologicalAgeReadout.gap(age) }
        guard synthesis.normed > 0 else { return nil }
        switch watchCount {
        case 0: return "Rien à surveiller"
        case 1: return "1 point à surveiller"
        default: return "\(watchCount) points à surveiller"
        }
    }

    /// The reading's tone: younger or older than the civil age, or whether anything is flagged.
    private var tone: Color {
        if let age = synthesis.biologicalAge {
            switch BiologicalAgeReadout.isYounger(age) {
            case true?: return SharpitColor.signalRecovery
            case false?: return SharpitColor.signalCaution
            case nil: return SharpitColor.primary
            }
        }
        return watchCount == 0 ? SharpitColor.signalRecovery : SharpitColor.signalCaution
    }

    // MARK: - Ruler

    @ViewBuilder
    private var ruler: some View {
        if let age = synthesis.biologicalAge, let civil = age.chronologicalYears {
            SanteAgeRuler(civil: civil, biological: age.years, tone: tone, isRevealed: hasAppeared)
        } else if !tones.isEmpty {
            SanteToneRuler(tones: tones)
        }
    }

    private var highlights: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: SharpitSpacing.xs) { chips }
            VStack(spacing: SharpitSpacing.xs) { chips }
        }
    }

    private var chips: some View {
        ForEach(synthesis.highlights, id: \.key) { highlight in
            Text(SanteReadout.highlight(highlight))
                .font(SharpitTypography.meta.weight(.semibold))
                .foregroundStyle(highlight.tone.color)
                .lineLimit(1)
                .fixedSize()
                .padding(.horizontal, SharpitSpacing.sm)
                .padding(.vertical, SharpitSpacing.xxs + 2)
                .background(highlight.tone.color.opacity(0.14), in: Capsule())
        }
    }

    // MARK: - Halo

    /// Full width, under the navigation bar: the reading's tone at the centre, the brand's
    /// highlight beside it, both fading to the page.
    private var halo: some View {
        GeometryReader { geometry in
            let size = geometry.size
            ZStack {
                // The reading's tone, full and wide behind the number.
                RadialGradient(
                    colors: [tone.opacity(0.75), tone.opacity(0.28), .clear],
                    center: UnitPoint(x: 0.5, y: 0.36),
                    startRadius: 0,
                    endRadius: size.width * 0.78
                )
                // The brand's highlight drifting in from a corner, so the halo reads as light
                // rather than a flat disc.
                RadialGradient(
                    colors: [SharpitColor.highlight.opacity(0.35), .clear],
                    center: UnitPoint(x: 0.82, y: 0.18),
                    startRadius: 0,
                    endRadius: size.width * 0.6
                )
                RadialGradient(
                    colors: [SharpitColor.primary.opacity(0.25), .clear],
                    center: UnitPoint(x: 0.12, y: 0.62),
                    startRadius: 0,
                    endRadius: size.width * 0.55
                )
            }
            .blur(radius: 24)
            .frame(width: size.width, height: size.height + 160)
            .offset(y: -160)
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// Ten years either side of the civil age, a tick a year and a longer one every five: the civil
/// age marked and named, the biological age drawn in the reading's tone.
private struct SanteAgeRuler: View {
    let civil: Double
    let biological: Double
    let tone: Color
    let isRevealed: Bool

    private let span = 10

    var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            let low = Int(civil.rounded()) - span
            let step = width / CGFloat(span * 2)
            let position = { (years: Double) in CGFloat(years - Double(low)) * step }
            ZStack(alignment: .topLeading) {
                Canvas { context, size in
                    for index in 0...(span * 2) {
                        let x = CGFloat(index) * step
                        let isMajor = (low + index) % 5 == 0
                        let height: CGFloat = isMajor ? 22 : 12
                        let rect = CGRect(x: x - 0.5, y: 0, width: 1, height: height)
                        context.fill(Path(rect), with: .color(SharpitColor.mutedForeground.opacity(isMajor ? 0.55 : 0.3)))
                    }
                    // The civil age: a thin full-height mark.
                    let civilX = position(civil)
                    context.fill(
                        Path(CGRect(x: civilX - 0.75, y: 0, width: 1.5, height: 30)),
                        with: .color(SharpitColor.foreground.opacity(0.6))
                    )
                    _ = size
                }
                Capsule()
                    .fill(tone)
                    .frame(width: 3, height: 36)
                    .offset(x: position(isRevealed ? min(max(biological, Double(low)), Double(low + span * 2)) : civil) - 1.5, y: -3)
                    .animation(SharpitMotion.reveal, value: isRevealed)
                Text("\(Int(civil.rounded())) · ton âge")
                    .font(SharpitTypography.meta)
                    .foregroundStyle(SharpitColor.mutedForeground)
                    .fixedSize()
                    .offset(x: position(civil) - 34, y: 36)
            }
        }
    }
}

/// One tick per normed marker, in its tone: the check-up at a glance when there is no age.
private struct SanteToneRuler: View {
    let tones: [V1HealthTone]

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            ForEach(Array(tones.enumerated()), id: \.offset) { _, tone in
                Capsule()
                    .fill(tone == .neutral ? SharpitColor.mutedForeground.opacity(0.45) : tone.color)
                    .frame(width: 3, height: tone == .watch ? 36 : 26)
                    .frame(maxWidth: .infinity)
            }
        }
        .padding(.horizontal, SharpitSpacing.lg)
    }
}
