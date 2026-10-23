import SwiftUI

/// The tag a contextual conversation carries.
///
/// It names what the coach was handed and lets the athlete drop it — that is the whole
/// contract (ADR-030). It is not a prefilled prompt: the question stays the athlete's,
/// the context only says what they were looking at when they asked.
struct CoachContextTag: View {
    let context: CoachDiscussContext
    var onDismiss: (() -> Void)?

    var body: some View {
        HStack(spacing: SharpitSpacing.xs) {
            Image(systemName: "paperclip")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(SharpitColor.inkAccent)
                .frame(width: 24, height: 24)
                .background(SharpitColor.inkSurface, in: Circle())
                .accessibilityHidden(true)

            Text(context.label)
                .font(SharpitTypography.bodyEmphasis)
                .foregroundStyle(SharpitColor.foreground)
                .lineLimit(1)

            if let onDismiss {
                Button(action: onDismiss) {
                    Image(systemName: "xmark")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(SharpitColor.mutedForeground)
                        .frame(width: 24, height: 24)
                        .background(SharpitColor.track, in: Circle())
                        .frame(width: SharpitSpacing.minimumTouchTarget, height: SharpitSpacing.minimumTouchTarget)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.sharpitPressable)
                .padding(.trailing, -SharpitSpacing.xs)
                .accessibilityLabel("Retirer le contexte")
            }
        }
        .padding(.leading, SharpitSpacing.xs)
        .padding(.trailing, onDismiss == nil ? SharpitSpacing.sm : SharpitSpacing.xxs)
        .padding(.vertical, SharpitSpacing.xxs)
        .background(Capsule().fill(SharpitColor.chipSurface).sharpitShadow(.control))
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
                    .foregroundStyle(SharpitColor.mutedForeground)
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
