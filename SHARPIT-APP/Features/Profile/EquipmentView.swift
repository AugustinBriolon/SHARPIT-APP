import SwiftData
import SwiftUI

struct PracticedSportItem: Identifiable, Sendable {
    let id: String
    let label: String
    let subtitle: String
    let symbolName: String
}

enum PracticedSportCatalog {
    static let endurance: [PracticedSportItem] = [
        PracticedSportItem(id: "run", label: "Course à pied", subtitle: "Route, trail et piste", symbolName: "figure.run"),
        PracticedSportItem(id: "bike", label: "Cyclisme / Vélo", subtitle: "Route, gravel et home-trainer", symbolName: "bicycle"),
        PracticedSportItem(id: "swim", label: "Natation", subtitle: "Bassin et eau libre", symbolName: "figure.pool.swim"),
        PracticedSportItem(id: "triathlon", label: "Triathlon", subtitle: "Enchaînements multi-disciplines", symbolName: "figure.cross.training")
    ]

    static let complementary: [PracticedSportItem] = [
        PracticedSportItem(id: "strength", label: "Musculation", subtitle: "Force, PPG et gainage", symbolName: "figure.strengthtraining.traditional"),
        PracticedSportItem(id: "mobility", label: "Mobilité", subtitle: "Amplitude articulaire", symbolName: "figure.yoga"),
        PracticedSportItem(id: "stretching", label: "Étirements", subtitle: "Souplesse et récupération", symbolName: "figure.cooldown")
    ]
}

/// Réglages → Sports & équipement: modern, tactile practiced sports & equipment manager.
struct EquipmentView: View {
    @State private var store: AthleteProfileStore
    @Environment(SharpitToastCenter.self) private var toastCenter: SharpitToastCenter?
    @State private var practicedSports: Set<String> = ["run", "bike", "swim", "strength"]
    @State private var strengthVenue: V1AthleteEquipment.StrengthVenue? = .bodyweight
    @State private var owned: Set<String> = []
    @State private var selectedSportTab: EquipmentSport = .run
    @State private var hasLoaded = false
    @State private var autoSaveTask: Task<Void, Never>?

    private let columns = [
        GridItem(.flexible(), spacing: SharpitSpacing.sm),
        GridItem(.flexible(), spacing: SharpitSpacing.sm)
    ]

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

    var body: some View {
        ScrollView {
            VStack(spacing: SharpitSpacing.lg) {
                practicedSportsSection(
                    title: "Sports d'endurance",
                    caption: "Oriente les objectifs et les plans d'entraînement.",
                    items: PracticedSportCatalog.endurance
                )

                practicedSportsSection(
                    title: "Pratiques complémentaires",
                    caption: "Pour le renforcement, la mobilité et la prévention.",
                    items: PracticedSportCatalog.complementary
                )

                equipmentInventorySection
            }
            .padding(.horizontal, SharpitSpacing.pageInset)
            .padding(.vertical, SharpitSpacing.md)
        }
        .background(SharpitCanvasBackground())
        .navigationTitle("Sports & équipement")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                if store.isSaving {
                    ProgressView()
                        .controlSize(.small)
                }
            }
        }
        .task {
            await store.load()
            syncFromProfile()
        }
        .onChange(of: store.profile) { _, _ in
            if !hasLoaded {
                syncFromProfile()
            }
        }
    }

    // MARK: - Practiced Sports Bento Grid

    private func practicedSportsSection(
        title: String,
        caption: String,
        items: [PracticedSportItem]
    ) -> some View {
        VStack(alignment: .leading, spacing: SharpitSpacing.sm) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(SharpitTypography.sectionTitle)
                    .foregroundStyle(SharpitColor.foreground)

                Text(caption)
                    .font(SharpitTypography.meta)
                    .foregroundStyle(SharpitColor.mutedForeground)
            }

            LazyVGrid(columns: columns, spacing: SharpitSpacing.sm) {
                ForEach(items) { item in
                    sportCard(item)
                }
            }
        }
    }

    private func sportCard(_ item: PracticedSportItem) -> some View {
        let isSelected = practicedSports.contains(item.id)
        let color = sportColor(for: item.id)

        return Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            withAnimation(.snappy(duration: 0.2)) {
                if isSelected {
                    practicedSports.remove(item.id)
                } else {
                    practicedSports.insert(item.id)
                }
                ensureValidSelectedTab()
            }
            scheduleAutoSave()
        } label: {
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .top) {
                    ZStack {
                        RoundedRectangle(cornerRadius: SharpitRadius.small, style: .continuous)
                            .fill(isSelected ? color.opacity(0.18) : SharpitColor.analysisGrid.opacity(0.35))
                            .frame(width: 34, height: 34)
                        Image(systemName: item.symbolName)
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(isSelected ? color : SharpitColor.mutedForeground)
                    }

                    Spacer()

                    Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 18, weight: isSelected ? .bold : .regular))
                        .foregroundStyle(isSelected ? color : SharpitColor.mutedForeground.opacity(0.3))
                }

                Spacer(minLength: 8)

                VStack(alignment: .leading, spacing: 2) {
                    Text(item.label)
                        .font(SharpitTypography.bodyEmphasis)
                        .foregroundStyle(SharpitColor.foreground)
                        .lineLimit(1)
                        .minimumScaleFactor(0.9)

                    Text(item.subtitle)
                        .font(.system(size: 11))
                        .lineSpacing(1.5)
                        .foregroundStyle(SharpitColor.mutedForeground)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                        .frame(height: 30, alignment: .topLeading)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, minHeight: 124, maxHeight: 124, alignment: .topLeading)
            .background(
                RoundedRectangle(cornerRadius: SharpitRadius.panel, style: .continuous)
                    .fill(isSelected ? color.opacity(0.08) : SharpitColor.card.opacity(0.55))
            )
            .overlay(
                RoundedRectangle(cornerRadius: SharpitRadius.panel, style: .continuous)
                    .strokeBorder(isSelected ? color.opacity(0.8) : SharpitColor.border.opacity(0.5), lineWidth: isSelected ? 1.5 : 1)
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Equipment Inventory Section with Tabs

    private var equipmentInventorySection: some View {
        VStack(alignment: .leading, spacing: SharpitSpacing.md) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Inventaire matériel")
                    .font(SharpitTypography.sectionTitle)
                    .foregroundStyle(SharpitColor.foreground)

                Text("Le coach adapte les séances en fonction de ce que tu possèdes.")
                    .font(SharpitTypography.meta)
                    .foregroundStyle(SharpitColor.mutedForeground)
            }

            if visibleEquipmentSports.isEmpty {
                emptyPracticedSportsView
            } else {
                sportTabsBar

                VStack(spacing: SharpitSpacing.sm) {
                    if selectedSportTab == .strength {
                        strengthVenueSelector
                    }

                    let items = EquipmentCatalog.items(for: selectedSportTab, venue: strengthVenue)
                    if items.isEmpty {
                        emptyVenueEquipmentView
                    } else {
                        ForEach(items) { item in
                            equipmentCard(item)
                        }
                    }
                }
            }
        }
    }

    private var emptyPracticedSportsView: some View {
        VStack(spacing: SharpitSpacing.sm) {
            Image(systemName: "hand.tap")
                .font(.system(size: 28))
                .foregroundStyle(SharpitColor.mutedForeground)
            Text("Sélectionne au moins une discipline ci-dessus pour configurer ton matériel.")
                .font(SharpitTypography.meta)
                .foregroundStyle(SharpitColor.mutedForeground)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(SharpitSpacing.lg)
        .sharpitSurface(.panelAlt)
    }

    private var emptyVenueEquipmentView: some View {
        Text("Aucun équipement spécifique requis pour ce mode de renforcement.")
            .font(SharpitTypography.meta)
            .foregroundStyle(SharpitColor.mutedForeground)
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(SharpitSpacing.cardPadding)
            .sharpitSurface(.panelAlt)
    }

    // MARK: - Sport Tabs Bar

    private var sportTabsBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: SharpitSpacing.xs) {
                ForEach(visibleEquipmentSports) { sport in
                    let isSelected = selectedSportTab == sport
                    let items = EquipmentCatalog.items(for: sport, venue: strengthVenue)
                    let ownedCount = items.filter { owned.contains($0.id) }.count

                    Button {
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        withAnimation(.snappy(duration: 0.2)) {
                            selectedSportTab = sport
                        }
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: sport.symbolName)
                                .font(.system(size: 13, weight: .semibold))

                            Text(sport.label)
                                .font(SharpitTypography.meta)

                            Text("\(ownedCount)/\(items.count)")
                                .font(.system(size: 10, weight: .bold))
                                .padding(.horizontal, 5)
                                .padding(.vertical, 2)
                                .background(
                                    (isSelected ? SharpitColor.primaryForeground : SharpitColor.primary).opacity(0.18),
                                    in: Capsule()
                                )
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(
                            isSelected ? SharpitColor.primary : SharpitColor.card,
                            in: Capsule()
                        )
                        .foregroundStyle(isSelected ? SharpitColor.primaryForeground : SharpitColor.foreground)
                        .overlay(
                            Capsule()
                                .strokeBorder(isSelected ? Color.clear : SharpitColor.border.opacity(0.6), lineWidth: 1)
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.vertical, 2)
        }
    }

    // MARK: - Strength Venue Selector (Visual Cards)

    private var strengthVenueSelector: some View {
        VStack(alignment: .leading, spacing: SharpitSpacing.xs) {
            Text("Lieu principal de renforcement")
                .font(SharpitTypography.bodyEmphasis)
                .foregroundStyle(SharpitColor.foreground)

            LazyVGrid(columns: columns, spacing: SharpitSpacing.xs) {
                ForEach(V1AthleteEquipment.StrengthVenue.allCases) { venue in
                    venueCard(venue)
                }
            }

            if let venue = strengthVenue {
                Text(venue.description)
                    .font(SharpitTypography.meta)
                    .foregroundStyle(SharpitColor.mutedForeground)
                    .padding(.top, 2)
            }
        }
        .padding(SharpitSpacing.cardPadding)
        .sharpitSurface(.panelAlt)
    }

    private func venueCard(_ venue: V1AthleteEquipment.StrengthVenue) -> some View {
        let isSelected = strengthVenue == venue
        let icon: String = {
            switch venue {
            case .gym: "dumbbell"
            case .home: "house.fill"
            case .both: "arrow.triangle.2.circlepath"
            case .bodyweight: "figure.cross.training"
            }
        }()

        return Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            withAnimation(.snappy(duration: 0.2)) {
                strengthVenue = venue
            }
            scheduleAutoSave()
        } label: {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(isSelected ? SharpitColor.primary : SharpitColor.mutedForeground)

                Text(venue.title)
                    .font(SharpitTypography.meta)
                    .foregroundStyle(isSelected ? SharpitColor.foreground : SharpitColor.mutedForeground)

                Spacer()

                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(SharpitColor.primary)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: SharpitRadius.small, style: .continuous)
                    .fill(isSelected ? SharpitColor.card : SharpitColor.analysisGrid.opacity(0.3))
            )
            .overlay(
                RoundedRectangle(cornerRadius: SharpitRadius.small, style: .continuous)
                    .strokeBorder(isSelected ? SharpitColor.primary : Color.clear, lineWidth: 1.5)
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Equipment Item Card

    private func equipmentCard(_ item: EquipmentCatalogItem) -> some View {
        let isOwned = owned.contains(item.id)

        return Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            withAnimation(.snappy(duration: 0.2)) {
                if isOwned {
                    owned.remove(item.id)
                } else {
                    owned.insert(item.id)
                }
            }
            scheduleAutoSave()
        } label: {
            HStack(alignment: .center, spacing: SharpitSpacing.sm) {
                ZStack {
                    RoundedRectangle(cornerRadius: SharpitRadius.small, style: .continuous)
                        .fill(isOwned ? SharpitColor.primary.opacity(0.12) : SharpitColor.analysisGrid.opacity(0.4))
                        .frame(width: 38, height: 38)
                    Image(systemName: item.symbolName)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(isOwned ? SharpitColor.primary : SharpitColor.mutedForeground)
                }

                VStack(alignment: .leading, spacing: 3) {
                    Text(item.label)
                        .font(SharpitTypography.bodyEmphasis)
                        .foregroundStyle(SharpitColor.foreground)

                    Text(item.impact)
                        .font(SharpitTypography.meta)
                        .foregroundStyle(SharpitColor.mutedForeground)
                        .lineLimit(2)
                }

                Spacer()

                Image(systemName: isOwned ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 20, weight: isOwned ? .bold : .regular))
                    .foregroundStyle(isOwned ? SharpitColor.primary : SharpitColor.mutedForeground.opacity(0.3))
            }
            .padding(SharpitSpacing.cardPadding)
            .sharpitSurface(.panel)
            .overlay(
                RoundedRectangle(cornerRadius: SharpitRadius.panel, style: .continuous)
                    .strokeBorder(isOwned ? SharpitColor.primary.opacity(0.35) : Color.clear, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Helpers & Data Sync

    private var visibleEquipmentSports: [EquipmentSport] {
        if practicedSports.isEmpty {
            return EquipmentSport.allCases
        }
        return EquipmentSport.allCases.filter { sport in
            switch sport {
            case .run:
                return practicedSports.contains("run") || practicedSports.contains("triathlon")
            case .bike:
                return practicedSports.contains("bike") || practicedSports.contains("triathlon")
            case .swim:
                return practicedSports.contains("swim") || practicedSports.contains("triathlon")
            case .strength:
                return practicedSports.contains("strength")
            case .mobility:
                return practicedSports.contains("mobility") || practicedSports.contains("stretching")
            }
        }
    }

    private func ensureValidSelectedTab() {
        if !visibleEquipmentSports.contains(selectedSportTab), let first = visibleEquipmentSports.first {
            selectedSportTab = first
        }
    }

    private func sportColor(for id: String) -> Color {
        switch id {
        case "run": SharpitSportColor.color(SharpitSportColor.run)
        case "bike": SharpitSportColor.color(SharpitSportColor.bike)
        case "swim": SharpitSportColor.color(SharpitSportColor.swim)
        case "triathlon": SharpitSportColor.color(SharpitSportColor.triathlon)
        case "strength": SharpitSportColor.color(SharpitSportColor.strength)
        case "mobility": SharpitSportColor.color(SharpitSportColor.other)
        case "stretching": Color(red: 0.18, green: 0.82, blue: 0.65)
        default: SharpitColor.primary
        }
    }

    private func syncFromProfile() {
        if let ps = store.profile.practicedSports, !ps.sports.isEmpty {
            practicedSports = Set(ps.sports)
        }

        if let eq = store.profile.equipment {
            if let rawVenue = eq.strengthVenue, let v = V1AthleteEquipment.StrengthVenue(rawValue: rawVenue) {
                strengthVenue = v
            } else {
                strengthVenue = .bodyweight
            }
            owned = Set(eq.owned)
        } else {
            strengthVenue = .bodyweight
        }
        ensureValidSelectedTab()
        hasLoaded = true
    }

    private func scheduleAutoSave() {
        guard hasLoaded else { return }
        autoSaveTask?.cancel()
        autoSaveTask = Task {
            try? await Task.sleep(nanoseconds: 350_000_000)
            guard !Task.isCancelled else { return }
            await save()
        }
    }

    @MainActor
    private func save() async {
        var patch = AthleteProfilePatch()

        // 1. Practiced sports
        let ps = V1AthletePracticedSports(
            version: 1,
            sports: Array(practicedSports).sorted()
        )
        patch.setPracticedSports(ps)

        // 2. Equipment
        let eq = V1AthleteEquipment(
            version: 1,
            strengthVenue: strengthVenue?.rawValue,
            owned: Array(owned).sorted()
        )
        patch.setEquipment(eq)

        let success = await store.save(patch)
        if !success, let error = store.saveError {
            toastCenter?.show(error, symbol: "exclamationmark.triangle.fill", tone: .error)
        }
    }
}
