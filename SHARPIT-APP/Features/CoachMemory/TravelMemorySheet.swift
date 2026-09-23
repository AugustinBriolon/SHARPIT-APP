import MapKit
import SwiftUI

enum AllowedDiscipline: String, CaseIterable, Identifiable, Sendable {
    case run = "RUN"
    case bike = "BIKE"
    case swim = "SWIM"
    case strength = "STRENGTH"
    case mobility = "MOBILITY"

    var id: String { rawValue }

    var label: String {
        switch self {
        case .run: "Course"
        case .bike: "Vélo"
        case .swim: "Natation"
        case .strength: "Muscu"
        case .mobility: "Mobilité"
        }
    }

    var symbol: String {
        switch self {
        case .run: "figure.run"
        case .bike: "bicycle"
        case .swim: "figure.pool.swim"
        case .strength: "figure.strengthtraining.traditional"
        case .mobility: "figure.yoga"
        }
    }
}

struct TravelMemorySheet: View {
    @Bindable var store: CoachMemoryStore
    @Environment(\.dismiss) private var dismiss

    @State private var type: CoachMemoryType = .travel
    @State private var label: String = ""
    @State private var locationLabel: String = ""
    @State private var startDate: Date = Date()
    @State private var endDate: Date = Calendar.current.date(byAdding: .day, value: 3, to: Date()) ?? Date()
    @State private var trainingConstraint: TravelTrainingConstraint = .reduced
    @State private var selectedDisciplines: Set<String> = ["RUN", "BIKE", "SWIM", "STRENGTH", "MOBILITY"]
    @State private var note: String = ""
    @State private var isSubmitting = false

    @State private var completer = LocationSearchCompleter()
    @State private var isShowingSuggestions = false
    @State private var isSelectingSuggestion = false

    var isSaveDisabled: Bool {
        if type == .travel && locationLabel.trimmingCharacters(in: .whitespaces).isEmpty && label.trimmingCharacters(in: .whitespaces).isEmpty {
            return true
        }
        if type == .constraint && label.trimmingCharacters(in: .whitespaces).isEmpty {
            return true
        }
        return isSubmitting
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Type", selection: $type) {
                        ForEach(CoachMemoryType.allCases) { t in
                            Text(t.label).tag(t)
                        }
                    }
                    .pickerStyle(.segmented)
                }

                Section(eyebrow: "Détails") {
                    if type == .travel {
                        VStack(alignment: .leading, spacing: SharpitSpacing.xs) {
                            TextField("Lieu / Destination (ex: Londres, Chamonix...)", text: $locationLabel)
                                .onChange(of: locationLabel) { _, newValue in
                                    guard !isSelectingSuggestion else { return }
                                    completer.query = newValue
                                    isShowingSuggestions = !completer.suggestions.isEmpty
                                }

                            if isShowingSuggestions && !completer.suggestions.isEmpty {
                                VStack(alignment: .leading, spacing: 6) {
                                    ForEach(completer.suggestions.prefix(4), id: \.self) { suggestion in
                                        Button {
                                            selectSuggestion(suggestion)
                                        } label: {
                                            HStack(spacing: SharpitSpacing.xs) {
                                                Image(systemName: "mappin.and.ellipse")
                                                    .font(SharpitTypography.meta)
                                                    .foregroundStyle(SharpitColor.primary)
                                                VStack(alignment: .leading, spacing: 1) {
                                                    Text(suggestion.title)
                                                        .font(SharpitTypography.bodyEmphasis)
                                                        .foregroundStyle(SharpitColor.foreground)
                                                    if !suggestion.subtitle.isEmpty {
                                                        Text(suggestion.subtitle)
                                                            .font(SharpitTypography.meta)
                                                            .foregroundStyle(SharpitColor.mutedForeground)
                                                    }
                                                }
                                                Spacer()
                                            }
                                            .padding(.vertical, 6)
                                            .contentShape(Rectangle())
                                        }
                                        .buttonStyle(.borderless)
                                        .highPriorityGesture(TapGesture().onEnded {
                                            selectSuggestion(suggestion)
                                        })

                                        if suggestion != completer.suggestions.prefix(4).last {
                                            Divider()
                                        }
                                    }
                                }
                                .padding(8)
                                .background(SharpitColor.analysisSurfaceAlt, in: RoundedRectangle(cornerRadius: 8))
                            }
                        }
                        .onChange(of: completer.suggestions) { _, newSuggs in
                            guard !isSelectingSuggestion else { return }
                            isShowingSuggestions = !newSuggs.isEmpty && !locationLabel.trimmingCharacters(in: .whitespaces).isEmpty
                        }

                        TextField("Titre (optionnel, ex: Déplacement pro)", text: $label)
                    } else {
                        TextField("Motif (ex: Astreinte, Travaux...)", text: $label)
                    }

                    DatePicker("Début", selection: $startDate, displayedComponents: .date)
                    DatePicker("Fin", selection: $endDate, displayedComponents: .date)
                }

                Section(
                    eyebrow: "Impact sur l'entraînement",
                    footer: constraintFooter
                ) {
                    Picker("Contrainte générale", selection: $trainingConstraint) {
                        ForEach(TravelTrainingConstraint.allCases) { c in
                            Text(c.label).tag(c)
                        }
                    }
                    .pickerStyle(.menu)
                    .onChange(of: trainingConstraint) { _, newC in
                        if newC == .none {
                            selectedDisciplines = []
                        } else if newC == .mobilityOnly {
                            selectedDisciplines = ["MOBILITY"]
                        } else if selectedDisciplines.isEmpty {
                            selectedDisciplines = ["RUN", "BIKE", "SWIM", "STRENGTH", "MOBILITY"]
                        }
                    }

                    if trainingConstraint != .none {
                        VStack(alignment: .leading, spacing: SharpitSpacing.xs) {
                            Text("Sports possibles sur place")
                                .font(SharpitTypography.meta)
                                .foregroundStyle(SharpitColor.mutedForeground)

                            disciplinesChipsView
                        }
                        .padding(.vertical, 4)
                    }

                    TextField("Notes pour le coach (optionnel)", text: $note, axis: .vertical)
                        .lineLimit(2...4)
                }
            }
            .sharpitGroupedList()
            .navigationTitle(type == .travel ? "Nouveau déplacement" : "Nouvelle contrainte")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Annuler") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Ajouter") {
                        Task { await submit() }
                    }
                    .disabled(isSaveDisabled)
                }
            }
        }
        .presentationDetents([.large])
        .sharpitSheet()
    }

    private var disciplinesChipsView: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: SharpitSpacing.xs) {
                ForEach(AllowedDiscipline.allCases) { disc in
                    let isSelected = selectedDisciplines.contains(disc.rawValue)
                    Button {
                        if isSelected {
                            selectedDisciplines.remove(disc.rawValue)
                        } else {
                            selectedDisciplines.insert(disc.rawValue)
                        }
                    } label: {
                        HStack(spacing: 5) {
                            Image(systemName: disc.symbol)
                                .font(.system(size: 13))
                            Text(disc.label)
                                .font(SharpitTypography.meta)
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 7)
                        .background(
                            isSelected ? SharpitColor.primary.opacity(0.15) : SharpitColor.analysisSurfaceAlt,
                            in: Capsule()
                        )
                        .foregroundStyle(isSelected ? SharpitColor.primary : SharpitColor.mutedForeground)
                        .overlay(
                            Capsule()
                                .stroke(isSelected ? SharpitColor.primary : SharpitColor.analysisBorder, lineWidth: 1)
                        )
                    }
                    .buttonStyle(.borderless)
                }
            }
            .padding(.vertical, 2)
        }
    }

    private func selectSuggestion(_ suggestion: LocationSuggestion) {
        isSelectingSuggestion = true
        let full = [suggestion.title, suggestion.subtitle].filter { !$0.isEmpty }.joined(separator: ", ")
        locationLabel = full
        isShowingSuggestions = false
        completer.clear()
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
        Task {
            try? await Task.sleep(nanoseconds: 150_000_000)
            isSelectingSuggestion = false
        }
    }

    private var constraintFooter: String {
        switch trainingConstraint {
        case .full: "Le coach continue de prescrire des séances complètes selon les sports disponibles."
        case .reduced: "Le coach allège le volume et l'intensité pendant cette période."
        case .mobilityOnly: "Seules des séances de récupération et mobilité seront proposées."
        case .none: "Aucune séance ne sera planifiée sur ces dates."
        }
    }

    @MainActor
    private func submit() async {
        isSubmitting = true
        defer { isSubmitting = false }

        let allowed = trainingConstraint == .none ? [] : Array(selectedDisciplines).sorted()

        let input = CreateCoachMemoryInput(
            type: type,
            label: label.trimmingCharacters(in: .whitespaces).isEmpty ? nil : label.trimmingCharacters(in: .whitespaces),
            locationLabel: locationLabel.trimmingCharacters(in: .whitespaces).isEmpty ? nil : locationLabel.trimmingCharacters(in: .whitespaces),
            startDate: startDate,
            endDate: endDate,
            note: note.trimmingCharacters(in: .whitespaces).isEmpty ? nil : note.trimmingCharacters(in: .whitespaces),
            trainingConstraint: trainingConstraint,
            allowedDisciplines: allowed.isEmpty ? nil : allowed
        )

        let ok = await store.createEntry(input)
        if ok {
            dismiss()
        }
    }
}
