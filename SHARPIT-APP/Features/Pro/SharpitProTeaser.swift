import SwiftUI

/// Where something SHARPIT adds (an analysis, a computed metric) would sit, below SharpIt Pro:
/// its name, what it brings, and the way to Pro. The athlete's own data is never behind one.
struct SharpitProTeaser: View {
    let title: String
    let message: String

    @Environment(ProStore.self) private var pro: ProStore?

    var body: some View {
        if let pro {
            NavigationLink {
                ProView(store: pro)
            } label: {
                content
            }
            .buttonStyle(.sharpitPressable)
            .accessibilityHint("Ouvre SharpIt Pro")
        } else {
            content
        }
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: SharpitSpacing.sm) {
            HStack(spacing: SharpitSpacing.xs) {
                SharpitEyebrow(title)
                Spacer(minLength: 0)
                Text("Pro")
                    .font(SharpitTypography.label)
                    .tracking(SharpitTypography.labelTracking)
                    .textCase(.uppercase)
                    .foregroundStyle(SharpitColor.highlightForeground)
                    .padding(.horizontal, SharpitSpacing.xs)
                    .padding(.vertical, 2)
                    .background(SharpitColor.highlight, in: Capsule())
                Image(systemName: "chevron.right")
                    .font(SharpitTypography.label)
                    .foregroundStyle(SharpitColor.mutedForeground.opacity(0.6))
                    .accessibilityHidden(true)
            }
            Text(message)
                .font(SharpitTypography.body)
                .foregroundStyle(SharpitColor.mutedForeground)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(SharpitSpacing.cardPadding)
        .sharpitSurface(.panel)
        .accessibilityElement(children: .combine)
    }
}
