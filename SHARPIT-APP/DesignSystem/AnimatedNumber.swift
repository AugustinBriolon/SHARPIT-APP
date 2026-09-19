import SwiftUI

struct AnimatedNumber: View {
    let value: Double
    var decimals: Int = 0
    var font: Font = SharpitTypography.data
    var animation: Animation = .easeOut(duration: SharpitMotion.countUpDuration)

    @State private var displayed: Double = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Text(formatted(displayed))
            .font(font)
            .monospacedDigit()
            .contentTransition(reduceMotion ? .identity : .numericText())
            .onAppear { snapOrAnimate(to: value) }
            .onChange(of: value) { _, newValue in
                snapOrAnimate(to: newValue)
            }
    }

    private func snapOrAnimate(to target: Double) {
        if SharpitMotion.reduceMotion || reduceMotion {
            displayed = target
            return
        }
        SharpitMotion.run(animation) {
            displayed = target
        }
    }

    private func formatted(_ number: Double) -> String {
        if decimals <= 0 {
            return String(Int(number.rounded()))
        }
        return String(format: "%.\(decimals)f", number)
    }
}

struct AnimatedScoreText: View {
    let score: String
    var animation: Animation = .easeOut(duration: SharpitMotion.countUpDuration)

    var body: some View {
        if let numeric = Self.parse(score) {
            AnimatedNumber(value: numeric.value, decimals: numeric.decimals, animation: animation)
        } else {
            Text(score)
                .font(SharpitTypography.data)
                .monospacedDigit()
        }
    }

    static func parse(_ score: String) -> (value: Double, decimals: Int)? {
        let normalized = score.replacingOccurrences(of: ",", with: ".")
        guard let value = Double(normalized.filter { $0.isNumber || $0 == "." || $0 == "-" }) else {
            return nil
        }
        let decimals = normalized.split(separator: ".").count > 1
            ? (normalized.split(separator: ".").last?.count ?? 0)
            : 0
        return (value, min(decimals, 2))
    }

    static func progressFraction(from score: String) -> Double? {
        guard let parsed = parse(score) else { return nil }
        // Scores like effort 1.8 stay unmapped to 0–100; only 0…100 style indices.
        if parsed.value >= 0, parsed.value <= 100, parsed.decimals == 0 || parsed.value >= 10 {
            return min(max(parsed.value / 100, 0), 1)
        }
        if parsed.value > 0, parsed.value <= 1 {
            return parsed.value
        }
        return nil
    }
}
