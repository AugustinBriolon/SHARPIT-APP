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
            .unredacted()
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
                .unredacted()
            }
            .tint(SharpitColor.primary)

            if hasBedtime {
                HStack(spacing: SharpitSpacing.sm) {
                    VStack(alignment: .leading, spacing: SharpitSpacing.xxs) {
                        Label("Coucher", systemImage: "moon.fill")
                            .font(SharpitTypography.meta)
                            .foregroundStyle(SharpitColor.slate)
                        DatePicker("Coucher", selection: $bedtime, displayedComponents: .hourAndMinute)
                            .labelsHidden()
                            .environment(\.locale, SharpitLocale.current)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(SharpitSpacing.sm)
                    .sharpitConcentricBackground(SharpitColor.tile, minimum: SharpitRadius.row)

                    VStack(alignment: .leading, spacing: SharpitSpacing.xxs) {
                        Label("Réveil", systemImage: "alarm.fill")
                            .font(SharpitTypography.meta)
                            .foregroundStyle(SharpitColor.slate)
                        Text(SleepTargetFormat.clock(SleepTargetFormat.wake(bedtime: Self.minutes(from: bedtime), duration: minutes)))
                            .font(SharpitTypography.data)
                            .foregroundStyle(SharpitColor.foreground)
                            .monospacedDigit()
                            .contentTransition(.numericText())
                            .frame(minHeight: 34, alignment: .leading)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(SharpitSpacing.sm)
                    .sharpitConcentricBackground(SharpitColor.tile, minimum: SharpitRadius.row)
                    .accessibilityElement(children: .combine)
                }
                .transition(.opacity.combined(with: .move(edge: .top)))

                Text("Réveil calculé avec ta durée visée.")
                    .font(SharpitTypography.meta)
                    .foregroundStyle(SharpitColor.slate)
            }
        }
    }

    private func stepButton(_ symbol: String, label: String, delta: Int) -> some View {
        Button { step(delta) } label: {
            Image(systemName: symbol)
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(SharpitColor.foreground)
                .frame(width: 52, height: 52)
                .background(SharpitColor.tile, in: Circle())
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
    private var isValid: Bool { WeightTargetPlate.isValid(text) }

    /// As tall as what it holds; the whole screen once the keyboard is up.
    @State private var detent: PresentationDetent = WeightTargetSheet.compact
    private static let compact = PresentationDetent.height(400)

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Objectif de poids")
                .font(SharpitTypography.system(size: 26, weight: .semibold, relativeTo: .title))
                .tracking(-0.4)
                .foregroundStyle(SharpitColor.foreground)
                .accessibilityAddTraits(.isHeader)
                .padding(.trailing, 56)
            WeightTargetPlate(text: $text, current: store.profile.targetWeightKg, isFocused: $isFocused)
                .padding(.top, 18)
            Spacer(minLength: 16)
            VStack(spacing: 6) {
                Button { save() } label: { Text("Enregistrer").frame(maxWidth: .infinity) }
                    .buttonStyle(CliniqueButtonStyle(kind: .primary, isLarge: true))
                    .disabled(!hasLoaded || !isValid)
                if store.profile.targetWeightKg != nil {
                    Button("Retirer l'objectif") {
                        text = ""
                        save()
                    }
                    .buttonStyle(CliniqueButtonStyle(kind: .plain))
                }
            }
        }
        .padding(.horizontal, 24)
        .padding(.top, 30)
        .padding(.bottom, SharpitSpacing.xs)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(SharpitColor.card)
        .disabled(!hasLoaded)
        .cliniqueSheetCross { dismiss() }
        .task {
            await store.load()
            text = ProfileFieldFormat.decimal(store.profile.targetWeightKg)
            hasLoaded = true
        }
        .onChange(of: isFocused) { _, focused in if focused { detent = .large } }
        .presentationDetents([Self.compact, .large], selection: $detent)
        .presentationDragIndicator(.visible)
        .sharpitSheet()
    }

    private func save() {
        var patch = AthleteProfilePatch()
        patch.setIfChanged(.targetWeightKg, double: parsed, was: store.profile.targetWeightKg)
        store.save(patch)
        dismiss()
    }
}

/// The weight target read big between − and +: typed in place, or stepped by half a kilo. Shared
/// by Santé's sheet and Nutrition's « Objectifs », so both set the one profile field the same way.
struct WeightTargetPlate: View {
    @Binding var text: String
    /// The saved target, where the steppers start from when the field is empty.
    let current: Double?
    var isFocused: FocusState<Bool>.Binding

    /// Empty clears the target; otherwise 30 to 250 kg.
    static func isValid(_ text: String) -> Bool {
        text.trimmingCharacters(in: .whitespaces).isEmpty
            || (ProfileFieldFormat.parseDecimal(text).map { (30...250).contains($0) } ?? false)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: SharpitSpacing.md) {
            HStack(alignment: .center, spacing: SharpitSpacing.sm) {
                SharpitStepButton(symbol: "minus", label: String(localized: "Moins 0,5 kg")) { step(-0.5) }
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    TextField("72,0", text: $text)
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                        .font(SharpitTypography.system(size: 44, weight: .semibold, relativeTo: .largeTitle, digits: true))
                        .tracking(-1.5)
                        .foregroundStyle(SharpitColor.foreground)
                        .minimumScaleFactor(0.5)
                        .lineLimit(1)
                        .fixedSize()
                        .focused(isFocused)
                        .accessibilityLabel("Poids cible en kilos")
                    Text("kg")
                        .font(SharpitTypography.system(size: 17, weight: .regular, relativeTo: .body))
                        .foregroundStyle(SharpitColor.slate)
                }
                .frame(maxWidth: .infinity)
                SharpitStepButton(symbol: "plus", label: String(localized: "Plus 0,5 kg")) { step(0.5) }
            }
            Text("Optionnel. Tracé sur ta courbe de poids et pris en compte dans la lecture nutritionnelle, jamais une alerte.")
                .font(SharpitTypography.system(size: 14, weight: .regular, relativeTo: .footnote))
                .lineSpacing(2)
                .foregroundStyle(SharpitColor.slate)
                .fixedSize(horizontal: false, vertical: true)
            if !Self.isValid(text) {
                CliniqueStatusPill(String(localized: "Entre 30 et 250 kg"), status: .alert)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func step(_ delta: Double) {
        let next = min(max((ProfileFieldFormat.parseDecimal(text) ?? current ?? 70) + delta, 30), 250)
        text = ProfileFieldFormat.decimal(next)
    }
}
