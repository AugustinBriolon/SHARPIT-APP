import SwiftUI

/// An exercise's sheet, pushed from its card in the guided session (the athlete's call,
/// 2026-11-28): the sets are done on the card, the sheet says how to do the movement.
///
/// « Guide » holds the demonstration, a search for its technique on YouTube, the figures — the
/// last session, the best, today's volume: the load lives here, not in the lists — the coach's
/// instruction and the athlete's pinned note. « À propos » names the muscle, the zone and the
/// equipment as the catalog describes them. « Évolution » is the exercise's curve over the days it
/// was done, then those days' sets.
struct ExerciseGuidePage: View {
    enum Tab: Hashable {
        case guide
        case about
        case evolution
    }

    let name: String
    var catalogId: String?
    /// « Exercice 2 sur 5 »; nil when the sheet stands outside a session's order.
    var position: String?
    /// The coach's instruction on it for this session.
    var coachNotes: String?
    /// Today's volume, « 1 920 kg », nil until a loaded set is done.
    var volume: String?
    /// Nil when nothing can be read from the server: no note, no history.
    var tokenProvider: (() async throws -> String)?
    var onEditNote: () -> Void = {}

    @State private var tab: Tab
    @Environment(\.openURL) private var openURL

    init(
        name: String,
        catalogId: String? = nil,
        position: String? = nil,
        coachNotes: String? = nil,
        volume: String? = nil,
        tokenProvider: (() async throws -> String)? = nil,
        opening tab: Tab = .guide,
        onEditNote: @escaping () -> Void = {}
    ) {
        self.name = name
        self.catalogId = catalogId
        self.position = position
        self.coachNotes = coachNotes
        self.volume = volume
        self.tokenProvider = tokenProvider
        self.onEditNote = onEditNote
        _tab = State(initialValue: tab)
    }

    private var details: ExerciseMediaCatalog.Details? {
        ExerciseMediaCatalog.details(catalogId: catalogId, name: name)
    }

    private var tabs: [SharpitSegmentedControl<Tab>.Option] {
        var tabs: [SharpitSegmentedControl<Tab>.Option] = [.init(value: .guide, label: String(localized: "Guide"))]
        if details != nil { tabs.append(.init(value: .about, label: String(localized: "À propos"))) }
        if tokenProvider != nil { tabs.append(.init(value: .evolution, label: String(localized: "Évolution"))) }
        return tabs
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: SharpitSpacing.lg) {
                VStack(alignment: .leading, spacing: 6) {
                    if let position {
                        Text(position)
                            .font(SharpitTypography.system(size: 16, weight: .regular, relativeTo: .callout, digits: true))
                            .foregroundStyle(SharpitColor.slate)
                    }
                    Text(name)
                        .font(SharpitTypography.system(size: 28, weight: .semibold, relativeTo: .title))
                        .tracking(-0.5)
                        .foregroundStyle(SharpitColor.foreground)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityAddTraits(.isHeader)
                    if let details {
                        Text(details.equipment)
                            .font(SharpitTypography.system(size: 16, weight: .regular, relativeTo: .callout))
                            .foregroundStyle(SharpitColor.slate)
                    }
                }

                if tabs.count > 1 {
                    SharpitSegmentedControl(selection: $tab, options: tabs)
                }

                switch tab {
                case .guide:
                    guide
                case .about:
                    if let details { about(details) }
                case .evolution:
                    if let tokenProvider {
                        ExerciseProgressionContent(name: name, tokenProvider: tokenProvider)
                    }
                }
            }
            .padding(.horizontal, 24)
            .padding(.vertical, SharpitSpacing.md)
        }
    }

    private var guide: some View {
        VStack(alignment: .leading, spacing: SharpitSpacing.lg) {
            if let gif = ExerciseMediaCatalog.gifURL(catalogId: catalogId, name: name) {
                VStack(alignment: .leading, spacing: SharpitSpacing.xs) {
                    GuidedExerciseMediaView(url: gif, height: 240)
                    Text(ExerciseMediaCatalog.attribution)
                        .font(SharpitTypography.meta)
                        .foregroundStyle(SharpitColor.slate)
                }
            }

            youTubeLink

            ExerciseFiguresStrip(history: StrengthLibraryStore.shared.history(of: name), volume: volume)

            if let coachNotes, !coachNotes.isEmpty {
                section(String(localized: "Consigne du coach")) {
                    Text(coachNotes)
                        .font(SharpitTypography.system(size: 16, weight: .regular, relativeTo: .callout))
                        .foregroundStyle(SharpitColor.foreground)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            if tokenProvider != nil {
                section(String(localized: "Note épinglée")) { pinnedNote }
            }
        }
    }

    /// What the movement works and with what, as lines on the sheet. The catalog names one target
    /// muscle and its zone; it draws no body map, so none is drawn.
    private func about(_ details: ExerciseMediaCatalog.Details) -> some View {
        VStack(alignment: .leading, spacing: SharpitSpacing.lg) {
            section(String(localized: "Muscles")) {
                VStack(spacing: 0) {
                    CliniqueDivider()
                    aboutRow(symbol: "figure.strengthtraining.traditional", title: details.muscle, detail: String(localized: "Principal"))
                    CliniqueDivider()
                    aboutRow(symbol: "figure.stand", title: details.zone, detail: String(localized: "Zone"))
                    CliniqueDivider()
                }
            }
            section(String(localized: "Équipement")) {
                VStack(spacing: 0) {
                    CliniqueDivider()
                    aboutRow(symbol: "dumbbell", title: details.equipment, detail: nil)
                    CliniqueDivider()
                }
            }
        }
    }

    private func aboutRow(symbol: String, title: String, detail: String?) -> some View {
        HStack(spacing: SharpitSpacing.sm) {
            Image(systemName: symbol)
                .font(.system(size: 17, weight: .regular))
                .foregroundStyle(SharpitColor.foreground)
                .frame(width: 28)
                .accessibilityHidden(true)
            Text(title)
                .font(SharpitTypography.system(size: 17, weight: .semibold, relativeTo: .body))
                .foregroundStyle(SharpitColor.foreground)
            Spacer(minLength: SharpitSpacing.xs)
            if let detail {
                Text(detail)
                    .font(SharpitTypography.system(size: 15, weight: .regular, relativeTo: .subheadline))
                    .foregroundStyle(SharpitColor.slate)
            }
        }
        .frame(minHeight: SharpitSpacing.rowHeight)
        .accessibilityElement(children: .combine)
    }

    /// The movement filmed by others: a search, since no one link fits every exercise.
    private var youTubeLink: some View {
        Button {
            if let url = ExerciseGuideReadout.youTubeSearchURL(name) { openURL(url) }
        } label: {
            HStack(spacing: SharpitSpacing.sm) {
                Image(systemName: "play.rectangle")
                    .font(.system(size: 20, weight: .regular))
                    .foregroundStyle(SharpitColor.foreground)
                    .frame(width: 44, height: 44)
                    .sharpitConcentricBackground(SharpitColor.tile, minimum: SharpitRadius.small)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Voir l’exécution sur YouTube")
                        .font(SharpitTypography.system(size: 16, weight: .semibold, relativeTo: .body))
                        .foregroundStyle(SharpitColor.foreground)
                    Text(ExerciseGuideReadout.youTubeQuery(name))
                        .font(SharpitTypography.system(size: 15, weight: .regular, relativeTo: .subheadline))
                        .foregroundStyle(SharpitColor.slate)
                        .lineLimit(2)
                }
                .multilineTextAlignment(.leading)
                Spacer(minLength: SharpitSpacing.xs)
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(SharpitColor.slate)
                    .accessibilityHidden(true)
            }
            .cliniqueCard()
            .contentShape(.rect)
        }
        .buttonStyle(.sharpitPressable)
        .accessibilityHint("Ouvre une recherche YouTube")
    }

    /// The athlete's standing note on the exercise, or the way to write one.
    private var pinnedNote: some View {
        let note = StrengthLibraryStore.shared.athleteNote(of: name)
        return Button(action: onEditNote) {
            HStack(alignment: .firstTextBaseline, spacing: SharpitSpacing.xs) {
                Image(systemName: "pin")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(SharpitColor.slate)
                    .accessibilityHidden(true)
                Text(note ?? String(localized: "Ajouter une note"))
                    .font(SharpitTypography.system(size: 16, weight: .regular, relativeTo: .callout))
                    .foregroundStyle(note == nil ? SharpitColor.slate : SharpitColor.foreground)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, SharpitSpacing.md)
            .padding(.vertical, 14)
            .frame(maxWidth: .infinity, minHeight: 48, alignment: .leading)
            .sharpitConcentricBackground(SharpitColor.tile, minimum: SharpitRadius.control)
            .contentShape(.rect)
        }
        .buttonStyle(.sharpitPressable)
        .accessibilityLabel(note.map { String(localized: "Note épinglée : \($0)") } ?? String(localized: "Ajouter une note"))
    }

    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: SharpitSpacing.sm) {
            Text(title)
                .font(SharpitTypography.sectionTitle)
                .tracking(SharpitTypography.sectionTitleTracking)
                .foregroundStyle(SharpitColor.foreground)
                .accessibilityAddTraits(.isHeader)
            content()
        }
    }
}

/// What the exercise's sheet asks of YouTube.
enum ExerciseGuideReadout {
    /// « Abdos jackknife technique »: the name as the athlete reads it, and what is looked for.
    static func youTubeQuery(_ name: String) -> String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return String(localized: "\(trimmed) technique")
    }

    /// A YouTube search — opened by the YouTube app when it is installed (universal link).
    static func youTubeSearchURL(_ name: String) -> URL? {
        var components = URLComponents(string: "https://www.youtube.com/results")
        components?.queryItems = [URLQueryItem(name: "search_query", value: youTubeQuery(name))]
        return components?.url
    }
}

/// An exercise's figures between two hairlines: last time, the best, today's volume — a column
/// each, its name over it. The volume's column is there before any set is done, empty.
struct ExerciseFiguresStrip: View {
    let history: V1StrengthExercise?
    let volume: String?

    private var columns: [(label: String, value: String?)] {
        var columns: [(String, String?)] = []
        if let history {
            columns.append((String(localized: "Dernière fois"), StrengthHistoryReadout.lastFigure(history)))
            if let best = StrengthHistoryReadout.bestFigure(history) { columns.append((String(localized: "Meilleur"), best)) }
        }
        columns.append((String(localized: "Volume"), volume))
        return columns
    }

    var body: some View {
        VStack(spacing: 0) {
            CliniqueDivider()
            HStack(alignment: .top, spacing: SharpitSpacing.sm) {
                ForEach(Array(columns.enumerated()), id: \.offset) { _, column in
                    VStack(alignment: .leading, spacing: 3) {
                        Text(column.label)
                            .font(SharpitTypography.meta)
                            .foregroundStyle(SharpitColor.slate)
                            .lineLimit(1)
                        Text(column.value ?? "—")
                            .font(SharpitTypography.system(size: 15, weight: .semibold, relativeTo: .subheadline, digits: true))
                            .foregroundStyle(column.value == nil ? SharpitColor.slate : SharpitColor.foreground)
                            .lineLimit(1)
                            .minimumScaleFactor(0.75)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityElement(children: .combine)
                }
            }
            .padding(.vertical, 10)
            CliniqueDivider()
        }
    }
}
