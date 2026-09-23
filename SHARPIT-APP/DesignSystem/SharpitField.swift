import SwiftUI

/// One value the athlete types, as a row of a grouped list: the name on the left, the entry
/// on the right, a hint or the reason it was refused underneath.
///
/// A row and not a panel (`docs/adr/0008`): inside a grouped list the row already is the
/// surface, and a second one set into it is elevation inside elevation. The whole row is the
/// target — a label is not a dead zone — and it is at least 44pt tall at any text size.
struct SharpitField: View {
    let label: String
    @Binding var text: String
    var placeholder: String = ""
    var unit: String?
    /// The entry it expects — a pace is typed with a colon, a weight with a comma.
    var keyboard: UIKeyboardType = .numberPad
    /// A quiet line under the field. Replaced by `error` when the entry is refused.
    var hint: String?
    var error: String?

    @FocusState private var isFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: SharpitSpacing.xxs) {
            HStack(alignment: .firstTextBaseline, spacing: SharpitSpacing.xs) {
                Text(label)
                    .accessibilityHidden(true)
                Spacer(minLength: SharpitSpacing.xs)
                TextField(placeholder, text: $text)
                    .font(SharpitTypography.instrument)
                    .multilineTextAlignment(.trailing)
                    .keyboardType(keyboard)
                    .submitLabel(.done)
                    .focused($isFocused)
                    .accessibilityLabel(label)
                    .accessibilityHint(error ?? hint ?? "")
                if let unit {
                    Text(unit)
                        .font(SharpitTypography.meta)
                        .foregroundStyle(SharpitColor.mutedForeground)
                        .accessibilityHidden(true)
                }
            }
            if let error {
                SharpitListFooter(error, tone: SharpitColor.signalRisk)
            } else if let hint {
                SharpitListFooter(hint)
            }
        }
        .padding(.vertical, SharpitSpacing.xs)
        .frame(minHeight: SharpitSpacing.minimumTouchTarget, alignment: .center)
        .contentShape(.rect)
        .onTapGesture { isFocused = true }
        // The row's own vertical inset would stack on the 44pt floor and leave the row taller
        // than its neighbours; the floor is the row, so the target is the whole of it.
        .listRowInsets(EdgeInsets(
            top: 0,
            leading: SharpitSpacing.md,
            bottom: 0,
            trailing: SharpitSpacing.md
        ))
    }
}
