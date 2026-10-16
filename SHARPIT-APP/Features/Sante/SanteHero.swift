import SwiftUI

/// Santé's headline, the tab's one ink card (ADR-085), as the verdict leads Résumé: one very large
/// number, a pill that says what it means, and a ruler that places it. Younger than the civil age
/// reads lime, older reads caution; nothing else carries a hue.
///
/// With a biological age, the number is that age and the ruler runs ten years either side of the
/// civil age. Without one — below Pro, or before the data it needs — the number is how many markers
/// sit in their norm and the ruler has one tick per marker, in its tone. The card's content is
/// drawn in the dark appearance, so every token resolves to its light-on-ink value.
struct SanteHero: View {
    /// What the hero stands on. Below Pro the web never computes the age, so the locked hero shows
    /// a fixed placeholder, blurred — nothing the app holds could reveal it.
    enum Mode: Equatable {
        case age(V1BiologicalAge)
        case locked
        case norms

        init(_ synthesis: V1HealthSynthesis) {
            // Locked first: below Pro nothing shows an age, whatever the payload holds.
            if synthesis.biologicalAgeRequiresPro {
                self = .locked
            } else if let age = synthesis.biologicalAge {
                self = .age(age)
            } else {
                self = .norms
            }
        }
    }

    /// Drawn under the blur. A constant, never derived from anything the athlete measured.
    static let lockedPlaceholder = "00"

    let synthesis: V1HealthSynthesis
    /// Every normed marker's tone, in page order, for the fallback ruler.
    let tones: [V1HealthTone]
    let watchCount: Int

    @State private var hasAppeared = false
    @Environment(ProStore.self) private var pro: ProStore?

    private var mode: Mode { Mode(synthesis) }

    var body: some View {
        VStack(spacing: SharpitSpacing.md) {
            Text(caption)
                .font(SharpitTypography.cardTitle)
                .foregroundStyle(SharpitColor.mutedForeground)
            figure
            if mode == .locked {
                unlock
                if let line = SanteReadout.synthesis(synthesis) {
                    Text(line)
                        .font(SharpitTypography.meta)
                        .foregroundStyle(SharpitColor.mutedForeground)
                }
            } else if let pill {
                Text(pill)
                    .font(SharpitTypography.bodyEmphasis)
                    .foregroundStyle(tone)
                    .padding(.horizontal, SharpitSpacing.md)
                    .padding(.vertical, SharpitSpacing.xs)
                    .background(tone.opacity(0.16), in: Capsule())
            }
            ruler
                .frame(height: 56)
                .padding(.top, SharpitSpacing.sm)
            if !synthesis.highlights.isEmpty {
                highlights
            }
            if mode != .norms {
                Text(BiologicalAgeReadout.disclaimer)
                    .font(SharpitTypography.meta)
                    .foregroundStyle(SharpitColor.mutedForeground)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.horizontal, SharpitSpacing.cardPadding)
        .padding(.vertical, SharpitSpacing.xl)
        .frame(maxWidth: .infinity)
        .environment(\.colorScheme, .dark)
        .sharpitContainerCorner(SharpitRadius.panel)
        .background(SharpitColor.inkSurface, in: RoundedRectangle(cornerRadius: SharpitRadius.panel, style: .continuous))
        .sharpitShadow(.panel)
        .padding(.horizontal, SharpitSpacing.pageInset)
        .padding(.top, SharpitSpacing.xs)
        .padding(.bottom, SharpitSpacing.lg)
        .onAppear { hasAppeared = true }
        .accessibilityElement(children: .combine)
    }

    // MARK: - What it shows

    private var caption: String {
        mode == .norms ? "Repères dans leur norme" : "Âge biologique"
    }

    @ViewBuilder
    private var figure: some View {
        if mode == .locked {
            Text(Self.lockedPlaceholder)
                .font(SharpitTypography.showcaseScore)
                .tracking(SharpitTypography.showcaseScoreTracking)
                // Enough to read as two digits, never enough to read which.
                .foregroundStyle(SharpitColor.foreground.opacity(0.8))
                .blur(radius: 11)
                .overlay {
                    Image(systemName: "lock.fill")
                        .font(.title2.weight(.semibold))
                        .foregroundStyle(SharpitColor.foreground)
                }
                .accessibilityHidden(true)
        } else if case .age(let age) = mode {
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
            case true?: return SharpitColor.highlight
            case false?: return SharpitColor.signalCaution
            case nil: return SharpitColor.foreground
            }
        }
        if mode == .locked { return SharpitColor.foreground }
        return watchCount == 0 ? SharpitColor.highlight : SharpitColor.signalCaution
    }

    /// The way to Pro, where the pill would say the gap.
    @ViewBuilder
    private var unlock: some View {
        let label = HStack(spacing: SharpitSpacing.xs) {
            Image(systemName: "sparkle")
            Text("Débloquer avec SharpIt Pro")
        }
        .font(SharpitTypography.bodyEmphasis)
        .foregroundStyle(SharpitColor.highlightForeground)
        .padding(.horizontal, SharpitSpacing.md)
        .padding(.vertical, SharpitSpacing.xs + 2)
        .background(SharpitColor.highlight, in: Capsule())
        if let pro {
            NavigationLink { ProView(store: pro) } label: { label }
                .buttonStyle(.sharpitPressable)
                .accessibilityHint("Ton âge biologique, calculé par SharpIt à partir de ta VO₂max")
        } else {
            label
        }
    }

    // MARK: - Ruler

    @ViewBuilder
    private var ruler: some View {
        if mode == .locked {
            SanteBlankRuler()
        } else if let age = synthesis.biologicalAge, let civil = age.chronologicalYears {
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

/// The locked hero's ruler: the same ticks, nothing placed on them.
private struct SanteBlankRuler: View {
    var body: some View {
        Canvas { context, size in
            let count = 20
            let step = size.width / CGFloat(count)
            for index in 0...count {
                let isMajor = index % 5 == 0
                let rect = CGRect(x: CGFloat(index) * step - 0.5, y: 0, width: 1, height: isMajor ? 22 : 12)
                context.fill(Path(rect), with: .color(SharpitColor.mutedForeground.opacity(isMajor ? 0.5 : 0.28)))
            }
        }
        .accessibilityHidden(true)
    }
}
