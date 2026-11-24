import SwiftUI

/// What the picker hands back: an exercise to add to the session.
struct ExercisePick: Equatable {
    let name: String
    var catalogId: String?
    /// For an exercise of the athlete's own: « Zone travaillée : Épaules ».
    var note: String?
    var history: V1StrengthExercise?
}

/// « Ajouter un exercice »: a search over the athlete's own exercises first — each with what
/// they last did — then the catalog; when nothing fits, the words typed become an exercise of
/// their own once the zone it works is named. Saved with its sets, it is found here next time.
struct ExercisePickerSheet: View {
    let library: [V1StrengthExercise]
    let onPick: (ExercisePick) -> Void

    @State private var query = ""
    /// The name being created, once « Créer » is tapped: the sheet then asks for its zone.
    @State private var creating: String?
    @FocusState private var isSearching: Bool
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            CliniqueSheetTitle(creating == nil ? String(localized: "Ajouter un exercice") : String(localized: "Quelle zone travaille-t-il ?"))
                .padding(.horizontal, 24)
                .padding(.top, 30)
                .padding(.bottom, 14)
            if let creating {
                zoneStep(creating)
            } else {
                searchStep
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(SharpitColor.card)
        .cliniqueSheetCross { dismiss() }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .sharpitSheet()
        .animation(SharpitMotion.reveal, value: creating)
    }

    private var searchStep: some View {
        let results = ExercisePickerReadout.results(query: query, library: library)
        return VStack(spacing: 0) {
            HStack(spacing: SharpitSpacing.xs) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(SharpitColor.slate)
                    .accessibilityHidden(true)
                TextField("Squat, gainage, étirement…", text: $query)
                    .font(SharpitTypography.system(size: 17, weight: .regular, relativeTo: .body))
                    .focused($isSearching)
                    .submitLabel(.search)
                    .autocorrectionDisabled()
            }
            .padding(.horizontal, 16)
            .frame(minHeight: 48)
            .overlay(Capsule().strokeBorder(SharpitColor.outline, lineWidth: 1))
            .padding(.horizontal, 24)
            .padding(.bottom, 10)

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    if !results.own.isEmpty {
                        section(String(localized: "Tes exercices"))
                        ForEach(results.own) { exercise in
                            row(exercise.name, detail: ExercisePickerReadout.detail(exercise), catalogId: exercise.catalogId) {
                                pick(ExercisePick(name: exercise.name, catalogId: exercise.catalogId, note: exercise.note, history: exercise))
                            }
                            CliniqueDivider()
                        }
                    }
                    if !results.catalog.isEmpty {
                        section(String(localized: "Catalogue"))
                        ForEach(results.catalog) { entry in
                            row(entry.name, detail: nil, catalogId: entry.id) { pick(ExercisePick(name: entry.name, catalogId: entry.id)) }
                            CliniqueDivider()
                        }
                    }
                    if let name = results.creatable {
                        Button { creating = name } label: {
                            Label("Créer « \(name) »", systemImage: "plus").frame(maxWidth: .infinity)
                        }
                        .buttonStyle(CliniqueButtonStyle(kind: .outline))
                        .padding(.top, 18)
                    } else if results.own.isEmpty, results.catalog.isEmpty {
                        Text("Tape le nom d'un exercice. S'il n'existe pas, tu pourras le créer.")
                            .font(SharpitTypography.system(size: 15, weight: .regular, relativeTo: .subheadline))
                            .foregroundStyle(SharpitColor.slate)
                            .padding(.top, 18)
                    }
                }
                .padding(.horizontal, 24)
                .padding(.bottom, SharpitSpacing.lg)
            }
            .scrollDismissesKeyboard(.interactively)
        }
        .onAppear { isSearching = true }
    }

    /// One answer of a short list of zones: the exercise is created on the tap.
    private func zoneStep(_ name: String) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Text(name)
                    .font(SharpitTypography.system(size: 15, weight: .regular, relativeTo: .subheadline))
                    .foregroundStyle(SharpitColor.slate)
                    .padding(.bottom, 10)
                CliniqueDivider()
                ForEach(ExercisePickerReadout.zones, id: \.self) { zone in
                    row(zone, detail: nil, isExercise: false) {
                        pick(ExercisePick(name: name, note: ExercisePickerReadout.zoneNote(zone)))
                    }
                    CliniqueDivider()
                }
                Button("Retour à la recherche") { creating = nil }
                    .buttonStyle(CliniqueButtonStyle(kind: .plain))
                    .frame(maxWidth: .infinity)
                    .padding(.top, 10)
            }
            .padding(.horizontal, 24)
            .padding(.bottom, SharpitSpacing.lg)
        }
    }

    private func section(_ title: String) -> some View {
        Text(title)
            .font(SharpitTypography.sectionTitle)
            .tracking(SharpitTypography.sectionTitleTracking)
            .foregroundStyle(SharpitColor.foreground)
            .accessibilityAddTraits(.isHeader)
            .padding(.top, 18)
            .padding(.bottom, 4)
    }

    /// A zone answer carries no picture; an exercise shows its demonstration's still, or the
    /// strength glyph when the catalog has none.
    private func row(_ title: String, detail: String?, catalogId: String? = nil, isExercise: Bool = true, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: SharpitSpacing.sm) {
                if isExercise {
                    GuidedExerciseThumbView(url: ExerciseMediaCatalog.thumbURL(catalogId: catalogId, name: title), size: 44)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(SharpitTypography.system(size: 16, weight: .regular, relativeTo: .callout))
                        .foregroundStyle(SharpitColor.foreground)
                        .multilineTextAlignment(.leading)
                    if let detail {
                        Text(detail)
                            .font(SharpitTypography.system(size: 13, weight: .regular, relativeTo: .caption, digits: true))
                            .foregroundStyle(SharpitColor.slate)
                            .multilineTextAlignment(.leading)
                    }
                }
                Spacer(minLength: SharpitSpacing.xs)
                Image(systemName: "plus")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(SharpitColor.slate)
                    .accessibilityHidden(true)
            }
            .frame(maxWidth: .infinity, minHeight: 52, alignment: .leading)
            .contentShape(.rect)
        }
        .buttonStyle(.sharpitPressable)
    }

    private func pick(_ exercise: ExercisePick) {
        onPick(exercise)
        dismiss()
    }
}

enum ExercisePickerReadout {
    struct Results: Equatable {
        var own: [V1StrengthExercise] = []
        var catalog: [ExerciseMediaCatalog.Entry] = []
        /// The words typed, when no exercise of the athlete's or of the catalog bears that name.
        var creatable: String?
    }

    /// The zones an exercise of the athlete's own can be filed under.
    static var zones: [String] {
        [
            String(localized: "Épaules"), String(localized: "Pectoraux"), String(localized: "Dos"),
            String(localized: "Bras"), String(localized: "Tronc"), String(localized: "Hanches et fessiers"),
            String(localized: "Cuisses"), String(localized: "Mollets et chevilles"), String(localized: "Corps entier"),
        ]
    }

    /// « Dernière fois … · Meilleur … », then the athlete's own note on it when there is one.
    static func detail(_ exercise: V1StrengthExercise) -> String {
        [StrengthHistoryReadout.line(exercise), exercise.athleteNote].compactMap { $0 }.joined(separator: "\n")
    }

    static func zoneNote(_ zone: String) -> String { String(localized: "Zone travaillée : \(zone)") }

    /// The athlete's exercises first (all of them before anything is typed), then the catalog's
    /// that are not already theirs; an exact name found in neither can be created.
    static func results(query: String, library: [V1StrengthExercise]) -> Results {
        let typed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let words = ExerciseMediaCatalog.normalize(typed).split(separator: " ")
        guard !words.isEmpty else { return Results(own: library) }
        let own = library.filter { exercise in words.allSatisfy { exercise.id.contains($0) } }
        let ownCatalogIds = Set(own.compactMap(\.catalogId))
        let ownKeys = Set(own.map(\.id))
        let catalog = ExerciseMediaCatalog.search(typed).filter {
            !ownCatalogIds.contains($0.id) && !ownKeys.contains(StrengthExerciseKey.of($0.name))
        }
        let key = StrengthExerciseKey.of(typed)
        let exists = ownKeys.contains(key) || catalog.contains { StrengthExerciseKey.of($0.name) == key }
        return Results(own: own, catalog: catalog, creatable: exists || typed.count < 2 ? nil : typed)
    }
}
