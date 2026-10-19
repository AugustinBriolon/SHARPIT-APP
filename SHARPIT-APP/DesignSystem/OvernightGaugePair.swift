import SwiftUI

struct OvernightGaugePair: View {
    let gauges: [OvernightGaugeModel]
    var sleepOverrideCaption: String? = nil
    var pulseScores: Bool = false
    var animated: Bool = true
    /// When set, each gauge opens the screen behind it.
    var onSelect: ((V1TodaySignalKey) -> Void)?

    var body: some View {
        HStack(alignment: .top, spacing: SharpitSpacing.sm) {
            ForEach(gauges) { gauge in
                let override = (gauge.key == .sleep) ? sleepOverrideCaption : nil
                if let onSelect {
                    Button { onSelect(gauge.key) } label: {
                        OvernightGaugeCell(
                            gauge: gauge,
                            overrideCaption: override,
                            pulse: pulseScores,
                            opensDetail: true,
                            animated: animated
                        )
                    }
                    .buttonStyle(.sharpitPressable)
                    .accessibilityAddTraits(.isButton)
                    .frame(maxWidth: .infinity)
                } else {
                    OvernightGaugeCell(
                        gauge: gauge,
                        overrideCaption: override,
                        pulse: pulseScores,
                        animated: animated
                    )
                    .frame(maxWidth: .infinity)
                }
            }
        }
    }
}

/// One overnight readout, as the sleep reference card at half width: compact icon-tile header,
/// the 270° tick dial with the score in its centre, and the night's figure in a chip below.
private struct OvernightGaugeCell: View {
    let gauge: OvernightGaugeModel
    var overrideCaption: String? = nil
    var pulse: Bool = false
    var opensDetail = false
    var animated: Bool = true

    @State private var displayedScore: CGFloat?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(
        gauge: OvernightGaugeModel,
        overrideCaption: String? = nil,
        pulse: Bool = false,
        opensDetail: Bool = false,
        animated: Bool = true
    ) {
        self.gauge = gauge
        self.overrideCaption = overrideCaption
        self.pulse = pulse
        self.opensDetail = opensDetail
        self.animated = animated
        let target = AnimatedScoreText.progressFraction(from: gauge.score).map { CGFloat($0 * 100) }
        _displayedScore = State(initialValue: animated ? nil : target)
    }

    /// Dial maximum width to give proper margin within the card.
    private let dialMaxWidth: CGFloat = 146

    private var targetScore: CGFloat? {
        AnimatedScoreText.progressFraction(from: gauge.score).map { CGFloat($0 * 100) }
    }

    private var displayCaption: String? {
        guard var text = (overrideCaption ?? gauge.caption) else { return nil }
        if gauge.key == .recovery {
            text = text.replacingOccurrences(of: "VFC", with: String(localized: "Système nerveux"))
            text = text.replacingOccurrences(of: "vfc", with: String(localized: "Système nerveux"))
        }
        return text
    }

    var body: some View {
        VStack(spacing: 0) {
            header

            Spacer(minLength: SharpitSpacing.sm)

            dial

            Spacer(minLength: SharpitSpacing.sm)

            footCaption
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, SharpitSpacing.sm + 2)
        .padding(.vertical, SharpitSpacing.md)
        .sharpitSurface(.panel)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
        .onAppear { reveal(to: targetScore) }
        .onChange(of: gauge.score) { _, _ in reveal(to: targetScore) }
    }

    private var header: some View {
        SharpitCardHeader(title: title, symbol: gauge.key.instrumentSymbol, showsChevron: opensDetail, isCompact: true)
    }

    private var dial: some View {
        SharpitTickGauge(score: displayedScore)
            .sharpitDialCentre { readout }
        .frame(maxWidth: dialMaxWidth)
        .aspectRatio(SharpitTickGaugeGeometry.aspectRatio, contentMode: .fit)
    }

    private var readout: some View {
        VStack(spacing: 1) {
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

    private var footCaption: some View {
        Group {
            if let caption = displayCaption, !caption.isEmpty {
                if let bullet = caption.range(of: "·") {
                    SharpitTelemetryCapsule(
                        lead: String(caption[..<bullet.lowerBound]).trimmingCharacters(in: .whitespaces),
                        value: String(caption[bullet.upperBound...]).trimmingCharacters(in: .whitespaces)
                    )
                } else {
                    SharpitTelemetryCapsule(lead: caption)
                }
            } else {
                Color.clear
                    .frame(height: 24)
            }
        }
    }

    private var scoreDisplay: String {
        guard let displayedScore else { return "—" }
        return String(Int(displayedScore.rounded()))
    }

    private func reveal(to value: CGFloat?) {
        guard animated, !SharpitMotion.reduceMotion, !reduceMotion else {
            displayedScore = value
            return
        }
        SharpitMotion.run(SharpitMotion.gaugeFill) {
            displayedScore = value
        }
    }

    private var accessibilityLabel: String {
        [title, String(localized: "\(gauge.score) sur 100"), displayCaption]
            .compactMap { $0 }
            .filter { !$0.isEmpty }
            .joined(separator: ", ")
    }

    private var title: String {
        switch gauge.key {
        case .sleep: String(localized: "Sommeil")
        case .recovery: String(localized: "Récupération")
        case .effort, .adaptation, .stress: gauge.key.instrumentLabel
        }
    }
}

#Preview("Overnight Gauge Pair") {
    VStack(spacing: 20) {
        OvernightGaugePair(
            gauges: [
                OvernightGaugeModel(key: .sleep, score: "79", caption: String(localized: "Nuit dernière · 6h 54m")),
                OvernightGaugeModel(key: .recovery, score: "20", caption: String(localized: "Frein · VFC")),
            ],
            sleepOverrideCaption: String(localized: "Manque · 1 h 06"),
            onSelect: { _ in }
        )
    }
    .padding()
    .background(SharpitColor.background)
}
