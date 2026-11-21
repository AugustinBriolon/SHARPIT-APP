import SwiftUI

/// One light sheet for the journal's amounts — caffeine, water, time at the wheel: the figure
/// read big between − and +, the usual portions to add in one tap, and a way back to zero.
/// Each amount only says what it is (`Amount`); the layout is the same, so they read alike.
struct JournalAmountSheet<Detail: View>: View {
    typealias Portion = JournalAmountPortion
    typealias Amount = JournalAmount

    let amount: Amount
    let value: Int
    let onAdjust: (Int) -> Void
    let onReset: () -> Void
    /// A line under the quick adds that only this amount has (the last coffee's time).
    @ViewBuilder var detail: () -> Detail

    @Environment(\.dismiss) private var dismiss

    private var hasDetail: Bool { ObjectIdentifier(Detail.self) != ObjectIdentifier(EmptyView.self) }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            CliniqueSheetTitle(amount.title)
            Text(amount.caption)
                .font(SharpitTypography.system(size: 15, weight: .regular, relativeTo: .subheadline))
                .foregroundStyle(SharpitColor.slate)
                .padding(.top, 4)

            HStack(spacing: 18) {
                stepButton("minus", String(localized: "Retirer \(amount.format(amount.stepDelta))")) { onAdjust(-amount.stepDelta) }
                    .disabled(value <= 0)
                Text(amount.format(value))
                    .font(SharpitTypography.system(size: 40, weight: .semibold, relativeTo: .largeTitle, digits: true))
                    .tracking(-1.2)
                    .foregroundStyle(SharpitColor.foreground)
                    .contentTransition(.numericText(value: Double(value)))
                    .animation(SharpitMotion.selection, value: value)
                    .minimumScaleFactor(0.7)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity)
                stepButton("plus", String(localized: "Ajouter \(amount.format(amount.stepDelta))")) { onAdjust(amount.stepDelta) }
            }
            .padding(.top, 22)

            Text("Ajouts rapides")
                .font(SharpitTypography.sectionTitle)
                .tracking(SharpitTypography.sectionTitleTracking)
                .foregroundStyle(SharpitColor.foreground)
                .accessibilityAddTraits(.isHeader)
                .padding(.top, 26)
                .padding(.bottom, 10)
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
                ForEach(amount.portions) { portion in
                    Button { onAdjust(portion.delta) } label: {
                        HStack(spacing: 10) {
                            Image(systemName: portion.symbol)
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundStyle(amount.hue)
                                .frame(width: 32, height: 32)
                                .background(amount.hue.opacity(0.14), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                                .accessibilityHidden(true)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(portion.label)
                                    .font(SharpitTypography.system(size: 14, weight: .semibold, relativeTo: .footnote))
                                    .foregroundStyle(SharpitColor.foreground)
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.8)
                                Text(amount.portionLabel(portion))
                                    .font(SharpitTypography.system(size: 12, weight: .regular, relativeTo: .caption, digits: true))
                                    .foregroundStyle(SharpitColor.slate)
                            }
                            Spacer(minLength: 0)
                        }
                        .padding(.horizontal, 10)
                        .frame(minHeight: 52)
                        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(SharpitColor.outline, lineWidth: 1))
                        .contentShape(.rect)
                    }
                    .buttonStyle(.sharpitPressable)
                }
            }

            detail()
                .padding(.top, 18)

            Spacer(minLength: 16)

            VStack(spacing: 6) {
                Button { dismiss() } label: { Text("Terminé").frame(maxWidth: .infinity) }
                    .buttonStyle(CliniqueButtonStyle(kind: .primary, isLarge: true))
                if value > 0 {
                    Button(amount.resetTitle, action: onReset)
                        .buttonStyle(CliniqueButtonStyle(kind: .plain))
                }
            }
        }
        .padding(.horizontal, 24)
        .padding(.top, 30)
        .padding(.bottom, SharpitSpacing.xs)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(SharpitColor.card)
        .cliniqueSheetCross { dismiss() }
        .presentationDetents([.height((amount.portions.count > 4 ? 500 : 440) + (hasDetail ? 56 : 0))])
        .presentationDragIndicator(.visible)
        .sharpitSheet()
    }

    private func stepButton(_ symbol: String, _ label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 18, weight: .regular))
                .foregroundStyle(SharpitColor.foreground)
                .frame(width: 48, height: 48)
                .background(SharpitColor.tile, in: Circle())
                .contentShape(.circle)
        }
        .buttonStyle(.sharpitPressable)
        .accessibilityLabel(label)
    }
}

/// How the journal words an amount.
nonisolated enum JournalAmountFormat {
    static func milligrams(_ mg: Int) -> String { "\(mg) mg" }

    /// « 25 cl » under a litre, « 1,25 L » above.
    static func volume(_ millilitres: Int, locale: Locale = .current) -> String {
        guard millilitres >= 1_000 else { return "\(millilitres / 10) cl" }
        return (Double(millilitres) / 1_000).formatted(.number.precision(.fractionLength(0...2)).locale(locale)) + " L"
    }
}

extension JournalAmountSheet where Detail == EmptyView {
    init(amount: Amount, value: Int, onAdjust: @escaping (Int) -> Void, onReset: @escaping () -> Void) {
        self.init(amount: amount, value: value, onAdjust: onAdjust, onReset: onReset) { EmptyView() }
    }
}

/// A usual portion of a journal amount: what it is, what it adds.
struct JournalAmountPortion: Identifiable {
    let id: String
    let label: String
    let symbol: String
    let delta: Int
}

/// What a journal amount sheet adds up: its words, its steps, its usual portions.
struct JournalAmount {
    let title: String
    let caption: String
    /// How the figure reads, « 160 mg ».
    let format: (Int) -> String
    let stepDelta: Int
    let portions: [JournalAmountPortion]
    let portionLabel: (JournalAmountPortion) -> String
    let resetTitle: String
    let hue: Color
}
