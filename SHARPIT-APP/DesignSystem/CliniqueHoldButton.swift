import SwiftUI

/// An action confirmed by holding: the capsule fills with ink from its leading edge while the
/// finger stays on it, and the action goes once it is full. A finger lifted early lets the ink
/// run back out the way it came — nothing happened, and the button says so by emptying.
///
/// For the one kind of answer a stray tap must not give (deleting a session the coach proposed
/// to remove). It replaces a second « Confirmer » tap: the hold is the confirmation, and its
/// progress is under the finger rather than in a new label to read.
struct CliniqueHoldButton: View {
    let title: String
    /// How long the finger stays for the action to go.
    var duration: TimeInterval = 1.2
    let action: () -> Void

    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// 0 empty, 1 full.
    @State private var progress: CGFloat = 0
    @State private var isHeld = false
    @State private var hasFired = false

    var body: some View {
        label(SharpitColor.foreground)
            .background(SharpitColor.card)
            .overlay {
                // The same words in the fill's ink, shown only where the fill has reached: the
                // title turns over letter by letter as the ink passes it.
                label(SharpitColor.primaryForeground)
                    .background(SharpitColor.primary)
                    .mask(alignment: .leading) {
                        Rectangle().scaleEffect(x: progress, anchor: .leading)
                    }
            }
            .clipShape(Capsule())
            .overlay { Capsule().strokeBorder(SharpitColor.outline, lineWidth: 1) }
            .contentShape(Capsule())
            .scaleEffect(isHeld ? 0.97 : 1)
            .opacity(isEnabled ? 1 : 0.4)
            .animation(SharpitMotion.selection, value: isHeld)
            .onLongPressGesture(minimumDuration: duration, maximumDistance: 40) {
                guard !hasFired else { return }
                hasFired = true
                action()
            } onPressingChanged: { pressing in
                guard !hasFired else { return }
                isHeld = pressing
                if pressing {
                    withAnimation(.linear(duration: duration)) { progress = 1 }
                } else {
                    // Out faster than in: giving up should not have to be waited for.
                    withAnimation(reduceMotion ? .easeOut(duration: 0.01) : .easeOut(duration: 0.28)) { progress = 0 }
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(title)
            .accessibilityAddTraits(.isButton)
            // VoiceOver's double tap is already a deliberate act; a hold cannot be asked of it.
            .accessibilityAction {
                guard !hasFired else { return }
                hasFired = true
                action()
            }
    }

    private func label(_ color: Color) -> some View {
        Text(title)
            .font(SharpitTypography.system(size: 15, weight: .semibold, relativeTo: .body))
            .foregroundStyle(color)
            .lineLimit(1)
            .minimumScaleFactor(0.85)
            .padding(.horizontal, 22)
            .frame(maxWidth: .infinity, minHeight: SharpitSpacing.minimumTouchTarget)
    }
}
