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
                            .foregroundStyle(SharpitColor.mutedForeground)
                    }
                    Spacer(minLength: SharpitSpacing.xs)
                    if let value {
                        Text(value)
                            .font(SharpitTypography.system(size: 16, weight: .bold, relativeTo: .body, digits: true))
                            .foregroundStyle(SharpitColor.foreground)
                    }
                }
                .lineLimit(1)
            }
            SharpitBarTrack(fraction: fraction, tone: style == .lime ? SharpitColor.highlight : SharpitColor.foreground)
                .frame(height: thickness)
        }
        .accessibilityElement(children: .combine)
    }
}

/// The bare bar: a capsule fill over a capsule track.
struct SharpitBarTrack: View {
    let fraction: Double
    var tone: Color = SharpitColor.highlight

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(SharpitColor.track)
                Capsule()
                    .fill(tone)
                    .frame(width: proxy.size.width * SharpitProgressMath.clamped(fraction))
            }
        }
        .accessibilityHidden(true)
    }
}

/// From a previous best to the next goal, with where the athlete stands now: a lime run up
/// to a hollow knob, an ink bubble above it, and the two ends written under the track.
struct SharpitGoalTrack: View {
    let fraction: Double
    let nowLabel: String
    let nowValue: String
    let startValue: String
    let startLabel: String
    let goalValue: String
    let goalLabel: String

    @ScaledMetric(relativeTo: .body) private var thickness: CGFloat = 10
    @ScaledMetric(relativeTo: .body) private var knob: CGFloat = 20

    var body: some View {
        VStack(spacing: SharpitSpacing.md) {
            GeometryReader { proxy in
                let position = proxy.size.width * SharpitProgressMath.clamped(fraction)
                ZStack(alignment: .leading) {
                    Capsule().fill(SharpitColor.track).frame(height: thickness)
                    Capsule().fill(SharpitColor.highlight).frame(width: position, height: thickness)
                    Circle()
                        .fill(SharpitColor.card)
                        .overlay(Circle().strokeBorder(SharpitColor.foreground, lineWidth: 2.5))
                        .frame(width: knob, height: knob)
                        .offset(x: min(max(position - knob / 2, 0), proxy.size.width - knob))
                    bubble
                        .fixedSize()
                        .alignmentGuide(.leading) { $0[HorizontalAlignment.center] - position }
                        .offset(y: -(knob / 2 + 26))
                }
                .frame(maxHeight: .infinity, alignment: .bottom)
            }
            .frame(height: knob + 44)

            HStack(alignment: .top) {
                end(value: startValue, label: startLabel, alignment: .leading)
                Spacer()
                end(value: goalValue, label: goalLabel, alignment: .trailing)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(nowLabel) \(nowValue), \(startLabel) \(startValue), \(goalLabel) \(goalValue)")
    }

    private var bubble: some View {
        HStack(spacing: 4) {
            Text(nowLabel).foregroundStyle(SharpitColor.inkSurfaceForeground.opacity(0.7))
            Text(nowValue).fontWeight(.bold).foregroundStyle(SharpitColor.inkSurfaceForeground)
        }
        .font(SharpitTypography.system(size: 15, weight: .medium, relativeTo: .subheadline, digits: true))
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .sharpitConcentricBackground(SharpitColor.inkSurface, minimum: 12)
    }

    private func end(value: String, label: String, alignment: HorizontalAlignment) -> some View {
        VStack(alignment: alignment, spacing: 4) {
            Text(value)
                .font(SharpitTypography.system(size: 17, weight: .bold, relativeTo: .headline, digits: true))
                .foregroundStyle(SharpitColor.foreground)
            Text(label)
                .font(SharpitTypography.system(size: 15, weight: .regular, relativeTo: .subheadline))
                .foregroundStyle(SharpitColor.mutedForeground)
        }
    }
}
