import SwiftUI

/// Opaque cover while the app is not active — the app switcher must not show health data.
struct PrivacyMaskView: View {
    var body: some View {
        ZStack {
            Color(.systemBackground)
                .ignoresSafeArea()
            VStack(spacing: SharpitSpacing.md) {
                SharpitLaunchMark()
                Text("SharpIt")
                    .font(.custom(
                        SharpitFontFamily.heading.resolvedName(for: .bold) ?? "System",
                        size: 34,
                        relativeTo: .largeTitle
                    ))
                    .tracking(-0.8)
                    .foregroundStyle(Color.primary)
            }
        }
        .accessibilityHidden(true)
    }
}
