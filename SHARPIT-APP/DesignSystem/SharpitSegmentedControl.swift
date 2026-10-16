import SwiftUI

/// A choice among a few options, answered in place — appearance, reading density.
///
/// Ink & Lime (ADR-085): a neutral chip track, the choice an ink capsule with white text that
/// slides under the finger. VoiceOver sees a set of buttons with one selected.
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
                    .font(SharpitTypography.system(size: 15, weight: .semibold, relativeTo: .subheadline))
                    .foregroundStyle(isSelected ? SharpitColor.primaryForeground : SharpitColor.mutedForeground)
                    .frame(maxWidth: .infinity, minHeight: 38)
                    .background {
                        if isSelected {
                            Color.clear
                                .sharpitConcentricBackground(SharpitColor.primary, minimum: 12)
                                .matchedGeometryEffect(id: "pill", in: pill)
                        }
                    }
                    .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
            }
        }
        .padding(4)
        .sharpitContainerCorner(SharpitRadius.control)
        .sharpitConcentricBackground(SharpitColor.chipSurface, minimum: SharpitRadius.control)
        .disabled(isDisabled)
        .opacity(isDisabled ? 0.5 : 1)
    }
}
