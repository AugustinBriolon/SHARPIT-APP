import SwiftUI

/// Golden-ratio foundation for SHARPIT layout, spacing, and optical divisions.
///
/// Every spatial relationship (padding ladders, section gaps, in-bowl score lift,
/// major/minor splits) must derive from `SharpitRatio` — never hardcode ad-hoc gaps
/// when a φ split or φ step expresses the same intent.
enum SharpitRatio {
    /// φ = (1 + √5) / 2
    static let phi: CGFloat = 1.618033988749895
    /// 1/φ ≈ 0.618 — major segment of a whole
    static let majorFactor: CGFloat = 1 / phi
    /// 1/φ² ≈ 0.382 — minor segment of a whole
    static let minorFactor: CGFloat = 1 / (phi * phi)

    /// Larger part of a φ split (≈ 61.8% of `whole`).
    static func major(of whole: CGFloat) -> CGFloat { whole * majorFactor }

    /// Smaller part of a φ split (≈ 38.2% of `whole`).
    static func minor(of whole: CGFloat) -> CGFloat { whole * minorFactor }

    /// `base * φ^power`, rounded to the nearest display point.
    static func step(_ base: CGFloat, power: Int) -> CGFloat {
        let value = base * Foundation.pow(phi, CGFloat(power))
        return value.rounded()
    }

    static func rounded(_ value: CGFloat) -> CGFloat { value.rounded() }
}

/// Spacing ladder derived from base 8 × φⁿ (with one octave step at `sm`).
enum SharpitSpacing {
    /// Rhythm root — all φ steps grow from here.
    static let base: CGFloat = 8

    static let xxs: CGFloat = base // 8
    static let xs: CGFloat = SharpitRatio.step(base, power: 1) // 13 ≈ 8φ
    static let sm: CGFloat = base * 2 // 16 — octave companion
    static let md: CGFloat = SharpitRatio.step(base, power: 2) // 21 ≈ 8φ²
    static let pageInset: CGFloat = md
    static let section: CGFloat = md
    static let lg: CGFloat = SharpitRatio.step(base, power: 3) // 34 ≈ 8φ³
    static let cardPadding: CGFloat = md
    /// Corner radius ≈ major segment of 40pt optical square.
    static let cardRadius: CGFloat = SharpitRatio.rounded(SharpitRatio.major(of: 40))
}

enum SharpitTypography {
    static func eyebrow() -> Font { .system(size: 11, weight: .semibold) }
    /// Tracking ≈ φ (optical, not geometric).
    static var eyebrowTracking: CGFloat { SharpitRatio.rounded(SharpitRatio.phi * 10) / 10 }
    static func verdict() -> Font { .system(size: 36, weight: .semibold) }
    static var verdictTracking: CGFloat { -0.8 }
    static func label() -> Font { .system(size: 10, weight: .semibold) }
    static var labelTracking: CGFloat { SharpitRatio.rounded(SharpitRatio.majorFactor * 10) / 10 }
    static func data() -> Font { .title3.monospacedDigit().weight(.semibold) }
}

enum SharpitPostureStyle {
    static func color(for posture: V1TodayPosture) -> Color {
        switch posture {
        case .protect: .orange
        case .steady: Color.accentColor
        case .push: .green
        case .uncertain: .secondary
        }
    }
}
