import SwiftUI

struct OvernightGaugePair: View {
    let gauges: [OvernightGaugeModel]
    var pulseScores: Bool = false
    /// When set, each gauge opens the screen behind it.
    var onSelect: ((V1TodaySignalKey) -> Void)?

    var body: some View {
        HStack(alignment: .top, spacing: SharpitSpacing.xs) {
            ForEach(gauges) { gauge in
                if let onSelect {
                    Button { onSelect(gauge.key) } label: {
                        OvernightGaugeCell(gauge: gauge, pulse: pulseScores, opensDetail: true)
                    }
                    .buttonStyle(.sharpitPressable)
                    .accessibilityAddTraits(.isButton)
                } else {
                    OvernightGaugeCell(gauge: gauge, pulse: pulseScores)
                }
            }
        }
    }
}

/// One overnight readout, composed as the web composes it: the instrument's name on top,
/// the dial centred under it at a capped width, the baseline note at the foot.
///
/// The name used to sit *under* the dial, and the dial filled the card's full width. Both
/// were wrong, and no amount of spacing rescued them — a title below its instrument reads
/// as a caption for whatever follows, and an edge-to-edge dial has no air to give.
private struct OvernightGaugeCell: View {
    let gauge: OvernightGaugeModel
    var pulse: Bool = false
    var opensDetail = false

    @State private var displayedScore: CGFloat?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// The web caps the dial and centres it (`max-w-36` → `max-w-52`) rather than letting
    /// it fill the card. That cap is what gives the instrument its margin.
    private let dialMaxWidth: CGFloat = 150

    private var targetScore: CGFloat? {
        AnimatedScoreText.progressFraction(from: gauge.score).map { CGFloat($0 * 100) }
    }

    var body: some View {
        VStack(spacing: SharpitSpacing.md) {
            header
            dial
            if let caption = gauge.caption {
                Text(caption)
                    .font(SharpitTypography.meta)
                    .foregroundStyle(SharpitColor.mutedForeground)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .frame(maxWidth: .infinity, alignment: .center)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(SharpitSpacing.cardPadding)
        .sharpitSurface(.panel)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
        .onAppear { reveal(to: targetScore) }
        .onChange(of: gauge.score) { _, _ in reveal(to: targetScore) }
    }

    private var header: some View {
        HStack(spacing: SharpitSpacing.xxs + 2) {
            Image(systemName: gauge.key.instrumentSymbol)
                .font(SharpitTypography.label)
                .foregroundStyle(SharpitColor.primary)
            Text(title)
                .font(SharpitTypography.label)
                .tracking(SharpitTypography.labelTracking)
                .textCase(.uppercase)
                .foregroundStyle(SharpitColor.mutedForeground)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            if opensDetail {
                Image(systemName: "chevron.right")
                    .font(SharpitTypography.label)
                    .foregroundStyle(SharpitColor.mutedForeground)
                    .accessibilityHidden(true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .center)
    }

    private var dial: some View {
        ZStack(alignment: .top) {
            SharpitTickGauge(score: displayedScore)

            GeometryReader { geo in
                readout
                    .frame(width: geo.size.width)
                    .position(
                        x: geo.size.width / 2,
                        y: geo.size.height * SharpitTickGaugeGeometry.readoutTopFraction
                            + readoutHeight / 2
                    )
            }
        }
        .frame(maxWidth: dialMaxWidth)
        .aspectRatio(SharpitTickGaugeGeometry.aspectRatio, contentMode: .fit)
    }

    /// Approximate height of the score block, used to hang it from its top edge the way
    /// the web's absolutely positioned readout hangs from `top-[44%]`.
    private var readoutHeight: CGFloat { 50 }

    private var readout: some View {
        VStack(spacing: SharpitSpacing.xxs) {
            Text(scoreDisplay)
                .font(SharpitTypography.gaugeScore)
                .tracking(SharpitTypography.gaugeScoreTracking)
                .foregroundStyle(SharpitColor.foreground)
                .opacity(displayedScore == nil ? 0.45 : (pulse ? 0.55 : 1))
                .contentTransition(reduceMotion ? .identity : .numericText())
            Text("sur 100")
                .font(SharpitTypography.meta)
                .foregroundStyle(SharpitColor.mutedForeground)
        }
    }

    private var scoreDisplay: String {
        guard let displayedScore else { return "—" }
        return String(Int(displayedScore.rounded()))
    }

    private func reveal(to value: CGFloat?) {
        guard !SharpitMotion.reduceMotion, !reduceMotion else {
            displayedScore = value
            return
        }
        SharpitMotion.run(SharpitMotion.gaugeFill) {
            displayedScore = value
        }
    }

    private var accessibilityLabel: String {
        [title, "\(gauge.score) sur 100", gauge.caption]
            .compactMap { $0 }
            .filter { !$0.isEmpty }
            .joined(separator: ", ")
    }

    private var title: String {
        switch gauge.key {
        case .sleep: "Sommeil"
        case .recovery: "Récupération"
        case .effort, .adaptation: gauge.key.instrumentLabel
        }
    }
}
