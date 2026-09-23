import SwiftUI

/// Dedicated bottom sheet for logging water and liquid intake with standard beverage presets
/// and precise adjustments.
struct HydrationInputSheet: View {
    @Bindable var store: JournalStore
    @Environment(\.dismiss) private var dismiss

    private struct Preset: Identifiable {
        let id: String
        let label: String
        let delta: Int
        let icon: String
    }

    private let presets: [Preset] = [
        Preset(id: "glass", label: "Verre d'eau", delta: 250, icon: "drop"),
        Preset(id: "mug", label: "Grande tasse", delta: 350, icon: "mug"),
        Preset(id: "small_bottle", label: "Petite bouteille", delta: 500, icon: "waterbottle"),
        Preset(id: "flask", label: "Gourde sport", delta: 750, icon: "waterbottle.fill"),
        Preset(id: "liter", label: "Bouteille 1 L", delta: 1000, icon: "drop.fill")
    ]

    private var currentMl: Int {
        store.entry.hydrationMl ?? 0
    }

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(spacing: SharpitSpacing.md) {
                    // Big readout
                    VStack(spacing: SharpitSpacing.xxs) {
                        HStack(alignment: .firstTextBaseline, spacing: 6) {
                            Text(formatMl(currentMl))
                                .font(.system(size: 40, weight: .bold, design: .rounded))
                                .foregroundStyle(SharpitColor.primary)
                                .contentTransition(.numericText())
                                .animation(SharpitMotion.selection, value: currentMl)
                            Text("ml")
                                .font(SharpitTypography.verdict)
                                .foregroundStyle(SharpitColor.mutedForeground)
                        }

                        Text("Eau et liquides consommés sur la journée")
                            .font(SharpitTypography.meta)
                            .foregroundStyle(SharpitColor.mutedForeground)
                    }
                    .padding(.top, SharpitSpacing.xs)

                    // Fine-tuning stepper
                    HStack(spacing: SharpitSpacing.md) {
                        Button {
                            store.adjustHydration(by: -100)
                        } label: {
                            Image(systemName: "minus")
                                .frame(width: 44, height: 44)
                                .background(SharpitColor.primary.opacity(0.12), in: Circle())
                                .contentShape(.circle)
                        }
                        .buttonStyle(.sharpitPressable)
                        .disabled(currentMl <= 0)
                        .accessibilityLabel("Diminuer de 100 millilitres")

                        Text("± 100 ml")
                            .font(SharpitTypography.meta)
                            .foregroundStyle(SharpitColor.mutedForeground)
                            .frame(minWidth: 70)

                        Button {
                            store.adjustHydration(by: 100)
                        } label: {
                            Image(systemName: "plus")
                                .frame(width: 44, height: 44)
                                .background(SharpitColor.primary.opacity(0.12), in: Circle())
                                .contentShape(.circle)
                        }
                        .buttonStyle(.sharpitPressable)
                        .accessibilityLabel("Augmenter de 100 millilitres")
                    }
                    .font(SharpitTypography.bodyEmphasis)
                    .foregroundStyle(SharpitColor.primary)

                    // Quick add presets grid
                    VStack(alignment: .leading, spacing: SharpitSpacing.xs) {
                        SharpitEyebrow("Ajouts rapides")

                        LazyVGrid(
                            columns: [
                                GridItem(.flexible(), spacing: SharpitSpacing.xs),
                                GridItem(.flexible(), spacing: SharpitSpacing.xs)
                            ],
                            spacing: SharpitSpacing.xs
                        ) {
                            ForEach(presets) { preset in
                                Button {
                                    store.adjustHydration(by: preset.delta)
                                } label: {
                                    HStack(spacing: SharpitSpacing.xs) {
                                        Image(systemName: preset.icon)
                                            .font(SharpitTypography.bodyEmphasis)
                                            .foregroundStyle(SharpitColor.primary)
                                            .frame(width: 20)
                                        VStack(alignment: .leading, spacing: 1) {
                                            Text(preset.label)
                                                .font(SharpitTypography.meta)
                                                .foregroundStyle(SharpitColor.foreground)
                                            Text("+\(preset.delta) ml")
                                                .font(SharpitTypography.meta)
                                                .foregroundStyle(SharpitColor.mutedForeground)
                                        }
                                        Spacer(minLength: 0)
                                    }
                                    .padding(SharpitSpacing.cardPadding)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .sharpitSurface(.panel)
                                }
                                .buttonStyle(.sharpitPressable)
                            }
                        }
                    }

                    if currentMl > 0 {
                        Button("Réinitialiser à 0") {
                            store.setHydration(0)
                        }
                        .font(SharpitTypography.meta)
                        .foregroundStyle(SharpitColor.signalRisk)
                        .padding(.top, SharpitSpacing.xs)
                    }
                }
                .padding(.horizontal, SharpitSpacing.pageInset)
                .padding(.bottom, SharpitSpacing.lg)
            }
            .background(SharpitCanvasBackground())
            .navigationTitle("Hydratation")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("OK") { dismiss() }
                        .font(SharpitTypography.bodyEmphasis)
                        .foregroundStyle(SharpitColor.primary)
                }
            }
        }
        .presentationDetents([.fraction(0.68), .large])
        .sharpitSheet()
        .presentationDragIndicator(.visible)
    }

    private func formatMl(_ value: Int) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.groupingSeparator = " "
        return formatter.string(from: NSNumber(value: value)) ?? "\(value)"
    }
}
