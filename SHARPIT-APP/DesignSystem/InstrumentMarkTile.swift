import SwiftUI

/// Icon-first glass tile — primary visual unit for shell destinations.
struct InstrumentMarkTile: View {
    let symbolName: String
    let label: String
    var dimmed: Bool = true

    var body: some View {
        VStack(spacing: SharpitSpacing.xs) {
            Image(systemName: symbolName)
                .font(.system(size: 28, weight: .medium))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(dimmed ? AnyShapeStyle(.secondary) : AnyShapeStyle(.primary))
                .frame(height: 36)
            Text(label)
                .font(SharpitTypography.label())
                .tracking(SharpitTypography.labelTracking)
                .textCase(.uppercase)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, SharpitSpacing.md)
        .padding(.horizontal, SharpitSpacing.xxs)
        .sharpitGlassCard()
        .accessibilityElement(children: .combine)
        .accessibilityLabel(label)
    }
}

struct InstrumentHeroMark: View {
    let symbolName: String
    let cue: String

    var body: some View {
        VStack(spacing: SharpitSpacing.md) {
            Image(systemName: symbolName)
                .font(.system(size: 64, weight: .ultraLight))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(.primary.opacity(0.85))
            Text(cue)
                .font(SharpitTypography.eyebrow())
                .tracking(SharpitTypography.eyebrowTracking)
                .textCase(.uppercase)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, SharpitSpacing.lg)
        .padding(.bottom, SharpitSpacing.xs)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(cue)
    }
}
