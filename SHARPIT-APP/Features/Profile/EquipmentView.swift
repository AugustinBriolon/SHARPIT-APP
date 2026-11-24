import SwiftData
import SwiftUI

struct PracticedSportItem: Identifiable, Sendable {
    let id: String
    let label: String
    let subtitle: String
    let symbolName: String

    var image: Image { Image(sharpitSymbol: symbolName) }
}

enum PracticedSportCatalog {
    static let endurance: [PracticedSportItem] = [
        PracticedSportItem(id: "run", label: String(localized: "Course à pied"), subtitle: String(localized: "Route, trail et piste"), symbolName: "figure.run"),
        PracticedSportItem(id: "bike", label: String(localized: "Cyclisme / Vélo"), subtitle: String(localized: "Route, gravel et home-trainer"), symbolName: "bicycle"),
        PracticedSportItem(id: "swim", label: String(localized: "Natation"), subtitle: String(localized: "Bassin et eau libre"), symbolName: "figure.pool.swim"),
        PracticedSportItem(id: "triathlon", label: String(localized: "Triathlon"), subtitle: String(localized: "Enchaînements multi-disciplines"), symbolName: SharpitCustomSymbol.triathlon)
    ]

    static let complementary: [PracticedSportItem] = [
        PracticedSportItem(id: "strength", label: String(localized: "Musculation"), subtitle: String(localized: "Force, PPG et gainage"), symbolName: "figure.strengthtraining.traditional"),
        PracticedSportItem(id: "mobility", label: String(localized: "Mobilité"), subtitle: String(localized: "Amplitude articulaire"), symbolName: "figure.yoga"),
        PracticedSportItem(id: "stretching", label: String(localized: "Étirements"), subtitle: String(localized: "Souplesse et récupération"), symbolName: "figure.cooldown")
    ]

    /// Catalog order — the order the web stores (`uniqueOrdered` in `practiced-sports/catalog.ts`).
    static let all: [PracticedSportItem] = endurance + complementary

    static func hasEnduranceSport(_ sports: some Collection<String>) -> Bool {
        endurance.contains { sports.contains($0.id) }
    }

    /// What a plan can be built on: an endurance sport, or strength alone (SHARPIT ADR-086).
    /// Mobility or stretching alone is not a programme.
    static func isPlannable(_ sports: some Collection<String>) -> Bool {
        hasEnduranceSport(sports) || sports.contains("strength")
    }

    /// Strength without endurance: no race, no thresholds.
    static func isStrengthOnly(_ sports: some Collection<String>) -> Bool {
        !hasEnduranceSport(sports) && sports.contains("strength")
    }

    /// Known ids only, deduplicated, in catalog order.
    static func ordered(_ sports: some Collection<String>) -> [String] {
        all.map(\.id).filter { sports.contains($0) }
    }

    /// The inventory tabs a selection opens — triathlon counts for its three legs, stretching
    /// shares the mobility kit. Nothing selected shows every tab rather than none.
    static func equipmentSports(for sports: Set<String>) -> [EquipmentSport] {
        guard !sports.isEmpty else { return EquipmentSport.allCases }
        return EquipmentSport.allCases.filter { sport in
            switch sport {
            case .run: sports.contains("run") || sports.contains("triathlon")
            case .bike: sports.contains("bike") || sports.contains("triathlon")
            case .swim: sports.contains("swim") || sports.contains("triathlon")
            case .strength: sports.contains("strength")
            case .mobility: sports.contains("mobility") || sports.contains("stretching")
            }
        }
    }
}

/// The practiced sports, endurance first, complements after — one grid of tiles, shared by the
/// onboarding and Paramètres › Matériel so both read and answer the same.
struct SportChoiceGroups: View {
    let selected: Set<String>
    let onToggle: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: SharpitSpacing.lg) {
            group(title: String(localized: "Endurance"), items: PracticedSportCatalog.endurance)
            group(title: String(localized: "En complément"), items: PracticedSportCatalog.complementary)
        }
    }

    private func group(title: String, items: [PracticedSportItem]) -> some View {
        VStack(alignment: .leading, spacing: SharpitSpacing.sm) {
            Text(title)
                .font(SharpitTypography.system(size: 14, weight: .regular, relativeTo: .footnote))
                .foregroundStyle(SharpitColor.slate)
            LazyVGrid(
                columns: [GridItem(.flexible(), spacing: SharpitSpacing.sm), GridItem(.flexible(), spacing: SharpitSpacing.sm)],
                spacing: SharpitSpacing.sm
            ) {
                ForEach(items) { item in
                    SportChoiceTile(item: item, isSelected: selected.contains(item.id)) { onToggle(item.id) }
                }
            }
        }
    }
}

/// One practiced sport as a tile. It answers the touch by filling, never by moving.
struct SportChoiceTile: View {
    let item: PracticedSportItem
    let isSelected: Bool
    let onToggle: () -> Void

    /// A sport's glyph takes a data hue, so the grid reads at a glance; the choice is the ink
    /// border and its check, never a fill.
    private var hue: Color {
        switch item.id {
        case "run": SharpitColor.pillarNutrition
        case "bike": SharpitColor.pillarRecovery
        case "swim": SharpitColor.pillarSleep
        default: SharpitColor.pillarCoach
        }
    }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 20, style: .continuous)
        return Button {
            SharpitMotion.run(SharpitMotion.selection) { onToggle() }
        } label: {
            VStack(alignment: .leading, spacing: 18) {
                HStack(alignment: .top) {
                    item.image
                        .font(.system(size: 24, weight: .regular))
                        .foregroundStyle(hue)
                        .frame(height: 30, alignment: .leading)
                    Spacer(minLength: 0)
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 22, weight: .regular))
                        .foregroundStyle(SharpitColor.foreground)
                        .opacity(isSelected ? 1 : 0)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.label)
                        .font(SharpitTypography.system(size: 17, weight: .semibold, relativeTo: .body))
                        .foregroundStyle(SharpitColor.foreground)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                    Text(item.subtitle)
                        .font(SharpitTypography.system(size: 13, weight: .regular, relativeTo: .footnote))
                        .foregroundStyle(SharpitColor.slate)
                        .lineLimit(2, reservesSpace: true)
                        .multilineTextAlignment(.leading)
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(SharpitColor.card, in: shape)
            .overlay(shape.strokeBorder(isSelected ? SharpitColor.foreground : SharpitColor.divider, lineWidth: isSelected ? 2 : 1))
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(item.label)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }
}

/// The kit the chosen sports use, one section per sport, its lines split by hairlines; strength
/// asks where the athlete trains before listing what they own. Shared by the onboarding and Matériel.
struct EquipmentBySport: View {
    let sports: [EquipmentSport]
    let venue: V1AthleteEquipment.StrengthVenue
    let owned: Set<String>
    let onVenue: (V1AthleteEquipment.StrengthVenue) -> Void
    let onToggle: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 28) {
            ForEach(sports) { sport in
                VStack(alignment: .leading, spacing: SharpitSpacing.xs) {
                    Text(sport.label)
                        .font(SharpitTypography.sectionTitle)
                        .foregroundStyle(SharpitColor.foreground)
                        .accessibilityAddTraits(.isHeader)
                    if sport == .strength {
                        venuePicker
                    }
                    let items = EquipmentCatalog.items(for: sport, venue: venue)
                    if items.isEmpty {
                        Text("Rien de particulier pour ce type de renforcement.")
                            .font(SharpitTypography.meta)
                            .foregroundStyle(SharpitColor.slate)
                    } else {
                        VStack(spacing: 0) {
                            ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                                EquipmentChoiceRow(item: item, isOwned: owned.contains(item.id)) { onToggle(item.id) }
                                if index < items.count - 1 {
                                    CliniqueDivider()
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    /// Where the athlete lifts, as two switches. No third choice for « poids du corps »: it is
    /// what is left when neither is on, and it stays possible with both (the athlete's remark,
    /// 2026-11-24: the three chips read as if a gym ruled bodyweight work out).
    private var venuePicker: some View {
        VStack(spacing: 0) {
            EquipmentLine(
                title: String(localized: "Accès à une salle"),
                detail: String(localized: "Machines, racks et câbles : rien à lister."),
                isOn: venue.hasGym,
                onChange: { onVenue(.training(inGym: $0, atHome: venue.hasHome)) }
            ) { EquipmentTile(symbol: "dumbbell") }
            CliniqueDivider()
            EquipmentLine(
                title: String(localized: "Entraînement à la maison"),
                detail: String(localized: "Indique plus bas ce que tu as chez toi."),
                isOn: venue.hasHome,
                onChange: { onVenue(.training(inGym: venue.hasGym, atHome: $0)) }
            ) { EquipmentTile(symbol: "house") }
            CliniqueDivider()
            if venue == .bodyweight {
                Text("Sans salle ni matériel, tes séances se font au poids du corps.")
                    .font(SharpitTypography.meta)
                    .foregroundStyle(SharpitColor.slate)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 14)
                    .transition(.opacity)
            }
        }
    }
}

/// One piece of equipment as a line: its drawing, what it is, what it changes for the coach, and
/// a switch that says whether it is owned.
struct EquipmentChoiceRow: View {
    let item: EquipmentCatalogItem
    let isOwned: Bool
    let onToggle: () -> Void

    var body: some View {
        EquipmentLine(title: item.label, detail: item.impact, isOn: isOwned, onChange: { _ in onToggle() }) {
            EquipmentTile(imageName: item.imageName, symbol: item.symbolName)
        }
    }
}

/// A line of the kit: a tile, a name, what it changes, and the system's switch (the athlete's
/// call, 2026-11-24, over the words « Oui » / « Non »).
private struct EquipmentLine<Tile: View>: View {
    let title: String
    let detail: String
    let isOn: Bool
    let onChange: (Bool) -> Void
    @ViewBuilder let tile: Tile

    var body: some View {
        Toggle(isOn: Binding(get: { isOn }, set: { value in SharpitMotion.run(SharpitMotion.selection) { onChange(value) } })) {
            HStack(alignment: .center, spacing: SharpitSpacing.sm) {
                tile
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(SharpitTypography.system(size: 16, weight: .regular, relativeTo: .callout))
                        .foregroundStyle(SharpitColor.foreground)
                    Text(detail)
                        .font(SharpitTypography.meta)
                        .foregroundStyle(SharpitColor.slate)
                        .fixedSize(horizontal: false, vertical: true)
                        .multilineTextAlignment(.leading)
                }
            }
        }
        .padding(.vertical, 14)
    }
}

/// A line's tile: the item's drawing, or a glyph on the neutral tile where there is none.
private struct EquipmentTile: View {
    var imageName: String?
    let symbol: String

    @ScaledMetric(relativeTo: .callout) private var side: CGFloat = 60
    @Environment(\.colorScheme) private var colorScheme
    private static let shape = RoundedRectangle(cornerRadius: 16, style: .continuous)

    var body: some View {
        Group {
            if let drawing = imageName.flatMap(UIImage.init(named:)) {
                Image(uiImage: drawing)
                    .resizable()
                    .scaledToFill()
                    // The drawings are opaque, on white: the tile is their paper in both appearances,
                    // softened in the dark so it does not glow (HIG, Dark Mode).
                    .background(Color.white)
                    .colorMultiply(colorScheme == .dark ? Color(white: 0.82) : .white)
            } else {
                Image(systemName: symbol)
                    .font(.system(size: 22, weight: .regular))
                    .foregroundStyle(SharpitColor.foreground)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(SharpitColor.tile)
            }
        }
        .frame(width: side, height: side)
        .clipShape(Self.shape)
        .overlay { Self.shape.strokeBorder(SharpitColor.divider, lineWidth: 1) }
        .accessibilityHidden(true)
    }
}

/// Réglages › Matériel: one page — the sports practiced, each a line with what the athlete owns
/// for it, then the kit by sport, a line a tap flips. « Ajouter » adds a sport. Saved as it
/// changes (`docs/adr/0014`); the onboarding keeps its tiles.
struct EquipmentView: View {
    @State private var store: AthleteProfileStore
    @State private var practicedSports: Set<String> = []
    @State private var strengthVenue: V1AthleteEquipment.StrengthVenue = .bodyweight
    @State private var owned: Set<String> = []
    @State private var hasLoaded = false
    @State private var autoSaveTask: Task<Void, Never>?
    @State private var showingAdd = false
    @State private var removing: PracticedSportItem?

    init(
        client: any AthleteProfileServing,
        tokenProvider: @escaping () async throws -> String,
        modelContext: ModelContext? = nil
    ) {
        let store = AthleteProfileStore(
            client: client,
            tokenProvider: tokenProvider,
            modelContext: modelContext
        )
        _store = State(initialValue: store)
        // A profile kept on the iPhone fills the page at once: no redacted frame on a revisit.
        guard let kept = store.keptProfile() else { return }
        let kit = Kit(kept)
        _practicedSports = State(initialValue: kit.sports)
        _strengthVenue = State(initialValue: kit.venue)
        _owned = State(initialValue: kit.owned)
        _hasLoaded = State(initialValue: true)
    }

    /// What the page edits, as the profile holds it.
    private struct Kit {
        let sports: Set<String>
        let venue: V1AthleteEquipment.StrengthVenue
        let owned: Set<String>

        init(_ profile: V1AthleteProfile) {
            sports = Set(profile.practicedSports?.sports ?? [])
            venue = profile.equipment?.strengthVenue.flatMap(V1AthleteEquipment.StrengthVenue.init(rawValue:)) ?? .bodyweight
            owned = Set(profile.equipment?.owned ?? [])
        }
    }

    private var hasEndurance: Bool { PracticedSportCatalog.hasEnduranceSport(practicedSports) }

    private var practicedItems: [PracticedSportItem] {
        PracticedSportCatalog.all.filter { practicedSports.contains($0.id) }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                Text("Matériel")
                    .font(SharpitTypography.system(size: 32, weight: .semibold, relativeTo: .largeTitle))
                    .tracking(-0.6)
                    .foregroundStyle(SharpitColor.foreground)
                    .accessibilityAddTraits(.isHeader)
                sportsSection
                EquipmentBySport(
                    sports: PracticedSportCatalog.equipmentSports(for: practicedSports),
                    venue: strengthVenue,
                    owned: owned,
                    onVenue: { strengthVenue = $0; scheduleAutoSave() },
                    onToggle: toggle
                )
            }
            .padding(.horizontal, 24)
            .padding(.top, SharpitSpacing.xs)
            .padding(.bottom, 96)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .cliniqueSheet(wash: .neutral, height: 240)
        .disabled(!hasLoaded)
        .redacted(reason: hasLoaded ? [] : .placeholder)
        .navigationTitle("Matériel")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) { Text("") }
            ToolbarItem(placement: .primaryAction) {
                Button("Ajouter") { showingAdd = true }
                    .accessibilityLabel("Ajouter un sport")
                    .disabled(!hasLoaded)
            }
        }
        .sheet(isPresented: $showingAdd) {
            SportAddSheet(sports: SportsReadout.addable(to: practicedSports)) { id in
                showingAdd = false
                addSport(id)
            }
        }
        .confirmationDialog(
            "Retirer \(removing?.label ?? "") ?",
            isPresented: Binding(get: { removing != nil }, set: { if !$0 { removing = nil } }),
            titleVisibility: .visible,
            presenting: removing
        ) { item in
            Button("Retirer \(item.label)", role: .destructive) { removeSport(item.id) }
            Button("Annuler", role: .cancel) {}
        } message: { _ in
            Text("Tes plans ne s'appuieront plus sur ce sport. Ton matériel reste enregistré.")
        }
        .task {
            await store.load()
            syncFromProfile()
        }
    }

    /// The sports practiced, each a line: its glyph, its name, what is owned for it, and the way
    /// to take it out of the plan — closed for the last sport a plan can stand on.
    private var sportsSection: some View {
        VStack(alignment: .leading, spacing: SharpitSpacing.xs) {
            Text("Mes sports")
                .font(SharpitTypography.sectionTitle)
                .foregroundStyle(SharpitColor.foreground)
                .accessibilityAddTraits(.isHeader)
            if practicedItems.isEmpty {
                Text("Aucun sport pour l'instant. Ajoute-en un.")
                    .font(SharpitTypography.meta)
                    .foregroundStyle(SharpitColor.slate)
            }
            VStack(spacing: 0) {
                ForEach(Array(practicedItems.enumerated()), id: \.element.id) { index, item in
                    HStack(spacing: SharpitSpacing.sm) {
                        SportRowLabel(
                            item: item,
                            detail: SportsReadout.equipmentSummary(sportId: item.id, owned: owned, venue: strengthVenue)
                        )
                        Spacer(minLength: SharpitSpacing.xs)
                        Menu {
                            Button("Retirer \(item.label)", role: .destructive) { removing = item }
                                .disabled(!SportsReadout.canRemove(item.id, from: practicedSports))
                        } label: {
                            Image(systemName: "ellipsis")
                                .font(.system(size: 17, weight: .regular))
                                .foregroundStyle(SharpitColor.slate)
                                .frame(width: 44, height: 44)
                                .contentShape(.rect)
                        }
                        .accessibilityLabel("Options pour \(item.label)")
                    }
                    .padding(.vertical, 6)
                    if index < practicedItems.count - 1 {
                        CliniqueDivider()
                    }
                }
            }
            footer
        }
    }

    @ViewBuilder
    private var footer: some View {
        if !hasEndurance {
            Label("Garde au moins un sport d'endurance : SharpIt construit tes plans dessus.", systemImage: "exclamationmark.circle")
                .font(SharpitTypography.meta)
                .foregroundStyle(SharpitColor.signalCaution)
        }
    }

    private func toggle(_ id: String) {
        if owned.contains(id) { owned.remove(id) } else { owned.insert(id) }
        scheduleAutoSave()
    }

    private func addSport(_ id: String) {
        practicedSports.insert(id)
        scheduleAutoSave()
    }

    private func removeSport(_ id: String) {
        guard SportsReadout.canRemove(id, from: practicedSports) else { return }
        practicedSports.remove(id)
        scheduleAutoSave()
    }

    /// Takes the profile just read, unless the athlete already changed something here: the
    /// kept profile shown on arrival gives way to the server's, never an edit in hand.
    private func syncFromProfile() {
        guard store.phase == .loaded, autoSaveTask == nil else { return }
        let kit = Kit(store.profile)
        practicedSports = kit.sports
        strengthVenue = kit.venue
        owned = kit.owned
        hasLoaded = true
    }

    private func scheduleAutoSave() {
        guard hasLoaded else { return }
        autoSaveTask?.cancel()
        autoSaveTask = Task {
            try? await Task.sleep(for: .milliseconds(350))
            guard !Task.isCancelled else { return }
            save()
        }
    }

    private func save() {
        var patch = AthleteProfilePatch()
        // Without an endurance sport the selection is not one SharpIt can plan on: the sports
        // wait until one is back, the equipment saves as it changes.
        if hasEndurance {
            patch.setPracticedSports(V1AthletePracticedSports(
                version: 1,
                sports: PracticedSportCatalog.ordered(practicedSports)
            ))
        }
        patch.setEquipment(V1AthleteEquipment(
            version: 1,
            strengthVenue: strengthVenue.rawValue,
            owned: Array(owned).sorted()
        ))
        store.save(patch)
    }
}

/// One practiced sport as a line: its glyph in the round neutral tile, its name, what is owned.
struct SportRowLabel: View {
    let item: PracticedSportItem
    let detail: String

    var body: some View {
        HStack(spacing: SharpitSpacing.sm) {
            item.image
                .font(.system(size: 15, weight: .regular))
                .foregroundStyle(SharpitColor.foreground)
                .frame(width: 36, height: 36)
                .background(SharpitColor.tile, in: Circle())
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(item.label)
                    .font(SharpitTypography.system(size: 16, weight: .regular, relativeTo: .callout))
                    .foregroundStyle(SharpitColor.foreground)
                Text(detail)
                    .font(SharpitTypography.meta)
                    .foregroundStyle(SharpitColor.slate)
                    .lineLimit(1)
            }
        }
    }
}

/// The « + » sheet: the sports not yet practiced, each added with a tap.
struct SportAddSheet: View {
    let sports: [PracticedSportItem]
    let onAdd: (String) -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Group {
                if sports.isEmpty {
                    ContentUnavailableView(
                        String(localized: "Tous les sports sont ajoutés"),
                        systemImage: "checkmark.circle",
                        description: Text("Tu pratiques déjà tous les sports que SharpIt connaît.")
                    )
                } else {
                    List {
                        Section {
                            ForEach(sports) { item in
                                Button { onAdd(item.id) } label: {
                                    HStack {
                                        SportRowLabel(item: item, detail: item.subtitle)
                                        Spacer(minLength: SharpitSpacing.xs)
                                        Image(systemName: "plus.circle")
                                            .foregroundStyle(SharpitColor.slate)
                                            .accessibilityHidden(true)
                                    }
                                    .contentShape(.rect)
                                }
                                .accessibilityHint("Ajouter \(item.label)")
                            }
                        }
                        .sharpitListRows()
                    }
                    .sharpitGroupedList()
                }
            }
            .navigationTitle("Ajouter un sport")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Fermer") { dismiss() }
                }
            }
        }
        .sharpitSheet()
    }
}
