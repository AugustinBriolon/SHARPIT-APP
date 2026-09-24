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
            List {
                Section(
                    eyebrow: "Durée visée",
                    footer: "La lecture de tes nuits et ta dette de sommeil se comparent à ce repère."
                ) {
                    HStack {
                        Text(SleepTargetFormat.duration(minutes))
                            .font(SharpitTypography.data)
                            .tracking(SharpitTypography.dataTracking)
                            .monospacedDigit()
                            .contentTransition(.numericText(value: Double(minutes)))
                        Spacer()
                        Stepper("Durée", value: $minutes, in: 240...720, step: 15)
                            .labelsHidden()
                    }
                    SharpitSegmentedControl(
                        selection: $minutes,
                        options: Self.presets.map {
                            SharpitSegmentedControl<Int>.Option(value: $0, label: SleepTargetFormat.short($0))
                        }
                    )
                    .listRowSeparator(.hidden)
                }
                .sharpitListRows()

                Section(
                    eyebrow: "Coucher",
                    footer: "Un repère de régularité : se coucher à heure fixe compte autant que la durée."
                ) {
                    Toggle("Heure de coucher visée", isOn: $hasBedtime.animation(SharpitMotion.selection))
                        .tint(SharpitColor.primary)
                    if hasBedtime {
                        DatePicker("Coucher", selection: $bedtime, displayedComponents: .hourAndMinute)
                            .environment(\.locale, SharpitLocale.french)
                    }
                }
                .sharpitListRows()

                if let error = store.saveError {
                    Section {
                        Label(error, systemImage: "exclamationmark.triangle")
                            .font(SharpitTypography.meta)
                            .foregroundStyle(SharpitColor.signalRisk)
                    }
                    .listRowBackground(Color.clear)
                }
            }
            .sharpitGroupedList()
            .disabled(!hasLoaded)
            .redacted(reason: hasLoaded ? [] : .placeholder)
            .navigationTitle("Objectifs de sommeil")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Annuler") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    if store.isSaving {
                        ProgressView()
                    } else {
                        Button("OK") { Task { await save() } }
                            .disabled(!hasLoaded)
                    }
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
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .sharpitSheet()
    }

    private func save() async {
        var patch = AthleteProfilePatch()
        patch.setIfChanged(.sleepTargetMinutes, int: minutes, was: store.profile.sleepTargetMinutes)
        patch.setIfChanged(
            .sleepBedtimeTargetMin,
            int: hasBedtime ? Self.minutes(from: bedtime) : nil,
            was: store.profile.sleepBedtimeTargetMin
        )
        if await store.save(patch) { dismiss() }
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
            List {
                Section(
                    eyebrow: "Poids cible",
                    footer: "Optionnel. Tracé sur ta courbe de poids et pris en compte dans la lecture nutritionnelle — jamais une alerte."
                ) {
                    HStack {
                        TextField("72,0", text: $text)
                            .keyboardType(.decimalPad)
                            .font(SharpitTypography.data)
                            .focused($isFocused)
                        Text("kg")
                            .foregroundStyle(SharpitColor.mutedForeground)
                    }
                    if !isValid {
                        Text("Entre 30 et 250 kg.")
                            .font(SharpitTypography.meta)
                            .foregroundStyle(SharpitColor.signalRisk)
                    }
                    if store.profile.targetWeightKg != nil {
                        Button("Retirer l'objectif", role: .destructive) {
                            text = ""
                            Task { await save() }
                        }
                    }
                }
                .sharpitListRows()

                if let error = store.saveError {
                    Section {
                        Label(error, systemImage: "exclamationmark.triangle")
                            .font(SharpitTypography.meta)
                            .foregroundStyle(SharpitColor.signalRisk)
                    }
                    .listRowBackground(Color.clear)
                }
            }
            .sharpitGroupedList()
            .disabled(!hasLoaded)
            .navigationTitle("Objectif de poids")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Annuler") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    if store.isSaving {
                        ProgressView()
                    } else {
                        Button("OK") { Task { await save() } }
                            .disabled(!hasLoaded || !isValid)
                    }
                }
            }
            .task {
                await store.load()
                text = ProfileFieldFormat.decimal(store.profile.targetWeightKg)
                hasLoaded = true
                isFocused = true
            }
        }
        .presentationDetents([.medium])
        .presentationDragIndicator(.visible)
        .sharpitSheet()
    }

    private func save() async {
        var patch = AthleteProfilePatch()
        patch.setIfChanged(.targetWeightKg, double: parsed, was: store.profile.targetWeightKg)
        if await store.save(patch) { dismiss() }
    }
}
