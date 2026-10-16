import SwiftUI
import UIKit

/// Font weights the ramp uses, mapped onto SF Pro.
enum SharpitFontWeight {
    case regular
    case medium
    case semibold
    case bold
    case heavy

    var system: Font.Weight {
        switch self {
        case .regular: .regular
        case .medium: .medium
        case .semibold: .semibold
        case .bold: .bold
        case .heavy: .heavy
        }
    }

    var uiKit: UIFont.Weight {
        switch self {
        case .regular: .regular
        case .medium: .medium
        case .semibold: .semibold
        case .bold: .bold
        case .heavy: .heavy
        }
    }
}

/// The Ink & Lime type ramp (ADR-085): SF Pro throughout, heavy figures with tabular
/// digits, muted units. Every style scales with Dynamic Type through its text style.
enum SharpitTypography {
    /// `text-verdict` — the plate headline.
    static var verdict: Font { heading(size: 20, weight: .bold, relativeTo: .title2) }
    static var verdictTracking: CGFloat { tracking(em: -0.02, size: 20) }

    /// `text-page-title` so the date reads as the screen's title, not a section's.
    static var screenTitle: Font { heading(size: 32, weight: .bold, relativeTo: .largeTitle) }
    static var screenTitleTracking: CGFloat { tracking(em: -0.025, size: 32) }

    /// `text-page-title`
    static var pageTitle: Font { heading(size: 26, weight: .bold, relativeTo: .title) }
    static var pageTitleTracking: CGFloat { tracking(em: -0.02, size: 26) }

    /// `text-section-title`
    static var sectionTitle: Font { heading(size: 18, weight: .semibold, relativeTo: .title3) }
    static var sectionTitleTracking: CGFloat { tracking(em: -0.015, size: 18) }

    /// `text-card-title`
    static var cardTitle: Font { heading(size: 17, weight: .semibold, relativeTo: .headline) }
    static var cardTitleTracking: CGFloat { tracking(em: -0.01, size: 17) }

    /// Body prose.
    static var body: Font { prose(size: 16, weight: .regular, relativeTo: .body) }
    static var bodyEmphasis: Font { prose(size: 16, weight: .medium, relativeTo: .body) }

    /// `text-meta` — caption tier, the floor for text that is read rather than classified.
    static var meta: Font { prose(size: 13, weight: .regular, relativeTo: .caption) }

    /// `text-label` — uppercase, tracked, muted. Classification, never prose.
    static var label: Font { prose(size: 12, weight: .semibold, relativeTo: .caption2) }
    static var labelTracking: CGFloat { tracking(em: 0.06, size: 12) }

    /// Eyebrow — a label used as a section marker.
    static var eyebrow: Font { label }
    static var eyebrowTracking: CGFloat { labelTracking }

    /// `text-instrument` — a number read at body size.
    static var instrument: Font { instrument(size: 16, weight: .semibold, relativeTo: .body) }

    /// `text-data` — the score tier, the largest figures on a plate.
    static var data: Font { instrument(size: 20, weight: .bold, relativeTo: .title3) }
    static var dataTracking: CGFloat { tracking(em: -0.02, size: 20) }

    /// The gauge readout — a dial's number is the largest figure on its card.
    static var gaugeScore: Font { instrument(size: 34, weight: .heavy, relativeTo: .title) }
    static var gaugeScoreTracking: CGFloat { tracking(em: -0.03, size: 34) }

    /// A unit beside a figure ("kg", "minutes") — muted, at roughly a third of the hero.
    static var unit: Font { prose(size: 22, weight: .medium, relativeTo: .title3) }

    /// The one number a drill-down screen is about — the night's score, the day's readiness.
    static var heroScore: Font { instrument(size: 64, weight: .heavy, relativeTo: .largeTitle) }
    static var heroScoreTracking: CGFloat { tracking(em: -0.04, size: 64) }

    /// The one number a whole tab stands on — Santé's biological age. Twice a drill-down's hero,
    /// alone on its halo, never inside a card.
    static var showcaseScore: Font { instrument(size: 96, weight: .heavy, relativeTo: .largeTitle) }
    static var showcaseScoreTracking: CGFloat { tracking(em: -0.05, size: 96) }

    /// CSS tracking is relative to the font size; SwiftUI's is absolute.
    static func tracking(em: CGFloat, size: CGFloat) -> CGFloat {
        em * size
    }

    // MARK: - Resolution

    /// SF Pro at a fixed design size, scaled with Dynamic Type through `style`.
    /// `digits` switches to tabular figures so numbers do not jitter as they change.
    static func system(
        size: CGFloat,
        weight: SharpitFontWeight,
        relativeTo style: Font.TextStyle = .body,
        digits: Bool = false
    ) -> Font {
        let base = UIFont.systemFont(ofSize: size, weight: weight.uiKit)
        let scaled = UIFontMetrics(forTextStyle: style.uiKit).scaledFont(for: base)
        let font = Font(scaled)
        return digits ? font.monospacedDigit() : font
    }

    private static func heading(
        size: CGFloat,
        weight: SharpitFontWeight,
        relativeTo style: Font.TextStyle
    ) -> Font {
        system(size: size, weight: weight, relativeTo: style)
    }

    private static func prose(
        size: CGFloat,
        weight: SharpitFontWeight,
        relativeTo style: Font.TextStyle
    ) -> Font {
        system(size: size, weight: weight, relativeTo: style)
    }

    private static func instrument(
        size: CGFloat,
        weight: SharpitFontWeight,
        relativeTo style: Font.TextStyle
    ) -> Font {
        system(size: size, weight: weight, relativeTo: style, digits: true)
    }
}

private extension Font.TextStyle {
    var uiKit: UIFont.TextStyle {
        switch self {
        case .largeTitle: .largeTitle
        case .title: .title1
        case .title2: .title2
        case .title3: .title3
        case .headline: .headline
        case .subheadline: .subheadline
        case .callout: .callout
        case .footnote: .footnote
        case .caption: .caption1
        case .caption2: .caption2
        default: .body
        }
    }
}
