import SwiftUI

/// A new goal, pushed in the Objectifs stack rather than presented over it: Objectifs is
/// already a sheet, and a sheet over a sheet is a stack the athlete cannot see.
struct GoalCreateView: View {
    @Bindable var store: GoalStore
    @Environment(\.dismiss) private var dismiss

    @State private var kind: GoalKind = .race
    @State private var title: String = ""
    @State private var priority: GoalPriority = .a
    @State private var targetDate: Date = Calendar.current.date(byAdding: .month, value: 3, to: Date()) ?? Date()
    @State private var location: String = ""
    @State private var targetPerformance: String = ""
    @State private var raceFormat: String = ""

    // Metric fields
    @State private var targetValueText: String = ""
    @State private var currentValueText: String = ""
    @State private var unit: String = ""

    @State private var notes: String = ""
    @State private var isSubmitting = false

    var isSaveDisabled: Bool {
        title.trimmingCharacters(in: .whitespaces).isEmpty || isSubmitting
    }

    var body: some View {
        Form {
            Section {
                Picker("Type d'objectif", selection: $kind) {
                    ForEach(GoalKind.allCases) { k in
                        Text(k.label).tag(k)
                    }
                }
                .pickerStyle(.segmented)
            }

            Section(eyebrow: "Détails") {
                TextField("Titre de l'objectif", text: $title)

                if kind == .race {
                    Picker("Priorité", selection: $priority) {
                        ForEach(GoalPriority.allCases) { p in
                            Text(p.label).tag(p)
                        }
                    }

                    DatePicker("Date de la course", selection: $targetDate, displayedComponents: .date)

                    TextField("Format (ex: Marathon, 70.3...)", text: $raceFormat)
                    TextField("Lieu (ex: Nice, France)", text: $location)
                    TextField("Chrono visé (ex: 3h30)", text: $targetPerformance)
                } else {
                    TextField("Valeur cible", text: $targetValueText)
                        .keyboardType(.decimalPad)
                    TextField("Valeur actuelle (optionnel)", text: $currentValueText)
                        .keyboardType(.decimalPad)
                    TextField("Unité (ex: W, km, h, kg)", text: $unit)
                    DatePicker("Date cible (optionnelle)", selection: $targetDate, displayedComponents: .date)
                }

                TextField("Notes libres", text: $notes, axis: .vertical)
                    .lineLimit(3...5)
            }
        }
        .sharpitGroupedList()
        .navigationTitle("Nouvel objectif")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Ajouter") {
                    Task { await submit() }
                }
                .disabled(isSaveDisabled)
            }
        }
    }

    @MainActor
    private func submit() async {
        isSubmitting = true
        defer { isSubmitting = false }

        let targetVal = Double(targetValueText.replacingOccurrences(of: ",", with: "."))
        let currentVal = Double(currentValueText.replacingOccurrences(of: ",", with: "."))

        let input = CreateGoalInput(
            title: title.trimmingCharacters(in: .whitespaces),
            kind: kind,
            priority: kind == .race ? priority : nil,
            targetDate: targetDate,
            location: location.isEmpty ? nil : location,
            raceFormat: raceFormat.isEmpty ? nil : raceFormat,
            targetPerformance: targetPerformance.isEmpty ? nil : targetPerformance,
            targetValue: targetVal,
            startValue: nil,
            currentValue: currentVal,
            unit: unit.isEmpty ? nil : unit,
            notes: notes.isEmpty ? nil : notes
        )

        let ok = await store.create(input)
        if ok {
            dismiss()
        }
    }
}
