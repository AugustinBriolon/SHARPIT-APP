import ClerkKit
import ClerkKitUI
import SwiftUI

extension ClerkTheme {
    /// The SharpIT brand theme for ClerkKitUI components.
    ///
    /// Customizes colors, typography, and corner radius across AuthView and UserProfileView
    /// to seamlessly blend with the athletic instrument design system.
    @MainActor
    static var sharpit: ClerkTheme {
        ClerkTheme(
            colors: .init(
                primary: SharpitColor.primary,
                switchTint: SharpitColor.highlight,
                background: SharpitColor.background,
                input: SharpitColor.card,
                danger: SharpitColor.destructive,
                success: SharpitColor.signalRecovery,
                warning: SharpitColor.signalCaution,
                foreground: SharpitColor.foreground,
                mutedForeground: SharpitColor.mutedForeground,
                primaryForeground: SharpitColor.primaryForeground,
                inputForeground: SharpitColor.foreground,
                neutral: SharpitColor.muted,
                ring: SharpitColor.highlight,
                muted: SharpitColor.muted,
                secondaryButtonBackground: SharpitColor.card,
                secondaryButtonForeground: SharpitColor.foreground,
                shadow: Color.black.opacity(0.06),
                border: SharpitColor.border
            ),
            fonts: .init(
                title: SharpitTypography.system(size: 24, weight: .bold, relativeTo: .title),
                title2: SharpitTypography.system(size: 20, weight: .semibold, relativeTo: .title2),
                headline: SharpitTypography.system(size: 17, weight: .semibold, relativeTo: .headline),
                subheadline: SharpitTypography.system(size: 15, weight: .medium, relativeTo: .subheadline),
                body: SharpitTypography.system(size: 16, weight: .regular, relativeTo: .body),
                callout: SharpitTypography.system(size: 15, weight: .medium, relativeTo: .callout),
                footnote: SharpitTypography.system(size: 13, weight: .regular, relativeTo: .footnote),
                caption: SharpitTypography.system(size: 12, weight: .regular, relativeTo: .caption)
            ),
            design: .init(
                borderRadius: SharpitTokens.radius
            )
        )
    }
}
