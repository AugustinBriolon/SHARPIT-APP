import SwiftUI
import UIKit

/// The nights the athlete is aiming for, set from Sommeil where they are read: a duration and,
/// optionally, a bedtime. Saved on « OK » through `AthleteProfilePatch`, which sends only what
/// changed.
struct SleepTargetsSheet: View {
    @State private var store: AthleteProfileStore
    @State private var minutes = 480
    @State private var hasBedtime = false
    @State private var bedtime = SleepTargetsSheet.date(fromMinutes: 22 * 60 + 30)
    @State private var hasLoaded = false
    @Environment(\.dismiss) private var dismiss

    init(profileClient: any AthleteProfileServing, tokenProvider: @escaping () async throws -> String) {
        _store = State(initialValue: AthleteProfileStore(client: profileClient, tokenProvider: tokenProvider))
    }

    private static let presets = [420, 450, 480, 510, 540]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: SharpitSpacing.md) {
                    durationCard
                    scheduleCard
                }
                .padding(.horizontal, SharpitSpacing.pageInset)
                .padding(.vertical, SharpitSpacing.sm)
            }
            .background(SharpitCanvasBackground())
            .disabled(!hasLoaded)
            .redacted(reason: hasLoaded ? [] : .placeholder)
            .navigationTitle("Objectifs de sommeil")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Annuler") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("OK") { save() }
                        .disabled(!hasLoaded)
                }
            }
            .task {
                await store.load()
                minutes = store.profile.sleepTargetMinutes ?? 480
                if let bed = store.profile.sleepBedtimeTargetMin {
                    hasBedtime = true
                    bedtime = Self.date(fromMinutes: bed)
                }
                hasLoaded = true
            }
        }
        .presentationDetents([.fraction(0.75), .large])
        .presentationDragIndicator(.visible)
        .sharpitSheet()
    }

    /// The duration as one large figure between − and +, the usual targets one tap below.
    private var durationCard: some View {
        VStack(spacing: SharpitSpacing.md) {
            SharpitCardHeader(
                title: String(localized: "Durée visée"),
                symbol: "moon.zzz.fill",
                showsChevron: false
            )
            HStack {
                stepButton("minus", label: String(localized: "Moins 15 minutes"), delta: -15)
                Spacer(minLength: 0)
                Text(SleepTargetFormat.duration(minutes))
                    .font(SharpitTypography.heroScore)
                    .tracking(SharpitTypography.heroScoreTracking)
                    .foregroundStyle(SharpitColor.foreground)
                    .monospacedDigit()
                    .contentTransition(.numericText(value: Double(minutes)))
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    .accessibilityLabel("Durée visée")
                    .accessibilityValue(SleepTargetFormat.duration(minutes))
                    .accessibilityAdjustableAction { direction in
                        step(direction == .increment ? 15 : -15)
                    }
                Spacer(minLength: 0)
                stepButton("plus", label: String(localized: "Plus 15 minutes"), delta: 15)
            }
            SharpitSegmentedControl(
                selection: $minutes.animation(SharpitMotion.selection),
                options: Self.presets.map {
                    SharpitSegmentedControl<Int>.Option(value: $0, label: SleepTargetFormat.short($0))
                }
            )
        }
        .padding(SharpitSpacing.cardPadding)
        .sharpitSurface(.panel)
    }

    /// A fixed bedtime, and the wake time it gives with the duration above — the night as a span.
    private var scheduleCard: some View {
        VStack(alignment: .leading, spacing: SharpitSpacing.md) {
            Toggle(isOn: $hasBedtime.animation(SharpitMotion.selection)) {
                SharpitCardHeader(
                    title: String(localized: "Heure fixe"),
                    symbol: "bed.double.fill",
                    showsChevron: false
                )
            }
            .tint(SharpitColor.highlight)

            if hasBedtime {
                HStack(spacing: SharpitSpacing.sm) {
                    VStack(alignment: .leading, spacing: SharpitSpacing.xxs) {
                        Label("Coucher", systemImage: "moon.fill")
                            .font(SharpitTypography.meta)
                            .foregroundStyle(SharpitColor.mutedForeground)
                        DatePicker("Coucher", selection: $bedtime, displayedComponents: .hourAndMinute)
                            .labelsHidden()
                            .environment(\.locale, SharpitLocale.current)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(SharpitSpacing.sm)
                    .sharpitConcentricBackground(SharpitColor.chipSurface, minimum: SharpitRadius.row)

                    VStack(alignment: .leading, spacing: SharpitSpacing.xxs) {
                        Label("Réveil", systemImage: "alarm.fill")
                            .font(SharpitTypography.meta)
                            .foregroundStyle(SharpitColor.mutedForeground)
                        Text(SleepTargetFormat.clock(SleepTargetFormat.wake(bedtime: Self.minutes(from: bedtime), duration: minutes)))
                            .font(SharpitTypography.data)
                            .foregroundStyle(SharpitColor.foreground)
                            .monospacedDigit()
                            .contentTransition(.numericText())
                            .frame(minHeight: 34, alignment: .leading)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(SharpitSpacing.sm)
                    .sharpitConcentricBackground(SharpitColor.chipSurface, minimum: SharpitRadius.row)
                    .accessibilityElement(children: .combine)
                }
                .transition(.opacity.combined(with: .move(edge: .top)))

                Text("Réveil calculé avec ta durée visée.")
                    .font(SharpitTypography.meta)
                    .foregroundStyle(SharpitColor.mutedForeground)
            }
        }
        .padding(SharpitSpacing.cardPadding)
        .sharpitSurface(.panel)
    }

    private func stepButton(_ symbol: String, label: String, delta: Int) -> some View {
        Button { step(delta) } label: {
            Image(systemName: symbol)
                .font(.system(size: 20, weight: .bold))
                .foregroundStyle(SharpitColor.foreground)
                .frame(width: 52, height: 52)
                .background(SharpitColor.chipSurface, in: Circle())
        }
        .buttonStyle(.sharpitPressable)
        .disabled(!Self.range.contains(minutes + delta))
        .accessibilityLabel(label)
    }

    private func step(_ delta: Int) {
        let next = minutes + delta
        guard Self.range.contains(next) else { return }
        withAnimation(SharpitMotion.selection) { minutes = next }
    }

    private static let range = 240...720

    private func save() {
        var patch = AthleteProfilePatch()
        patch.setIfChanged(.sleepTargetMinutes, int: minutes, was: store.profile.sleepTargetMinutes)
        patch.setIfChanged(
            .sleepBedtimeTargetMin,
            int: hasBedtime ? Self.minutes(from: bedtime) : nil,
            was: store.profile.sleepBedtimeTargetMin
        )
        store.save(patch)
        dismiss()
    }

    static func date(fromMinutes minutes: Int) -> Date {
        Calendar.current.date(
            bySettingHour: minutes / 60, minute: minutes % 60, second: 0, of: Date()
        ) ?? Date()
    }

    static func minutes(from date: Date) -> Int {
        let parts = Calendar.current.dateComponents([.hour, .minute], from: date)
        return (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
    }
}

nonisolated enum SleepTargetFormat {
    /// 450 → « 7 h 30 », 480 → « 8 h ».
    static func duration(_ minutes: Int) -> String {
        let hours = minutes / 60
        let rest = minutes % 60
        return rest == 0 ? "\(hours) h" : "\(hours) h \(String(format: "%02d", rest))"
    }

    /// The wake time a bedtime and a duration give, in minutes after midnight.
    static func wake(bedtime: Int, duration: Int) -> Int {
        (bedtime + duration) % (24 * 60)
    }

    /// 420 → « 07:00 ».
    static func clock(_ minutes: Int) -> String {
        String(format: "%02d:%02d", minutes / 60, minutes % 60)
    }

    /// 450 → « 7h30 », 480 → « 8 h » — for the presets.
    static func short(_ minutes: Int) -> String {
        let rest = minutes % 60
        return rest == 0 ? "\(minutes / 60) h" : "\(minutes / 60)h\(String(format: "%02d", rest))"
    }
}

/// The weight the athlete is aiming for, set from Corps. Optional, and never a verdict: it draws
/// a line across the weight trend and informs the nutrition reading, nothing more.
struct WeightTargetSheet: View {
    @State private var store: AthleteProfileStore
    @State private var text = ""
    @State private var hasLoaded = false
    @FocusState private var isFocused: Bool
    @Environment(\.dismiss) private var dismiss

    init(profileClient: any AthleteProfileServing, tokenProvider: @escaping () async throws -> String) {
        _store = State(initialValue: AthleteProfileStore(client: profileClient, tokenProvider: tokenProvider))
    }

    private var parsed: Double? { ProfileFieldFormat.parseDecimal(text) }

    private var isValid: Bool {
        text.trimmingCharacters(in: .whitespaces).isEmpty || (parsed.map { (30...250).contains($0) } ?? false)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: SharpitSpacing.md) {
                    plate
                    if !isValid {
                        Label("Entre 30 et 250 kg.", systemImage: "exclamationmark.triangle.fill")
                            .font(SharpitTypography.meta)
                            .foregroundStyle(SharpitColor.signalRisk)
                    }
                    if store.profile.targetWeightKg != nil {
                        Button("Retirer l'objectif", role: .destructive) {
                            text = ""
                            save()
                        }
                        .frame(maxWidth: .infinity, minHeight: SharpitSpacing.minimumTouchTarget)
                    }
                }
                .padding(SharpitSpacing.pageInset)
            }
            .scrollDismissesKeyboard(.interactively)
            .background(SharpitCanvasBackground())
            .disabled(!hasLoaded)
            .navigationTitle("Objectif de poids")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Annuler") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("OK") { save() }
                        .disabled(!hasLoaded || !isValid)
                }
            }
            .task {
                await store.load()
                text = ProfileFieldFormat.decimal(store.profile.targetWeightKg)
                hasLoaded = true
                isFocused = true
            }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .sharpitSheet()
    }

    /// The target, big on the ink plate: typed, or stepped by half a kilo.
    private var plate: some View {
        VStack(alignment: .leading, spacing: SharpitSpacing.sm) {
            Text("Poids cible")
                .font(SharpitTypography.cardTitle)
                .foregroundStyle(SharpitColor.inkSurfaceForeground)
            HStack(alignment: .center, spacing: SharpitSpacing.sm) {
                SharpitStepButton(symbol: "minus", label: String(localized: "Moins 0,5 kg")) { step(-0.5) }
                VStack(spacing: 2) {
                    TextField("72,0", text: $text)
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.center)
                        .font(SharpitTypography.heroScore)
                        .tracking(SharpitTypography.heroScoreTracking)
                        .foregroundStyle(SharpitColor.inkSurfaceForeground)
                        .minimumScaleFactor(0.5)
                        .lineLimit(1)
                        .focused($isFocused)
                        .accessibilityLabel("Poids cible en kilos")
                    Text("kg")
                        .font(SharpitTypography.bodyEmphasis)
                        .foregroundStyle(SharpitColor.inkAccent)
                }
                .frame(maxWidth: .infinity)
                SharpitStepButton(symbol: "plus", label: String(localized: "Plus 0,5 kg")) { step(0.5) }
            }
            Text("Optionnel. Tracé sur ta courbe de poids et pris en compte dans la lecture nutritionnelle — jamais une alerte.")
                .font(SharpitTypography.meta)
                .foregroundStyle(SharpitColor.inkSurfaceForeground.opacity(0.7))
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(SharpitSpacing.cardPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .sharpitSurface(.ink)
    }

    private func step(_ delta: Double) {
        let next = min(max((parsed ?? store.profile.targetWeightKg ?? 70) + delta, 30), 250)
        text = ProfileFieldFormat.decimal(next)
    }

    private func save() {
        var patch = AthleteProfilePatch()
        patch.setIfChanged(.targetWeightKg, double: parsed, was: store.profile.targetWeightKg)
        store.save(patch)
        dismiss()
    }
}
