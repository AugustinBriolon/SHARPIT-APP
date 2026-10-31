import SwiftUI

/// Where a list of dated entries goes next: a new one, or one to change.
enum CoachMemoryFormRoute: Hashable {
    case new
    case edit(CoachMemoryEntry)

    var entry: CoachMemoryEntry? {
        if case .edit(let entry) = self { entry } else { nil }
    }
}

/// Adds or changes one entry, pushed inside its list: one sheet at a time. The save waits for
/// the server's answer, and a refusal is said under the form, the form left as typed.
struct CoachMemoryEntryForm: View {
    let store: CoachMemoryStore
    let kinds: [CoachMemoryType]
    let entry: CoachMemoryEntry?

    @State private var draft: MemoryEntryDraft
    private let initial: MemoryEntryDraft
    @State private var isSaving = false
    @State private var failure: String?
    @State private var showingDeleteConfirmation = false
    @State private var completer = LocationSearchCompleter()
    @State private var isSelectingSuggestion = false
    @Environment(\.dismiss) private var dismiss

    init(store: CoachMemoryStore, kinds: [CoachMemoryType], entry: CoachMemoryEntry?) {
        self.store = store
        self.kinds = kinds
        self.entry = entry
        let start = entry.map { MemoryEntryDraft(entry: $0) } ?? MemoryEntryDraft(type: kinds.first ?? .travel)
        initial = start
        _draft = State(initialValue: start)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: SharpitSpacing.lg) {
                if entry == nil, kinds.count > 1 { kindChoice }
                nameField
                if draft.hasDates { dates }
                if draft.hasTraining { training }
                noteField
                if let failure {
                    Text(failure)
                        .font(SharpitTypography.meta)
                        .foregroundStyle(SharpitColor.signalRisk)
                }
                if entry != nil { deleteButton }
            }
            .padding(.horizontal, SharpitSpacing.pageInset)
            .padding(.vertical, SharpitSpacing.md)
        }
        .scrollDismissesKeyboard(.interactively)
        .background(SharpitCanvasBackground())
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        // A half-typed entry is not thrown away by a swipe back: « Annuler » says it.
        .navigationBarBackButtonHidden(true)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Annuler") { dismiss() }
            }
            ToolbarItem(placement: .confirmationAction) {
                if isSaving {
                    ProgressView()
                } else {
                    Button(entry == nil ? String(localized: "Ajouter") : String(localized: "Enregistrer")) {
                        Task { await save() }
                    }
                    .disabled(!draft.isComplete || draft == initial)
                }
            }
        }
        .confirmationDialog(
            String(localized: "Supprimer cette entrée ?"),
            isPresented: $showingDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button("Supprimer", role: .destructive) {
                guard let entry else { return }
                dismiss()
                Task { await store.deleteEntry(id: entry.id) }
            }
            Button("Annuler", role: .cancel) {}
        }
    }

    private var title: String {
        switch draft.type {
        case .travel: entry == nil ? String(localized: "Nouveau déplacement") : String(localized: "Déplacement")
        case .constraint: entry == nil ? String(localized: "Nouvelle contrainte") : String(localized: "Contrainte")
        case .injury: entry == nil ? String(localized: "Nouvelle blessure") : String(localized: "Blessure")
        case .preference: entry == nil ? String(localized: "Nouvelle préférence") : String(localized: "Préférence")
        case .note: entry == nil ? String(localized: "Nouvelle note") : String(localized: "Note")
        }
    }

    private var kindChoice: some View {
        SharpitSegmentedChoice(
            options: kinds,
            label: \.shortLabel,
            selection: Binding(get: { draft.type }, set: { if let type = $0 { draft.type = type } })
        )
    }

    @ViewBuilder private var nameField: some View {
        if draft.type == .travel {
            VStack(alignment: .leading, spacing: SharpitSpacing.xs) {
                SharpitFormField(String(localized: "Destination"), placeholder: String(localized: "Londres, Chamonix…"), text: $draft.location)
                    .onChange(of: draft.location) { _, newValue in
                        guard !isSelectingSuggestion else { return }
                        completer.query = newValue
                    }
                suggestions
            }
        } else {
            SharpitFormField(
                draft.type == .injury ? String(localized: "Gène ou blessure") : String(localized: "Titre"),
                placeholder: placeholder,
                text: $draft.title
            )
        }
    }

    private var placeholder: String {
        switch draft.type {
        case .constraint: String(localized: "Semaine chargée au travail")
        case .injury: String(localized: "Genou droit")
        case .preference: String(localized: "Séances le matin")
        default: ""
        }
    }

    @ViewBuilder private var suggestions: some View {
        let shown = Array(completer.suggestions.prefix(4))
        if !shown.isEmpty {
            VStack(spacing: 0) {
                ForEach(shown) { suggestion in
                    Button { select(suggestion) } label: {
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
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, SharpitSpacing.xs)
                        .contentShape(.rect)
                    }
                    .buttonStyle(.sharpitPressable)
                    if suggestion != shown.last { Divider() }
                }
            }
            .padding(.horizontal, SharpitSpacing.sm)
            .padding(.vertical, SharpitSpacing.xxs)
            .sharpitSurface(.panel)
        }
    }

    private func select(_ suggestion: LocationSuggestion) {
        isSelectingSuggestion = true
        draft.location = suggestion.displayName
        completer.clear()
        Task {
            await Task.yield()
            isSelectingSuggestion = false
        }
    }

    private var dates: some View {
        HStack(alignment: .top, spacing: SharpitSpacing.md) {
            dateField(String(localized: "Du"), selection: $draft.startDay)
                .onChange(of: draft.startDay) { _, newStart in
                    if draft.endDay < newStart { draft.endDay = newStart }
                }
            dateField(String(localized: "Au"), selection: $draft.endDay, from: draft.startDay)
        }
    }

    private func dateField(_ title: String, selection: Binding<Date>, from start: Date = .distantPast) -> some View {
        VStack(alignment: .leading, spacing: SharpitSpacing.xs) {
            SharpitFieldLabel(title)
            DatePicker(title, selection: selection, in: start..., displayedComponents: .date)
                .labelsHidden()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var training: some View {
        VStack(alignment: .leading, spacing: SharpitSpacing.sm) {
            SharpitFieldLabel(String(localized: "Entraînement"))
            SharpitSegmentedChoice(
                options: Array(TripTraining.Mode.allCases),
                label: \.label,
                selection: Binding(get: { draft.training.mode }, set: { if let mode = $0 { draft.training.mode = mode } })
            )
            if draft.training.mode == .normal {
                TripSportGrid(sports: $draft.training.sports)
            }
            Text(draft.training.outcome)
                .font(SharpitTypography.meta)
                .foregroundStyle(SharpitColor.mutedForeground)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var noteField: some View {
        VStack(alignment: .leading, spacing: SharpitSpacing.xs) {
            SharpitFieldLabel(String(localized: "Note pour le coach"))
            TextField(String(localized: "Hôtel avec petite salle…"), text: $draft.note, axis: .vertical)
                .font(SharpitTypography.body)
                .lineLimit(2...5)
                .padding(.vertical, SharpitSpacing.sm)
                .sharpitFieldWell()
        }
    }

    private var deleteButton: some View {
        Button("Supprimer", role: .destructive) { showingDeleteConfirmation = true }
            .font(SharpitTypography.bodyEmphasis)
            .tint(SharpitColor.destructive)
            .frame(maxWidth: .infinity, minHeight: SharpitSpacing.rowHeight)
    }

    private func save() async {
        isSaving = true
        failure = nil
        defer { isSaving = false }
        let input = draft.input()
        let saved = if let entry {
            await store.updateEntry(id: entry.id, input)
        } else {
            await store.createEntry(input)
        }
        if saved {
            dismiss()
        } else {
            failure = store.errorMessage
        }
    }
}

/// The five sports, side by side: on is the ink tile every sport wears elsewhere, off the same
/// glyph left on the plain well, so the row reads at a glance what can be done.
private struct TripSportGrid: View {
    @Binding var sports: Set<AllowedDiscipline>
    @ScaledMetric(relativeTo: .caption) private var minimumWidth: CGFloat = 58

    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: minimumWidth), spacing: SharpitSpacing.xs)], spacing: SharpitSpacing.sm) {
            ForEach(AllowedDiscipline.allCases) { sport in
                let isOn = sports.contains(sport)
                Button {
                    if isOn { sports.remove(sport) } else { sports.insert(sport) }
                } label: {
                    VStack(spacing: SharpitSpacing.xxs) {
                        tile(sport, isOn: isOn)
                        Text(sport.label)
                            .font(SharpitTypography.meta)
                            .foregroundStyle(isOn ? SharpitColor.foreground : SharpitColor.mutedForeground)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                    }
                    .frame(maxWidth: .infinity)
                    .contentShape(.rect)
                }
                .buttonStyle(.sharpitPressable)
                .accessibilityLabel(sport.label)
                .accessibilityAddTraits(isOn ? [.isButton, .isSelected] : .isButton)
            }
        }
    }

    @ViewBuilder private func tile(_ sport: AllowedDiscipline, isOn: Bool) -> some View {
        if isOn {
            SharpitIconTile(symbol: sport.symbol)
        } else {
            let side = SharpitTokens.tileSize
            Image(systemName: sport.symbol)
                .font(.system(size: side * 0.42, weight: .bold))
                .foregroundStyle(SharpitColor.mutedForeground)
                .frame(width: side, height: side)
                .background(SharpitColor.analysisSurfaceAlt, in: RoundedRectangle(cornerRadius: SharpitRadius.tile, style: .continuous))
                .accessibilityHidden(true)
        }
    }
}

/// One dated entry in a list: its tile, its name and days, a word when training changes, and
/// the sports left when they are narrowed. It opens the form.
struct CoachMemoryEntryRow: View {
    let entry: CoachMemoryEntry

    var body: some View {
        VStack(alignment: .leading, spacing: SharpitSpacing.xs) {
            SharpitCardHeader(title: entry.displayTitle, symbol: entry.type.symbol, subtitle: subtitle) {
                if entry.trainingConstraint != .full {
                    SharpitPill(entry.trainingConstraint.badgeText)
                }
            }
            if !sports.isEmpty {
                HStack(spacing: SharpitSpacing.sm) {
                    ForEach(sports) { sport in
                        Image(systemName: sport.symbol)
                            .font(SharpitTypography.meta)
                            .foregroundStyle(SharpitColor.mutedForeground)
                    }
                }
                .padding(.leading, SharpitTokens.tileSize + SharpitSpacing.sm)
                .accessibilityElement()
                .accessibilityLabel(sports.map(\.label).formatted(.list(type: .and).locale(AppLanguage.locale)))
            }
        }
        .padding(.vertical, SharpitSpacing.xxs)
    }

    private var subtitle: String? {
        entry.type.isOpenEnded ? entry.note : entry.formattedDateRange
    }

    private var sports: [AllowedDiscipline] {
        let listed = (entry.allowedDisciplines ?? []).compactMap(AllowedDiscipline.init(rawValue:))
        return listed.count < AllowedDiscipline.allCases.count ? listed : []
    }
}
