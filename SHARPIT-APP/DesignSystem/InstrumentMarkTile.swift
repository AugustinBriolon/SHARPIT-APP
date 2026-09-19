import SwiftUI

/// Icon-first tile — the primary visual unit for shell destinations that have no screen yet.
struct InstrumentMarkTile: View {
    let symbolName: String
    let label: String
    var dimmed: Bool = true

    var body: some View {
        VStack(spacing: SharpitSpacing.xs) {
            ZStack {
                Circle()
                    .fill(SharpitColor.accent)
                    .frame(width: 48, height: 48)

                Image(systemName: symbolName)
                    .font(.system(size: 24, weight: .medium))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(dimmed ? SharpitColor.mutedForeground : SharpitColor.primary)
            }

            Text(label)
                .font(SharpitTypography.label)
                .tracking(SharpitTypography.labelTracking)
                .textCase(.uppercase)
                .foregroundStyle(SharpitColor.mutedForeground)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, SharpitSpacing.md)
        .padding(.horizontal, SharpitSpacing.xs)
        .sharpitSurface(.panel)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(label)
    }
}

struct InstrumentHeroMark: View {
    let symbolName: String
    let cue: String

    var body: some View {
        VStack(spacing: SharpitSpacing.md) {
            ZStack {
                Circle()
                    .fill(SharpitColor.highlight)
                    .frame(width: 108, height: 108)

                Image(systemName: symbolName)
                    .font(.system(size: 42, weight: .semibold))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(SharpitColor.highlightForeground)
            }

            Text(cue)
                .font(SharpitTypography.eyebrow)
                .tracking(SharpitTypography.eyebrowTracking)
                .textCase(.uppercase)
                .foregroundStyle(SharpitColor.mutedForeground)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, SharpitSpacing.lg)
        .padding(.bottom, SharpitSpacing.xs)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(cue)
    }
}
