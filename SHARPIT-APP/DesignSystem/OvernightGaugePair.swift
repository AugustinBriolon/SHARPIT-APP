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

/// One overnight readout, composed with Apple-grade hierarchy and Golden Ratio spatial balance:
/// - Header: tinted micro-badge icon + uppercase category label + subtle disclosure chevron
/// - Center: preserved 52-tick gauge arc with nested tabular score and refined sub-label
/// - Footer: structured telemetry capsule highlighting key metrics (e.g. sleep duration, HRV)
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
            text = text.replacingOccurrences(of: "VFC", with: "Système nerveux")
            text = text.replacingOccurrences(of: "vfc", with: "Système nerveux")
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
        .padding(.vertical, SharpitSpacing.sm + 2)
        .sharpitSurface(.panel)
        .sharpitCardSpecularBorder()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
        .onAppear { reveal(to: targetScore) }
        .onChange(of: gauge.score) { _, _ in reveal(to: targetScore) }
    }

    private var header: some View {
        HStack(spacing: 6) {
            ZStack {
                Circle()
                    .fill(tintColor.opacity(0.12))
                    .frame(width: 22, height: 22)
                Image(systemName: gauge.key.instrumentSymbol)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(tintColor)
            }

            Text(title)
                .font(SharpitTypography.label)
                .tracking(SharpitTypography.labelTracking)
                .textCase(.uppercase)
                .foregroundStyle(SharpitColor.foreground.opacity(0.85))
                .lineLimit(1)
                .minimumScaleFactor(0.75)

            Spacer(minLength: 2)

            if opensDetail {
                Image(systemName: "chevron.right")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(SharpitColor.mutedForeground.opacity(0.45))
                    .accessibilityHidden(true)
            }
        }
        .frame(maxWidth: .infinity)
    }

    private var tintColor: Color {
        switch gauge.key {
        case .sleep:
            SharpitColor.primary
        case .recovery:
            SharpitColor.signalRecovery
        case .effort, .adaptation:
            SharpitColor.primary
        }
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

    /// Approximate height of the score block, used to hang it from its top edge.
    private var readoutHeight: CGFloat { 50 }

    private var readout: some View {
        VStack(spacing: 1) {
            Text(scoreDisplay)
                .font(SharpitTypography.gaugeScore)
                .tracking(SharpitTypography.gaugeScoreTracking)
                .foregroundStyle(SharpitColor.foreground)
                .opacity(displayedScore == nil ? 0.45 : (pulse ? 0.55 : 1))
                .contentTransition(reduceMotion ? .identity : .numericText())
            Text("sur 100")
                .font(.system(size: 11, weight: .medium, design: .rounded))
                .foregroundStyle(SharpitColor.mutedForeground.opacity(0.85))
        }
    }

    private var footCaption: some View {
        Group {
            if let caption = displayCaption, !caption.isEmpty {
                HStack(spacing: 3) {
                    if let bulletRange = caption.range(of: "·") {
                        let prefix = String(caption[..<bulletRange.lowerBound]).trimmingCharacters(in: .whitespaces)
                        let suffix = String(caption[bulletRange.upperBound...]).trimmingCharacters(in: .whitespaces)

                        Text(prefix)
                            .font(.system(size: 11, weight: .regular))
                            .foregroundStyle(SharpitColor.mutedForeground)
                            .lineLimit(1)

                        Text("·")
                            .font(.system(size: 11, weight: .regular))
                            .foregroundStyle(SharpitColor.mutedForeground.opacity(0.4))

                        Text(suffix)
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(SharpitColor.foreground)
                            .lineLimit(1)
                    } else {
                        Text(caption)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(SharpitColor.mutedForeground)
                            .lineLimit(1)
                    }
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .frame(maxWidth: .infinity)
                .background(
                    Capsule(style: .continuous)
                        .fill(SharpitColor.secondary.opacity(0.55))
                        .overlay(
                            Capsule(style: .continuous)
                                .strokeBorder(SharpitColor.border.opacity(0.06), lineWidth: 0.5)
                        )
                )
            } else {
                Color.clear
                    .frame(height: 24)
            }
        }
        .frame(height: 24)
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
        [title, "\(gauge.score) sur 100", displayCaption]
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

#Preview("Overnight Gauge Pair") {
    VStack(spacing: 20) {
        OvernightGaugePair(
            gauges: [
                OvernightGaugeModel(key: .sleep, score: "79", caption: "Nuit dernière · 6h 54m"),
                OvernightGaugeModel(key: .recovery, score: "20", caption: "Frein · VFC"),
            ],
            sleepOverrideCaption: "Manque · 1 h 06",
            onSelect: { _ in }
        )
    }
    .padding()
    .background(SharpitColor.background)
}
