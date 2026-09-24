import SwiftUI

/// A choice among a few options, answered in place — appearance, reading density.
///
/// The system segmented picker draws a grey iOS 6 track that reads as a form control dropped
/// on an editorial page. This one keeps the same behaviour — one selection, VoiceOver sees a
/// set of buttons with one selected — on the app's surfaces: a quiet track and a raised pill
/// that slides to the choice under the finger.
struct SharpitSegmentedControl<Value: Hashable>: View {
    struct Option: Identifiable {
        let value: Value
        let label: String
        var symbol: String?

        var id: Value { value }
    }

    @Binding var selection: Value
    let options: [Option]
    var isDisabled = false

    @Namespace private var pill

    var body: some View {
        HStack(spacing: 2) {
            ForEach(options) { option in
                let isSelected = option.value == selection
                Button {
                    guard !isSelected else { return }
                    SharpitHaptics.play(.light)
                    SharpitMotion.run(SharpitMotion.selection) { selection = option.value }
                } label: {
                    HStack(spacing: SharpitSpacing.xxs + 2) {
                        if let symbol = option.symbol {
                            Image(systemName: symbol)
                                .symbolVariant(isSelected ? .fill : .none)
                                .contentTransition(.symbolEffect(.replace))
                        }
                        Text(option.label)
                            .lineLimit(1)
                            .minimumScaleFactor(0.85)
                    }
                    .font(SharpitTypography.meta.weight(isSelected ? .semibold : .medium))
                    .foregroundStyle(isSelected ? SharpitColor.foreground : SharpitColor.mutedForeground)
                    .frame(maxWidth: .infinity, minHeight: 36)
                    .background {
                        if isSelected {
                            Capsule()
                                .fill(SharpitColor.card)
                                .sharpitShadow(.control)
                                .matchedGeometryEffect(id: "pill", in: pill)
                        }
                    }
                    .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
            }
        }
        .padding(3)
        .background(SharpitColor.analysisGrid.opacity(0.45), in: Capsule())
        .disabled(isDisabled)
        .opacity(isDisabled ? 0.5 : 1)
    }
}
