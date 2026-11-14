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
            case .heartRate: String(localized: "Fréquence cardiaque")
            case .speed: String(localized: "Vitesse")
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
    /// The session's own 10th and 90th percentiles, in the sample's unit (bpm, m/s): where the
    /// easiest and the hardest colours start.
    let low: Double
    let high: Double

    /// The signals this recording can colour the route by, heart rate first.
    static func metrics(in samples: [V1ActivityStreamSample]) -> [Metric] {
        [Metric.heartRate, .speed].filter { metric in
            samples.filter { value(of: $0, metric) != nil }.count * 2 >= max(samples.count, 1)
        }
    }

    /// Nil when there is no route, or no signal that varies along it. Without a metric asked
    /// for, the first the recording carries.
    static func make(
        route: [V1ActivityCoordinate],
        samples: [V1ActivityStreamSample],
        metric asked: Metric? = nil
    ) -> RouteIntensity? {
        let carried = metrics(in: samples)
        guard route.count >= 2, !samples.isEmpty,
              let metric = asked ?? carried.first, carried.contains(metric) else { return nil }
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
        return RouteIntensity(metric: metric, segments: segments(route: route, levels: fillGaps(pointLevels)), low: low, high: high)
    }

    static func level(of value: Double, low: Double, high: Double) -> Int {
        let share = (value - low) / (high - low)
        return min(max(Int(share * Double(levels)), 0), levels - 1)
    }

    /// « 128 – 171 bpm », « 4'11" – 5'02" /km » for a run, « 24,5 – 33,0 km/h » otherwise: what
    /// the colours span, easiest first.
    @MainActor func rangeText(asPace: Bool) -> String {
        switch metric {
        case .heartRate:
            return "\(Int(low.rounded())) – \(Int(high.rounded())) bpm"
        case .speed where asPace:
            return "\(ActivityFormat.paceClock(1_000 / low)) – \(ActivityFormat.paceClock(1_000 / high)) /km"
        case .speed:
            let kmh = { (speed: Double) in String(format: "%.1f", speed * 3.6).replacingOccurrences(of: ".", with: ",") }
            return "\(kmh(low)) – \(kmh(high)) km/h"
        }
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

/// How the expanded map draws the route: by heart rate, by speed, or in the sport's one colour.
enum RouteColouring: Hashable, Sendable {
    case heartRate
    case speed
    case plain

    var metric: RouteIntensity.Metric? {
        switch self {
        case .heartRate: .heartRate
        case .speed: .speed
        case .plain: nil
        }
    }

    /// The choices a recording offers, « Uni » last; empty when it has nothing to colour by.
    static func options(for metrics: [RouteIntensity.Metric]) -> [RouteColouring] {
        metrics.isEmpty ? [] : metrics.map { $0 == .heartRate ? .heartRate : .speed } + [.plain]
    }
}
