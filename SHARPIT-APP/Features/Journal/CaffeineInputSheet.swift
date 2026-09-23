import SwiftUI

/// Dedicated bottom sheet for logging caffeine intake with quick beverage presets
/// and granular fine-tuning.
struct CaffeineInputSheet: View {
    @Bindable var store: JournalStore
    @Environment(\.dismiss) private var dismiss

    private struct Preset: Identifiable {
        let id: String
        let label: String
        let delta: Int
        let icon: String
    }

    private let presets: [Preset] = [
        Preset(id: "tea", label: "Thé", delta: 40, icon: "cup.and.saucer"),
        Preset(id: "espresso", label: "Expresso", delta: 60, icon: "cup.and.saucer.fill"),
        Preset(id: "energy", label: "Énergie", delta: 80, icon: "bolt.fill"),
        Preset(id: "filter", label: "Filtre", delta: 100, icon: "mug"),
        Preset(id: "double", label: "Double expresso", delta: 120, icon: "mug.fill")
    ]

    private var currentMg: Int {
        store.entry.caffeineMg ?? 0
    }

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(spacing: SharpitSpacing.md) {
                    // Big readout
                    VStack(spacing: SharpitSpacing.xxs) {
                        HStack(alignment: .firstTextBaseline, spacing: 6) {
                            Text("\(currentMg)")
                                .font(.system(size: 40, weight: .bold, design: .rounded))
                                .foregroundStyle(SharpitColor.primary)
                                .contentTransition(.numericText())
                                .animation(SharpitMotion.selection, value: currentMg)
                            Text("mg")
                                .font(SharpitTypography.verdict)
                                .foregroundStyle(SharpitColor.mutedForeground)
                        }

                        Text("Caféine consommée sur la journée")
                            .font(SharpitTypography.meta)
                            .foregroundStyle(SharpitColor.mutedForeground)
                    }
                    .padding(.top, SharpitSpacing.xs)

                    // Fine-tuning stepper
                    HStack(spacing: SharpitSpacing.md) {
                        Button {
                            store.adjustCaffeine(by: -20)
                        } label: {
                            Image(systemName: "minus")
                                .frame(width: 44, height: 44)
                                .background(SharpitColor.primary.opacity(0.12), in: Circle())
                                .contentShape(.circle)
                        }
                        .buttonStyle(.sharpitPressable)
                        .disabled(currentMg <= 0)
                        .accessibilityLabel("Diminuer de 20 milligrammes")

                        Text("± 20 mg")
                            .font(SharpitTypography.meta)
                            .foregroundStyle(SharpitColor.mutedForeground)
                            .frame(minWidth: 70)

                        Button {
                            store.adjustCaffeine(by: 20)
                        } label: {
                            Image(systemName: "plus")
                                .frame(width: 44, height: 44)
                                .background(SharpitColor.primary.opacity(0.12), in: Circle())
                                .contentShape(.circle)
                        }
                        .buttonStyle(.sharpitPressable)
                        .accessibilityLabel("Augmenter de 20 milligrammes")
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
                                    store.adjustCaffeine(by: preset.delta)
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
                                            Text("+\(preset.delta) mg")
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

                    if currentMg > 0 {
                        Button("Réinitialiser à 0") {
                            store.setCaffeine(0)
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
            .navigationTitle("Caféine")
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
}
