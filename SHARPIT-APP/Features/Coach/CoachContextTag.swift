import SwiftUI

/// The tag a contextual conversation carries.
///
/// It names what the coach was handed and lets the athlete drop it — that is the whole
/// contract (ADR-030). It is not a prefilled prompt: the question stays the athlete's,
/// the context only says what they were looking at when they asked.
struct CoachContextTag: View {
    let context: CoachDiscussContext
    /// Inside the composer's box: flat on the glass, no shadow of its own.
    var isInline = false
    var onDismiss: (() -> Void)?

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: context.tagSymbol)
                .font(SharpitTypography.meta)
                .foregroundStyle(SharpitColor.slate)
                .accessibilityHidden(true)

            Text(context.label)
                .font(SharpitTypography.meta.weight(.medium))
                .foregroundStyle(SharpitColor.foreground)
                .lineLimit(1)

            if let onDismiss {
                Button(action: onDismiss) {
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(SharpitColor.slate)
                        .frame(width: SharpitSpacing.minimumTouchTarget, height: SharpitSpacing.minimumTouchTarget)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.sharpitPressable)
                // The touch target overflows the tag; the glyph sits where the tag ends.
                .padding(.vertical, -12)
                .padding(.horizontal, -14)
                .accessibilityLabel("Retirer le contexte")
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background {
            // Flat: a soft fill, no outline — the tag names, it does not ask to be pressed.
            if isInline {
                Capsule().fill(SharpitColor.muted)
            } else {
                Capsule().fill(SharpitColor.tile).sharpitShadow(.control)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Contexte joint : \(context.label)")
    }
}

/// Shown on the Coach placeholder until the conversation itself exists: proof that the
/// context travelled, and what it says.
struct CoachContextPreview: View {
    let context: CoachDiscussContext?

    var body: some View {
        if let context {
            VStack(alignment: .leading, spacing: SharpitSpacing.sm) {
                SharpitEyebrow(String(localized: "Contexte"))
                CoachContextTag(context: context)
                Text("La conversation s'ouvrira avec ce sujet joint.")
                    .font(SharpitTypography.meta)
                    .foregroundStyle(SharpitColor.slate)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(SharpitSpacing.cardPadding)
            .sharpitSurface(.panel)
        }
    }
}

#Preview {
    VStack(spacing: SharpitSpacing.lg) {
        CoachContextTag(
            context: CoachDiscuss.describe(
                .activity(activityId: "a-1"),
                name: "Zwift — Greater London Flat"
            ),
            onDismiss: {}
        )
        CoachContextPreview(context: CoachDiscuss.describe(.planning(horizonDays: 7)))
    }
    .padding()
    .background(SharpitCanvasBackground())
}
