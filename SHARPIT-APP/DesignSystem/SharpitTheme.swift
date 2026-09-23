import SwiftUI

/// Optical ratios for divisions *inside* a component.
///
/// φ used to be this app's spacing law. It is not any more (ADR-041): a 13 / 21 / 34 pt
/// ladder fights UIKit's 4/8 pt grid and the system layout margins, and the mismatch is
/// what read as unfinished. φ keeps the job it is good at — splitting the air inside a
/// gauge or a plate — and `SharpitSpacing` owns the space between things.
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

    static func rounded(_ value: CGFloat) -> CGFloat { value.rounded() }
}

/// Spacing on the Apple 4/8 pt grid, named after the web's density tiers.
///
/// `design.md` describes three densities — dense for metrics (12–16), standard for
/// panels (20–24), airy for explanations (32–48). The ladder below is those tiers
/// snapped to the grid the platform already aligns everything else to.
enum SharpitSpacing {
    /// Hairline gaps inside a control.
    static let xxs: CGFloat = 4
    /// Dense — between a figure and its label.
    static let xs: CGFloat = 8
    /// Dense — between rows of metrics.
    static let sm: CGFloat = 12
    /// Standard — panel padding, the default gap.
    static let md: CGFloat = 16
    /// Standard — between sections of a screen.
    static let lg: CGFloat = 24
    /// Airy — around an explanation, or below the last section.
    static let xl: CGFloat = 32

    /// System layout margin on iPhone; screen content aligns to it.
    static let pageInset: CGFloat = md
    /// Gap between the causal-column sections of a screen.
    static let section: CGFloat = lg
    static let cardPadding: CGFloat = md
    /// The Human Interface Guidelines' smallest tappable size, in points (`docs/adr/0008`).
    static let minimumTouchTarget: CGFloat = 44

    /// `BRAND.radius` — the web card radius, exported to Swift.
    static let cardRadius: CGFloat = SharpitTokens.radius
    /// Radius for chips and other controls nested inside a card.
    static let chipRadius: CGFloat = SharpitTokens.radius * 0.75
}

/// Hairline weights. The web draws its separation with a 1px border, not a shadow.
enum SharpitStroke {
    static let hairline: CGFloat = 1
}

/// Posture colors, mapped onto the web's semantic signal tokens.
///
/// `design.md`: colour is emotional state, and `RECOVER` uses protective sage — never
/// punitive red. So `protect` takes caution amber, not `signalRisk`.
enum SharpitPostureStyle {
    static func color(for posture: V1TodayPosture) -> Color {
        switch posture {
        case .protect: SharpitColor.signalCaution
        case .steady: SharpitColor.primary
        case .push: SharpitColor.signalRecovery
        case .uncertain: SharpitColor.signalNeutral
        }
    }
}
