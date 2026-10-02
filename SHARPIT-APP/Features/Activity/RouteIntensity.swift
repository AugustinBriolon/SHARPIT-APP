import SwiftUI

/// The route cut into stretches by how hard each was: heart rate when the recording carries it,
/// else speed. The path and the samples are both thinned evenly from the same recording on the
/// server, so a point is matched to the sample at the same share of the session.
nonisolated struct RouteIntensity: Equatable, Sendable {
    enum Metric: Equatable, Sendable {
        case heartRate
        case speed

        var label: String {
            switch self {
            case .heartRate: "Fréquence cardiaque"
            case .speed: "Vitesse"
            }
        }
    }

    struct Segment: Equatable, Sendable {
        /// 0 (easiest) … `levels - 1` (hardest), relative to the session itself.
        let level: Int
        let coordinates: [V1ActivityCoordinate]
    }

    static let levels = 5

    let metric: Metric
    let segments: [Segment]

    /// Nil when there is no route, or no signal that varies along it.
    static func make(route: [V1ActivityCoordinate], samples: [V1ActivityStreamSample]) -> RouteIntensity? {
        guard route.count >= 2, !samples.isEmpty, let metric = metric(for: samples) else { return nil }
        let values = samples.map { value(of: $0, metric) }
        let known = values.compactMap { $0 }.sorted()
        let low = percentile(known, 0.10)
        let high = percentile(known, 0.90)
        guard high > low else { return nil }

        let pointLevels = route.indices.map { index -> Int? in
            let share = Double(index) / Double(route.count - 1)
            let sample = Int((share * Double(samples.count - 1)).rounded())
            return values[sample].map { level(of: $0, low: low, high: high) }
        }
        return RouteIntensity(metric: metric, segments: segments(route: route, levels: fillGaps(pointLevels)))
    }

    static func level(of value: Double, low: Double, high: Double) -> Int {
        let share = (value - low) / (high - low)
        return min(max(Int(share * Double(levels)), 0), levels - 1)
    }

    private static func metric(for samples: [V1ActivityStreamSample]) -> Metric? {
        let withHeartRate = samples.filter { ($0.hr ?? 0) > 0 }.count
        if withHeartRate * 2 >= samples.count { return .heartRate }
        let withSpeed = samples.filter { ($0.speed ?? 0) > 0 }.count
        return withSpeed * 2 >= samples.count ? .speed : nil
    }

    private static func value(of sample: V1ActivityStreamSample, _ metric: Metric) -> Double? {
        let raw = metric == .heartRate ? sample.hr : sample.speed
        guard let raw, raw > 0 else { return nil }
        return raw
    }

    private static func percentile(_ sorted: [Double], _ p: Double) -> Double {
        guard !sorted.isEmpty else { return 0 }
        return sorted[min(Int(Double(sorted.count - 1) * p), sorted.count - 1)]
    }

    /// A point without a reading takes the last known level, so the line never breaks.
    private static func fillGaps(_ levels: [Int?]) -> [Int] {
        var last = levels.compactMap { $0 }.first ?? 0
        return levels.map { level in
            if let level { last = level }
            return last
        }
    }

    /// Consecutive points of one level become one stretch; each stretch starts on the last point
    /// of the one before, so the colours join without a gap.
    private static func segments(route: [V1ActivityCoordinate], levels: [Int]) -> [Segment] {
        var result: [Segment] = []
        var current: [V1ActivityCoordinate] = [route[0]]
        var currentLevel = levels[0]
        for index in 1..<route.count {
            current.append(route[index])
            if levels[index] != currentLevel || index == route.count - 1 {
                result.append(Segment(level: currentLevel, coordinates: current))
                current = [route[index]]
                currentLevel = levels[index]
            }
        }
        return result
    }
}

/// The intensity family the training zones already use, easiest to hardest.
enum RouteIntensityTone {
    static func color(level: Int) -> Color {
        switch level {
        case 0: SharpitColor.signalRecovery
        case 1: SharpitColor.signalBase
        case 2: SharpitColor.signalTempo
        case 3: SharpitColor.signalThreshold
        default: SharpitColor.signalVo2
        }
    }
}

/// The key under the coloured route: what the colours measure, from easy to hard.
struct RouteIntensityLegend: View {
    let metric: RouteIntensity.Metric

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(metric.label)
                .font(SharpitTypography.label)
                .tracking(SharpitTypography.labelTracking)
                .textCase(.uppercase)
                .foregroundStyle(SharpitColor.mutedForeground)
            HStack(spacing: 2) {
                ForEach(0..<RouteIntensity.levels, id: \.self) { level in
                    Capsule().fill(RouteIntensityTone.color(level: level)).frame(height: 5)
                }
            }
            .frame(width: 140)
            HStack {
                Text("Facile")
                Spacer()
                Text("Intense")
            }
            .font(SharpitTypography.meta)
            .foregroundStyle(SharpitColor.mutedForeground)
            .frame(width: 140)
        }
        .padding(SharpitSpacing.sm)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: SharpitRadius.small, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Tracé coloré selon \(metric.label.lowercased()), de facile à intense")
    }
}
