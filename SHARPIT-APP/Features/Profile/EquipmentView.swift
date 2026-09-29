import SwiftData
import SwiftUI

struct PracticedSportItem: Identifiable, Sendable {
    let id: String
    let label: String
    let subtitle: String
    let symbolName: String
    /// SF Symbols draws no triathlon: that one is the app's own symbol, in the asset catalog.
    var isCustomSymbol = false

    var image: Image {
        isCustomSymbol ? Image(symbolName) : Image(systemName: symbolName)
    }
}

enum PracticedSportCatalog {
    static let endurance: [PracticedSportItem] = [
        PracticedSportItem(id: "run", label: "Course à pied", subtitle: "Route, trail et piste", symbolName: "figure.run"),
        PracticedSportItem(id: "bike", label: "Cyclisme / Vélo", subtitle: "Route, gravel et home-trainer", symbolName: "bicycle"),
        PracticedSportItem(id: "swim", label: "Natation", subtitle: "Bassin et eau libre", symbolName: "figure.pool.swim"),
        PracticedSportItem(id: "triathlon", label: "Triathlon", subtitle: "Enchaînements multi-disciplines", symbolName: "triathlon.circles", isCustomSymbol: true)
    ]

    static let complementary: [PracticedSportItem] = [
        PracticedSportItem(id: "strength", label: "Musculation", subtitle: "Force, PPG et gainage", symbolName: "figure.strengthtraining.traditional"),
        PracticedSportItem(id: "mobility", label: "Mobilité", subtitle: "Amplitude articulaire", symbolName: "figure.yoga"),
        PracticedSportItem(id: "stretching", label: "Étirements", subtitle: "Souplesse et récupération", symbolName: "figure.cooldown")
    ]

    /// Catalog order — the order the web stores (`uniqueOrdered` in `practiced-sports/catalog.ts`).
    static let all: [PracticedSportItem] = endurance + complementary

    /// SHARPIT is built for endurance: a selection needs at least one of these.
    static func hasEnduranceSport(_ sports: some Collection<String>) -> Bool {
        endurance.contains { sports.contains($0.id) }
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
            group(title: "Endurance", items: PracticedSportCatalog.endurance)
            group(title: "En complément", items: PracticedSportCatalog.complementary)
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
            SharpitHaptics.play(.soft)
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
                                    Rectangle().fill(SharpitColor.analysisGrid).frame(height: 1).padding(.leading, 44)
                                }
                            }
                        }
                    }
                }
                .padding(SharpitSpacing.cardPadding)
                .sharpitSurface(.panel)
                .sharpitCardSpecularBorder()
            }
        }
    }

    private var venuePicker: some View {
        VStack(alignment: .leading, spacing: SharpitSpacing.xs) {
            LazyVGrid(
                columns: [GridItem(.flexible(), spacing: SharpitSpacing.xs), GridItem(.flexible(), spacing: SharpitSpacing.xs)],
                spacing: SharpitSpacing.xs
            ) {
                ForEach(V1AthleteEquipment.StrengthVenue.allCases) { choice in
                    OnboardingChoiceChip(title: choice.title, symbol: choice.symbolName, isSelected: venue == choice) {
                        SharpitMotion.run(SharpitMotion.selection) { onVenue(choice) }
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
            SharpitHaptics.play(.soft)
            SharpitMotion.run(SharpitMotion.selection) { onToggle() }
        } label: {
            HStack(spacing: SharpitSpacing.sm) {
                Image(systemName: item.symbolName)
                    .font(.system(size: 17, weight: .medium))
                    .foregroundStyle(isOwned ? SharpitColor.primary : SharpitColor.mutedForeground)
                    .frame(width: 32)
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

/// Réglages › Sports & équipement: the onboarding's own tiles and cards, saved as they change.
struct EquipmentView: View {
    @State private var store: AthleteProfileStore
    @Environment(SharpitToastCenter.self) private var toastCenter: SharpitToastCenter?
    @State private var practicedSports: Set<String> = []
    @State private var strengthVenue: V1AthleteEquipment.StrengthVenue = .bodyweight
    @State private var owned: Set<String> = []
    @State private var hasLoaded = false
    @State private var autoSaveTask: Task<Void, Never>?

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

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: SharpitSpacing.xl) {
                VStack(alignment: .leading, spacing: SharpitSpacing.sm) {
                    SportChoiceGroups(selected: practicedSports, onToggle: toggleSport)
                    if !hasEndurance {
                        Label("Garde au moins un sport d'endurance : SharpIt construit tes plans dessus.", systemImage: "exclamationmark.circle")
                            .font(SharpitTypography.meta)
                            .foregroundStyle(SharpitColor.signalCaution)
                    }
                }
                VStack(alignment: .leading, spacing: SharpitSpacing.sm) {
                    SharpitEyebrow("Matériel")
                    Text("Le coach adapte les séances à ce que tu possèdes.")
                        .font(SharpitTypography.meta)
                        .foregroundStyle(SharpitColor.mutedForeground)
                    EquipmentBySport(
                        sports: PracticedSportCatalog.equipmentSports(for: practicedSports),
                        venue: strengthVenue,
                        owned: owned,
                        onVenue: { strengthVenue = $0; scheduleAutoSave() },
                        onToggle: toggleEquipment
                    )
                }
            }
            .padding(.horizontal, SharpitSpacing.pageInset)
            .padding(.vertical, SharpitSpacing.md)
            .disabled(!hasLoaded)
            .redacted(reason: hasLoaded ? [] : .placeholder)
        }
        .background(SharpitCanvasBackground())
        .navigationTitle("Sports & équipement")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                if store.isSaving {
                    ProgressView().controlSize(.small)
                }
            }
        }
        .task {
            await store.load()
            syncFromProfile()
        }
    }

    private func toggleSport(_ id: String) {
        if practicedSports.contains(id) { practicedSports.remove(id) } else { practicedSports.insert(id) }
        scheduleAutoSave()
    }

    private func toggleEquipment(_ id: String) {
        if owned.contains(id) { owned.remove(id) } else { owned.insert(id) }
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
            await save()
        }
    }

    private func save() async {
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
        if await store.save(patch) == false, let error = store.saveError {
            toastCenter?.show(error, symbol: "exclamationmark.triangle.fill", tone: .error)
        }
    }
}
