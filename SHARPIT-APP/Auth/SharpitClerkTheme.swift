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
                title: .custom(SharpitFontFamily.heading.resolvedName(for: .bold) ?? "System", size: 24, relativeTo: .title),
                title2: .custom(SharpitFontFamily.heading.resolvedName(for: .semibold) ?? "System", size: 20, relativeTo: .title2),
                headline: .custom(SharpitFontFamily.heading.resolvedName(for: .semibold) ?? "System", size: 17, relativeTo: .headline),
                subheadline: .custom(SharpitFontFamily.body.resolvedName(for: .medium) ?? "System", size: 15, relativeTo: .subheadline),
                body: .custom(SharpitFontFamily.body.resolvedName(for: .regular) ?? "System", size: 16, relativeTo: .body),
                callout: .custom(SharpitFontFamily.body.resolvedName(for: .medium) ?? "System", size: 15, relativeTo: .callout),
                footnote: .custom(SharpitFontFamily.body.resolvedName(for: .regular) ?? "System", size: 13, relativeTo: .footnote),
                caption: .custom(SharpitFontFamily.body.resolvedName(for: .regular) ?? "System", size: 12, relativeTo: .caption)
            ),
            design: .init(
                borderRadius: SharpitTokens.radius
            )
        )
    }
}
