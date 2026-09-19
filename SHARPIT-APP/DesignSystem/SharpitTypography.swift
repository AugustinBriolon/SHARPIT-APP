import SwiftUI
import UIKit

/// The brand typefaces, as embedded in the app bundle.
///
/// The web design system carries its identity in three families (ADR-041): Syne for
/// every heading and the verdict, IBM Plex Sans for prose, JetBrains Mono with tabular
/// figures for every number. Until the font files are added to `Resources/Fonts` and
/// declared in `UIAppFonts`, `resolvedName` returns `nil` and the ramp falls back to the
/// system face — the layout is correct, only the identity is missing.
enum SharpitFontFamily {
    case heading
    case body
    case data

    /// PostScript names, in the order the ramp asks for them.
    private var postScriptNames: [SharpitFontWeight: String] {
        switch self {
        case .heading:
            [.medium: "Syne-Medium", .semibold: "Syne-SemiBold", .bold: "Syne-Bold"]
        case .body:
            [
                .regular: "IBMPlexSans-Regular",
                .medium: "IBMPlexSans-Medium",
                .semibold: "IBMPlexSans-SemiBold",
            ]
        case .data:
            [.regular: "JetBrainsMono-Regular", .medium: "JetBrainsMono-Medium"]
        }
    }

    /// The registered PostScript name, or `nil` when the family is not in the bundle.
    func resolvedName(for weight: SharpitFontWeight) -> String? {
        guard let name = postScriptNames[weight] else { return nil }
        return UIFont(name: name, size: 12) == nil ? nil : name
    }

    /// True once every weight of this family is available to the text system.
    var isEmbedded: Bool {
        postScriptNames.keys.allSatisfy { resolvedName(for: $0) != nil }
    }
}

enum SharpitFontWeight {
    case regular
    case medium
    case semibold
    case bold

    var system: Font.Weight {
        switch self {
        case .regular: .regular
        case .medium: .medium
        case .semibold: .semibold
        case .bold: .bold
        }
    }
}

/// The web type ramp, expressed natively.
///
/// Sizes mirror the `@utility` declarations in `globals.css` at the phone breakpoint —
/// the web renders `text-verdict` at 20pt below `40rem`, and an iPhone is narrower than
/// that, so these are the sizes the athlete already reads. Every style scales with
/// Dynamic Type through its `relativeTo:` text style.
enum SharpitTypography {
    /// `text-verdict` — the plate headline.
    static var verdict: Font { heading(size: 20, weight: .semibold, relativeTo: .title2) }
    static var verdictTracking: CGFloat { tracking(em: -0.02, size: 20) }

    /// `text-page-title`
    static var pageTitle: Font { heading(size: 24, weight: .semibold, relativeTo: .title) }
    static var pageTitleTracking: CGFloat { tracking(em: -0.02, size: 24) }

    /// `text-section-title`
    static var sectionTitle: Font { heading(size: 18, weight: .semibold, relativeTo: .title3) }
    static var sectionTitleTracking: CGFloat { tracking(em: -0.015, size: 18) }

    /// `text-card-title`
    static var cardTitle: Font { heading(size: 16, weight: .medium, relativeTo: .headline) }
    static var cardTitleTracking: CGFloat { tracking(em: -0.01, size: 16) }

    /// Body prose — IBM Plex Sans.
    static var body: Font { prose(size: 16, weight: .regular, relativeTo: .body) }
    static var bodyEmphasis: Font { prose(size: 16, weight: .medium, relativeTo: .body) }

    /// `text-meta` — caption tier, the floor for text that is read rather than classified.
    static var meta: Font { prose(size: 12, weight: .regular, relativeTo: .caption) }

    /// `text-label` — uppercase, tracked, muted. Classification, never prose.
    static var label: Font { prose(size: 11, weight: .semibold, relativeTo: .caption2) }
    static var labelTracking: CGFloat { tracking(em: 0.08, size: 11) }

    /// Eyebrow — a label used as a section marker.
    static var eyebrow: Font { label }
    static var eyebrowTracking: CGFloat { labelTracking }

    /// `text-instrument` — a number read at body size.
    static var instrument: Font { instrument(size: 16, weight: .regular, relativeTo: .body) }

    /// `text-data` — the score tier, the largest figures on a plate.
    static var data: Font { instrument(size: 20, weight: .medium, relativeTo: .title3) }
    static var dataTracking: CGFloat { tracking(em: -0.02, size: 20) }

    /// CSS tracking is relative to the font size; SwiftUI's is absolute.
    static func tracking(em: CGFloat, size: CGFloat) -> CGFloat {
        em * size
    }

    // MARK: - Family resolution

    private static func heading(
        size: CGFloat,
        weight: SharpitFontWeight,
        relativeTo style: Font.TextStyle
    ) -> Font {
        font(.heading, size: size, weight: weight, relativeTo: style)
    }

    private static func prose(
        size: CGFloat,
        weight: SharpitFontWeight,
        relativeTo style: Font.TextStyle
    ) -> Font {
        font(.body, size: size, weight: weight, relativeTo: style)
    }

    private static func instrument(
        size: CGFloat,
        weight: SharpitFontWeight,
        relativeTo style: Font.TextStyle
    ) -> Font {
        guard SharpitFontFamily.data.resolvedName(for: weight) != nil else {
            // Monospaced digits are the point of this tier; keep them even in fallback.
            return .system(style, design: .monospaced).weight(weight.system)
        }
        return font(.data, size: size, weight: weight, relativeTo: style)
    }

    private static func font(
        _ family: SharpitFontFamily,
        size: CGFloat,
        weight: SharpitFontWeight,
        relativeTo style: Font.TextStyle
    ) -> Font {
        guard let name = family.resolvedName(for: weight) else {
            return .system(style).weight(weight.system)
        }
        return .custom(name, size: size, relativeTo: style)
    }
}
