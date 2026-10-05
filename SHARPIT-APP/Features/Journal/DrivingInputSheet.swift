import SwiftUI

/// The day's time behind the wheel: set by quarter hours, or from a usual length. Long sitting,
/// often tense — the journal keeps it beside the rest of the day.
struct DrivingInputSheet: View {
    @Bindable var store: JournalStore
    @Environment(\.dismiss) private var dismiss

    private static let presets = [15, 30, 45, 60, 90, 120]

    private var minutes: Int { store.entry.drivingMinutes ?? 0 }

    var body: some View {
        NavigationStack {
            VStack(spacing: SharpitSpacing.md) {
                VStack(spacing: SharpitSpacing.xxs) {
                    Text(JournalDrivingFormat.minutes(store.entry.drivingMinutes))
                        .font(SharpitTypography.heroScore)
                        .tracking(SharpitTypography.heroScoreTracking)
                        .foregroundStyle(SharpitColor.foreground)
                        .contentTransition(.numericText(value: Double(minutes)))
                        .animation(SharpitMotion.selection, value: minutes)
                    Text("Temps passé à conduire aujourd'hui")
                        .font(SharpitTypography.meta)
                        .foregroundStyle(SharpitColor.mutedForeground)
                }
                .padding(.top, SharpitSpacing.xs)

                HStack(spacing: SharpitSpacing.md) {
                    stepButton("minus", delta: -15, label: "Retirer 15 minutes")
                        .disabled(minutes <= 0)
                    Text("± 15 min")
                        .font(SharpitTypography.meta)
                        .foregroundStyle(SharpitColor.mutedForeground)
                        .frame(minWidth: 70)
                    stepButton("plus", delta: 15, label: "Ajouter 15 minutes")
                }

                VStack(alignment: .leading, spacing: SharpitSpacing.xs) {
                    SharpitFieldLabel("Durée")
                    LazyVGrid(
                        columns: Array(repeating: GridItem(.flexible(), spacing: SharpitSpacing.xs), count: 3),
                        spacing: SharpitSpacing.xs
                    ) {
                        ForEach(Self.presets, id: \.self) { preset in
                            OnboardingChoiceChip(
                                title: JournalDrivingFormat.minutes(preset),
                                isSelected: store.entry.drivingMinutes == preset
                            ) {
                                store.setDriving(preset)
                            }
                        }
                    }
                }

                if minutes > 0 {
                    Button("Pas de conduite") { store.setDriving(0) }
                        .font(SharpitTypography.meta)
                        .foregroundStyle(SharpitColor.mutedForeground)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, SharpitSpacing.pageInset)
            .navigationTitle("Conduite")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("OK") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium])
        .presentationDragIndicator(.visible)
        .sharpitSheet()
    }

    private func stepButton(_ symbol: String, delta: Int, label: String) -> some View {
        Button {
            store.adjustDriving(by: delta)
        } label: {
            Image(systemName: symbol)
                .font(SharpitTypography.bodyEmphasis)
                .foregroundStyle(SharpitColor.primary)
                .frame(width: 44, height: 44)
                .background(SharpitColor.primary.opacity(0.12), in: Circle())
                .contentShape(.circle)
        }
        .buttonStyle(.sharpitPressable)
        .accessibilityLabel(label)
    }
}
