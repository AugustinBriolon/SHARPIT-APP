import SwiftUI

/// The arithmetic behind the progress readouts, kept pure so it is tested apart from drawing.
enum SharpitProgressMath {
    /// A fraction held to 0…1; a non-finite value reads as empty.
    static func clamped(_ fraction: Double) -> Double {
        guard fraction.isFinite else { return 0 }
        return min(max(fraction, 0), 1)
    }

    /// How far `current` has travelled from `start` toward `goal`, 0…1.
    /// Works both ways: a time going down toward a faster goal, a load going up.
    static func fraction(start: Double, current: Double, goal: Double) -> Double {
        guard goal != start else { return current == goal ? 1 : 0 }
        return clamped((current - start) / (goal - start))
    }
}

/// A labelled bar: a muted label left, a bold value right, then a rounded bar on the track.
/// Lime for progress toward something (« Prochain palier »), ink for a breakdown row.
struct SharpitProgressBar: View {
    enum Style {
        case lime
        case ink
    }

    var label: String?
    var value: String?
    let fraction: Double
    var style: Style = .lime

    @ScaledMetric(relativeTo: .body) private var thickness: CGFloat = SharpitTokens.barThickness

    var body: some View {
        VStack(alignment: .leading, spacing: SharpitSpacing.sm) {
            if label != nil || value != nil {
                HStack(alignment: .firstTextBaseline) {
                    if let label {
                        Text(label)
                            .font(SharpitTypography.system(size: 16, weight: .regular, relativeTo: .body))
                            .foregroundStyle(SharpitColor.slate)
                    }
                    Spacer(minLength: SharpitSpacing.xs)
                    if let value {
                        Text(value)
                            .font(SharpitTypography.system(size: 16, weight: .semibold, relativeTo: .body, digits: true))
                            .foregroundStyle(SharpitColor.foreground)
                    }
                }
                .lineLimit(1)
            }
            SharpitBarTrack(fraction: fraction, tone: SharpitColor.foreground)
                .frame(height: thickness)
        }
        .accessibilityElement(children: .combine)
    }
}

/// The bare bar: a capsule fill over a capsule track.
struct SharpitBarTrack: View {
    let fraction: Double
    var tone: Color = SharpitColor.foreground

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(SharpitColor.divider)
                Capsule()
                    .fill(tone)
                    .frame(width: proxy.size.width * SharpitProgressMath.clamped(fraction))
            }
        }
        .accessibilityHidden(true)
    }
}
