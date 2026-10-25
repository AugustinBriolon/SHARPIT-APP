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
/// onboarding and Paramètres › Sports & équipement so both read and answer the same.
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
            SharpitEyebrow(title)
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

    var body: some View {
        Button {
            SharpitMotion.run(SharpitMotion.selection) { onToggle() }
        } label: {
            VStack(alignment: .leading, spacing: SharpitSpacing.sm) {
                HStack(alignment: .top) {
                    item.image
                        .symbolVariant(isSelected ? .fill : .none)
                        .font(.system(size: 30, weight: .medium))
                        .foregroundStyle(isSelected ? SharpitColor.primary : SharpitColor.mutedForeground)
                        .frame(height: 36, alignment: .leading)
                    Spacer(minLength: 0)
                    Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(isSelected ? SharpitColor.primary : SharpitColor.mutedForeground.opacity(0.35))
                        .contentTransition(.symbolEffect(.replace))
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.label)
                        .font(SharpitTypography.cardTitle)
                        .tracking(SharpitTypography.cardTitleTracking)
                        .foregroundStyle(SharpitColor.foreground)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                    Text(item.subtitle)
                        .font(SharpitTypography.meta)
                        .foregroundStyle(SharpitColor.mutedForeground)
                        .lineLimit(2, reservesSpace: true)
                        .multilineTextAlignment(.leading)
                }
            }
            .padding(SharpitSpacing.md)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: SharpitRadius.panel, style: .continuous)
                    .fill(isSelected ? SharpitColor.primary.opacity(0.18) : SharpitColor.analysisSurface)
            )
            .overlay(
                RoundedRectangle(cornerRadius: SharpitRadius.panel, style: .continuous)
                    .strokeBorder(SharpitColor.primary, lineWidth: isSelected ? 2 : 0)
            )
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(item.label)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }
}

/// The kit the chosen sports use, one card per sport; strength asks where the athlete trains
/// before listing what they own. Shared by the onboarding and Paramètres.
struct EquipmentBySport: View {
    let sports: [EquipmentSport]
    let venue: V1AthleteEquipment.StrengthVenue
    let owned: Set<String>
    let onVenue: (V1AthleteEquipment.StrengthVenue) -> Void
    let onToggle: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: SharpitSpacing.md) {
            ForEach(sports) { sport in
                VStack(alignment: .leading, spacing: SharpitSpacing.md) {
                    SharpitCardHeader(title: sport.label, symbol: sport.symbolName, showsChevron: false)
                    if sport == .strength {
                        venuePicker
                    }
                    let items = EquipmentCatalog.items(for: sport, venue: venue)
                    if items.isEmpty {
                        Text("Rien de particulier pour ce type de renforcement.")
                            .font(SharpitTypography.meta)
                            .foregroundStyle(SharpitColor.mutedForeground)
                    } else {
                        VStack(spacing: 0) {
                            ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                                EquipmentChoiceRow(item: item, isOwned: owned.contains(item.id)) { onToggle(item.id) }
                                if index < items.count - 1 {
                                    Rectangle().fill(SharpitColor.analysisGrid).frame(height: 1)
                                        .padding(.leading, (sport != .strength && !item.symbolName.isEmpty) ? 44 : 0)
                                }
                            }
                        }
                    }
                }
                .padding(SharpitSpacing.cardPadding)
                .sharpitSurface(.panel)
            }
        }
    }

    private var venuePicker: some View {
        VStack(alignment: .leading, spacing: SharpitSpacing.xs) {
            LazyVGrid(
                columns: [GridItem(.flexible(), spacing: SharpitSpacing.xs), GridItem(.flexible(), spacing: SharpitSpacing.xs)],
                spacing: SharpitSpacing.xs
            ) {
                ForEach(V1AthleteEquipment.StrengthVenue.Toggle.allCases) { chip in
                    OnboardingChoiceChip(
                        title: chip.title,
                        symbol: chip.symbolName,
                        isSelected: venue.toggles.contains(chip)
                    ) {
                        SharpitHaptics.play(.notch(major: false))
                        SharpitMotion.run(SharpitMotion.selection) {
                            onVenue(V1AthleteEquipment.StrengthVenue.toggling(chip, in: venue))
                        }
                    }
                }
            }
            Text(venue.description)
                .font(SharpitTypography.meta)
                .foregroundStyle(SharpitColor.mutedForeground)
                .contentTransition(.opacity)
        }
    }
}

/// One piece of equipment: its glyph, what it changes for the coach, whether it is owned.
struct EquipmentChoiceRow: View {
    let item: EquipmentCatalogItem
    let isOwned: Bool
    let onToggle: () -> Void

    var body: some View {
        Button {
            SharpitMotion.run(SharpitMotion.selection) { onToggle() }
        } label: {
            HStack(spacing: SharpitSpacing.sm) {
                if item.sport != .strength && !item.symbolName.isEmpty {
                    Image(systemName: item.symbolName)
                        .font(.system(size: 17, weight: .medium))
                        .foregroundStyle(isOwned ? SharpitColor.primary : SharpitColor.mutedForeground)
                        .frame(width: 32)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.label)
                        .font(SharpitTypography.bodyEmphasis)
                        .foregroundStyle(SharpitColor.foreground)
                    Text(item.impact)
                        .font(SharpitTypography.meta)
                        .foregroundStyle(SharpitColor.mutedForeground)
                        .fixedSize(horizontal: false, vertical: true)
                        .multilineTextAlignment(.leading)
                }
                Spacer(minLength: 0)
                Image(systemName: isOwned ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(isOwned ? SharpitColor.primary : SharpitColor.mutedForeground.opacity(0.35))
                    .contentTransition(.symbolEffect(.replace))
            }
            .padding(.vertical, SharpitSpacing.sm)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isOwned ? [.isButton, .isSelected] : .isButton)
    }
}

/// Réglages › Sports & équipement: the sports practiced, one row each with what the athlete owns
/// for it, a sport's page for its kit and a « + » for the sports not yet added. Saved as it
/// changes (`docs/adr/0014`); the onboarding keeps its tiles.
struct EquipmentView: View {
    @State private var store: AthleteProfileStore
    @State private var practicedSports: Set<String> = []
    @State private var strengthVenue: V1AthleteEquipment.StrengthVenue = .bodyweight
    @State private var owned: Set<String> = []
    @State private var hasLoaded = false
    @State private var autoSaveTask: Task<Void, Never>?
    @State private var showingAdd = false

    init(
        client: any AthleteProfileServing,
        tokenProvider: @escaping () async throws -> String,
        modelContext: ModelContext? = nil
    ) {
        _store = State(initialValue: AthleteProfileStore(
            client: client,
            tokenProvider: tokenProvider,
            modelContext: modelContext
        ))
    }

    private var hasEndurance: Bool { PracticedSportCatalog.hasEnduranceSport(practicedSports) }

    private var practicedItems: [PracticedSportItem] {
        PracticedSportCatalog.all.filter { practicedSports.contains($0.id) }
    }

    var body: some View {
        List {
            Section {
                if practicedItems.isEmpty {
                    Text("Aucun sport pour l'instant. Ajoute-en un avec le +.")
                        .font(SharpitTypography.meta)
                        .foregroundStyle(SharpitColor.mutedForeground)
                }
                ForEach(practicedItems) { item in
                    NavigationLink {
                        SportEquipmentView(
                            sport: item,
                            venue: $strengthVenue,
                            owned: $owned,
                            canRemove: SportsReadout.canRemove(item.id, from: practicedSports),
                            onChange: scheduleAutoSave,
                            onRemove: { removeSport(item.id) }
                        )
                    } label: {
                        SportRowLabel(
                            item: item,
                            detail: SportsReadout.equipmentSummary(sportId: item.id, owned: owned, venue: strengthVenue)
                        )
                    }
                }
            } header: {
                SharpitEyebrow(String(localized: "Mes sports"))
            } footer: {
                footer
            }
            .sharpitListRows()
        }
        .sharpitGroupedList()
        .disabled(!hasLoaded)
        .redacted(reason: hasLoaded ? [] : .placeholder)
        .navigationTitle("Sports & équipement")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { showingAdd = true } label: { Image(systemName: "plus") }
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
        .task {
            await store.load()
            syncFromProfile()
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

    private func addSport(_ id: String) {
        practicedSports.insert(id)
        scheduleAutoSave()
    }

    private func removeSport(_ id: String) {
        guard SportsReadout.canRemove(id, from: practicedSports) else { return }
        practicedSports.remove(id)
        scheduleAutoSave()
    }

    private func syncFromProfile() {
        guard !hasLoaded, store.phase == .loaded else { return }
        practicedSports = Set(store.profile.practicedSports?.sports ?? [])
        if let equipment = store.profile.equipment {
            strengthVenue = equipment.strengthVenue.flatMap(V1AthleteEquipment.StrengthVenue.init(rawValue:)) ?? .bodyweight
            owned = Set(equipment.owned)
        }
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

/// One practiced sport as a settings row: its glyph in the ink tile, its name, what is owned.
struct SportRowLabel: View {
    let item: PracticedSportItem
    let detail: String

    var body: some View {
        Label {
            VStack(alignment: .leading, spacing: 1) {
                Text(item.label)
                    .font(SharpitTypography.bodyEmphasis)
                    .foregroundStyle(SharpitColor.foreground)
                Text(detail)
                    .font(SharpitTypography.meta)
                    .foregroundStyle(SharpitColor.mutedForeground)
                    .lineLimit(1)
            }
        } icon: {
            item.image
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(SharpitColor.inkAccent)
                .frame(width: 32, height: 32)
                .sharpitConcentricBackground(SharpitColor.inkSurface, minimum: SharpitRadius.tile * 32 / SharpitTokens.tileSize)
                .accessibilityHidden(true)
        }
    }
}

/// A sport's page: the kit it uses (strength asks where the athlete trains first) and the way to
/// take the sport out of the plan.
struct SportEquipmentView: View {
    let sport: PracticedSportItem
    @Binding var venue: V1AthleteEquipment.StrengthVenue
    @Binding var owned: Set<String>
    let canRemove: Bool
    let onChange: () -> Void
    let onRemove: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var confirmingRemoval = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: SharpitSpacing.xl) {
                EquipmentBySport(
                    sports: PracticedSportCatalog.equipmentSports(for: [sport.id]),
                    venue: venue,
                    owned: owned,
                    onVenue: { venue = $0; onChange() },
                    onToggle: toggle
                )
                VStack(alignment: .leading, spacing: SharpitSpacing.xs) {
                    SharpitPrimaryButton(title: String(localized: "Retirer \(sport.label)"), style: .secondary) {
                        confirmingRemoval = true
                    }
                    .disabled(!canRemove)
                    if !canRemove {
                        Text("C'est ton dernier sport d'endurance : ajoute-en un autre avant de le retirer.")
                            .font(SharpitTypography.meta)
                            .foregroundStyle(SharpitColor.mutedForeground)
                    }
                }
            }
            .padding(.horizontal, SharpitSpacing.pageInset)
            .padding(.vertical, SharpitSpacing.md)
        }
        .background(SharpitCanvasBackground())
        .navigationTitle(sport.label)
        .navigationBarTitleDisplayMode(.inline)
        .confirmationDialog("Retirer \(sport.label) ?", isPresented: $confirmingRemoval, titleVisibility: .visible) {
            Button("Retirer \(sport.label)", role: .destructive) {
                onRemove()
                dismiss()
            }
            Button("Annuler", role: .cancel) {}
        } message: {
            Text("Tes plans ne s'appuieront plus sur ce sport. Ton matériel reste enregistré.")
        }
    }

    private func toggle(_ id: String) {
        if owned.contains(id) { owned.remove(id) } else { owned.insert(id) }
        onChange()
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
                                            .foregroundStyle(SharpitColor.mutedForeground)
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
