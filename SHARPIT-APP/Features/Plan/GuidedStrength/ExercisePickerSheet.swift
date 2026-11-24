import SwiftUI

/// What the picker hands back: an exercise to add to the session.
struct ExercisePick: Equatable {
    let name: String
    var catalogId: String?
    /// For an exercise of the athlete's own: « Zone travaillée : Épaules ».
    var note: String?
    var history: V1StrengthExercise?
}

/// « Ajouter un exercice »: the athlete's own exercises first — each with what they last did —
/// then the whole catalog from A to Z, with an index at the trailing edge to slide a finger on
/// (the athlete's request, 2026-11-24). Typing searches both; when nothing fits, the words typed
/// become an exercise of their own once the zone it works is named.
struct ExercisePickerSheet: View {
    let library: [V1StrengthExercise]
    let onPick: (ExercisePick) -> Void

    @State private var query = ""
    /// The name being created, once « Créer » is tapped: the sheet then asks for its zone.
    @State private var creating: String?
    @FocusState private var isSearching: Bool

    /// The rows end on a « + » only while the index is away, that is while a search is typed.
    private var showsAddGlyph: Bool {
        !ExerciseMediaCatalog.normalize(query).isEmpty || creating != nil
    }
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

            let browsed = results.isBrowsing ? ExercisePickerReadout.browseSections : []
            ScrollViewReader { proxy in
                ScrollView {
                    // Lazy: browsing lists the whole catalog, over a thousand lines with a picture each.
                    LazyVStack(alignment: .leading, spacing: 0, pinnedViews: .sectionHeaders) {
                        if !results.own.isEmpty {
                            // In a `ForEach` for its identity: a lazy stack can scroll to an identity it
                            // has not laid out, which a plain `.id` on a row far above cannot promise.
                            ForEach([ExercisePickerReadout.ownIndexTitle], id: \.self) { _ in
                                section(String(localized: "Tes exercices"))
                            }
                            ForEach(results.own) { exercise in
                                row(exercise.name, detail: ExercisePickerReadout.detail(exercise), catalogId: exercise.catalogId) {
                                    pick(ExercisePick(name: exercise.name, catalogId: exercise.catalogId, note: exercise.note, history: exercise))
                                }
                                CliniqueDivider()
                            }
                        }
                        ForEach(browsed) { letter in
                            Section {
                                ForEach(letter.entries) { entry in
                                    row(entry.name, detail: nil, catalogId: entry.id) { pick(ExercisePick(name: entry.name, catalogId: entry.id)) }
                                    CliniqueDivider()
                                }
                            } header: {
                                letterHeader(letter.title)
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
                        } else if results.own.isEmpty, results.catalog.isEmpty, !results.isBrowsing {
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
                .overlay(alignment: .trailing) {
                    if !browsed.isEmpty {
                        ExerciseIndexBar(
                            titles: ExercisePickerReadout.indexTitles(hasOwn: !results.own.isEmpty, sections: browsed)
                        ) { title in
                            isSearching = false
                            proxy.scrollTo(title, anchor: .top)
                        }
                    }
                }
            }
        }
    }

    /// A letter of the catalog, pinned while its exercises pass under it.
    private func letterHeader(_ title: String) -> some View {
        Text(title)
            .font(SharpitTypography.system(size: 13, weight: .semibold, relativeTo: .footnote))
            .foregroundStyle(SharpitColor.slate)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 6)
            .background(SharpitColor.card)
            .accessibilityAddTraits(.isHeader)
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
                // No « + » beside the index: letters and a trailing glyph compete for the same
                // edge (HIG, Lists and tables). The whole line is the button either way.
                if showsAddGlyph {
                    Image(systemName: "plus")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(SharpitColor.slate)
                        .accessibilityHidden(true)
                }
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

/// The picker's index, as Contacts has one: a column of letters at the trailing edge. A tap or a
/// finger sliding on it takes the list to that letter, a notch felt at each one crossed.
struct ExerciseIndexBar: View {
    let titles: [String]
    let onJump: (String) -> Void

    /// The letter last jumped to; kept after the finger lifts, for VoiceOver's value.
    @State private var current: String?
    @State private var isSliding = false

    var body: some View {
        VStack(spacing: 0) {
            ForEach(titles, id: \.self) { title in
                Text(title)
                    .font(SharpitTypography.system(size: 11, weight: .semibold, relativeTo: .caption2))
                    .foregroundStyle(isSliding && title == current ? SharpitColor.foreground : SharpitColor.slate)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(width: 28)
        .frame(maxHeight: CGFloat(titles.count) * 18)
        .contentShape(.rect)
        .overlay {
            GeometryReader { geometry in
                Color.clear
                    .contentShape(.rect)
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { value in
                                if !isSliding {
                                    isSliding = true
                                    SharpitHaptics.prepare()
                                }
                                jump(to: ExercisePickerReadout.indexTitle(
                                    at: value.location.y / max(geometry.size.height, 1), in: titles
                                ))
                            }
                            .onEnded { _ in isSliding = false }
                    )
            }
        }
        .accessibilityElement()
        .accessibilityLabel("Index alphabétique")
        .accessibilityValue(current ?? titles.first ?? "")
        .accessibilityAdjustableAction { direction in
            let index = titles.firstIndex(of: current ?? "") ?? -1
            let next = direction == .increment ? index + 1 : index - 1
            guard titles.indices.contains(next) else { return }
            jump(to: titles[next])
        }
    }

    private func jump(to title: String?) {
        guard let title, title != current else { return }
        current = title
        SharpitHaptics.play(.notch(major: false))
        onJump(title)
    }
}

enum ExercisePickerReadout {
    struct Results: Equatable {
        var own: [V1StrengthExercise] = []
        var catalog: [ExerciseMediaCatalog.Entry] = []
        /// The words typed, when no exercise of the athlete's or of the catalog bears that name.
        var creatable: String?
        /// Nothing typed: the whole catalog is listed from A to Z under the athlete's own.
        var isBrowsing = false
    }

    /// The exercises under one letter of the index.
    struct LetterSection: Identifiable, Equatable {
        let title: String
        let entries: [ExerciseMediaCatalog.Entry]
        var id: String { title }
    }

    /// What the index shows for « Tes exercices », above the letters.
    static let ownIndexTitle = "★"
    /// Where a name that starts with a figure is filed, after Z.
    static let otherIndexTitle = "#"

    /// The catalog from A to Z, built once.
    static let browseSections = sections(ExerciseMediaCatalog.browse)

    /// Exercises by first letter, A to Z then « # », each letter in alphabetical order whatever
    /// the case or the accents. A letter with no exercise is left out.
    static func sections(_ entries: [ExerciseMediaCatalog.Entry]) -> [LetterSection] {
        let keyed = entries.map { (key: ExerciseMediaCatalog.normalize($0.name), entry: $0) }
        let grouped = Dictionary(grouping: keyed) { item -> String in
            guard let first = item.key.first, first.isLetter, first.isASCII else { return otherIndexTitle }
            return String(first).uppercased()
        }
        return grouped
            .map { LetterSection(title: $0.key, entries: $0.value.sorted { $0.key < $1.key }.map(\.entry)) }
            .sorted { ($0.title == otherIndexTitle ? "~" : $0.title) < ($1.title == otherIndexTitle ? "~" : $1.title) }
    }

    static func indexTitles(hasOwn: Bool, sections: [LetterSection]) -> [String] {
        (hasOwn ? [ownIndexTitle] : []) + sections.map(\.title)
    }

    /// The letter under the finger, `fraction` of the way down the index; the ends hold past it.
    static func indexTitle(at fraction: Double, in titles: [String]) -> String? {
        guard !titles.isEmpty, fraction.isFinite else { return nil }
        let index = Int((fraction * Double(titles.count)).rounded(.down))
        return titles[min(max(index, 0), titles.count - 1)]
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
        guard !words.isEmpty else { return Results(own: library, isBrowsing: true) }
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
