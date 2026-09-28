import AuthenticationServices
import SwiftUI
import UIKit

// MARK: - Identity

/// Who the athlete is: the first name the app greets them by, then the body the coach sizes
/// loads against. Only the first name is required.
struct OnboardingIdentityStep: View {
    @Binding var draft: OnboardingIdentityDraft

    private static let heights = 120...220
    private static let birthDates: ClosedRange<Date> = {
        let calendar = Calendar.current
        let earliest = calendar.date(byAdding: .year, value: -100, to: .now) ?? .distantPast
        let latest = calendar.date(byAdding: .year, value: -12, to: .now) ?? .now
        return earliest...latest
    }()

    var body: some View {
        VStack(alignment: .leading, spacing: SharpitSpacing.lg) {
            SharpitFormField("Prénom", placeholder: "Ton prénom", text: $draft.firstName)
                .textContentType(.givenName)

            VStack(alignment: .leading, spacing: SharpitSpacing.xs) {
                SharpitFieldLabel("Sexe")
                SharpitSegmentedChoice(options: AthleteSex.allCases, label: \.label, selection: $draft.sex)
            }

            VStack(alignment: .leading, spacing: SharpitSpacing.xs) {
                SharpitFieldLabel("Taille")
                SharpitRulerPicker(value: $draft.heightCm, range: Self.heights, unit: "cm", resting: 170)
            }

            SharpitDateField(
                title: "Date de naissance",
                date: $draft.birthDate,
                range: Self.birthDates,
                resting: Calendar.current.date(byAdding: .year, value: -30, to: .now) ?? .now,
                caption: { birth in
                    let years = Calendar.current.dateComponents([.year], from: birth, to: .now).year ?? 0
                    return "\(years) ans"
                }
            )
        }
    }
}

// MARK: - Shared controls

/// One choice of a few: picked, it fills. No symbol animation — a choice is seen by its fill and
/// felt by a light haptic, nothing more.
struct OnboardingChoiceChip: View {
    let title: String
    var symbol: String?
    let isSelected: Bool
    let onSelect: () -> Void

    var body: some View {
        Button {
            SharpitHaptics.play(.soft)
            onSelect()
        } label: {
            HStack(spacing: SharpitSpacing.xs) {
                if let symbol {
                    Image(systemName: symbol)
                        .symbolVariant(isSelected ? .fill : .none)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(isSelected ? SharpitColor.primaryForeground : SharpitColor.mutedForeground)
                        .frame(width: 22)
                }
                Text(title)
                    .font(SharpitTypography.meta.weight(.semibold))
                    .foregroundStyle(isSelected ? SharpitColor.primaryForeground : SharpitColor.foreground)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
                if symbol != nil { Spacer(minLength: 0) }
            }
            .padding(.horizontal, SharpitSpacing.sm)
            .frame(maxWidth: .infinity, minHeight: SharpitSpacing.minimumTouchTarget)
            .background(
                RoundedRectangle(cornerRadius: SharpitRadius.small, style: .continuous)
                    .fill(isSelected ? SharpitColor.primary : SharpitColor.analysisSurfaceAlt)
            )
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }
}

// MARK: - Sports

/// Endurance first, complements after. A tile answers the touch by filling, never by moving.
struct OnboardingSportsStep: View {
    let store: OnboardingStore

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
                    OnboardingSportTile(item: item, isSelected: store.sports.contains(item.id)) {
                        store.toggleSport(item.id)
                    }
                }
            }
        }
    }
}

struct OnboardingSportTile: View {
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

// MARK: - Equipment

/// Only the kit the chosen sports use, one card per sport; strength asks where the athlete
/// trains before listing what they own.
struct OnboardingEquipmentStep: View {
    let store: OnboardingStore

    var body: some View {
        VStack(alignment: .leading, spacing: SharpitSpacing.md) {
            ForEach(store.equipmentSports) { sport in
                VStack(alignment: .leading, spacing: SharpitSpacing.md) {
                    SharpitCardHeader(title: sport.label, symbol: sport.symbolName, showsChevron: false)
                    if sport == .strength {
                        venuePicker
                    }
                    let items = EquipmentCatalog.items(for: sport, venue: store.strengthVenue)
                    if items.isEmpty {
                        Text("Rien de particulier pour ce type de renforcement.")
                            .font(SharpitTypography.meta)
                            .foregroundStyle(SharpitColor.mutedForeground)
                    } else {
                        VStack(spacing: 0) {
                            ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                                OnboardingEquipmentRow(item: item, isOwned: store.ownedEquipment.contains(item.id)) {
                                    store.toggleEquipment(item.id)
                                }
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
                ForEach(V1AthleteEquipment.StrengthVenue.allCases) { venue in
                    OnboardingChoiceChip(title: venue.title, symbol: venue.symbolName, isSelected: store.strengthVenue == venue) {
                        SharpitMotion.run(SharpitMotion.selection) { store.setStrengthVenue(venue) }
                    }
                }
            }
            Text(store.strengthVenue.description)
                .font(SharpitTypography.meta)
                .foregroundStyle(SharpitColor.mutedForeground)
                .contentTransition(.opacity)
        }
    }
}

private struct OnboardingEquipmentRow: View {
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

// MARK: - Week

/// The week painted with a finger: the first day touched decides whether the stroke adds or
/// clears, and every day the finger crosses follows. The count is read live.
struct OnboardingWeekStep: View {
    let store: OnboardingStore

    @State private var paintValue: Bool?
    @State private var lastPainted: Int?

    private let days = V1TrainingAvailability.weekdaysMondayFirst

    private var count: Int { store.availability.availableWeekdays.count }

    var body: some View {
        VStack(alignment: .leading, spacing: SharpitSpacing.lg) {
            GeometryReader { geo in
                HStack(spacing: SharpitSpacing.xs) {
                    ForEach(days, id: \.self) { day in
                        dayColumn(day)
                    }
                }
                .contentShape(.rect)
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in paint(at: value.location.x, width: geo.size.width) }
                        .onEnded { _ in
                            paintValue = nil
                            lastPainted = nil
                        }
                )
            }
            .frame(height: 150)
            .accessibilityElement(children: .contain)

            VStack(alignment: .leading, spacing: SharpitSpacing.xxs) {
                HStack(alignment: .firstTextBaseline, spacing: SharpitSpacing.xs) {
                    Text("\(count)")
                        .font(SharpitTypography.heroScore)
                        .tracking(SharpitTypography.heroScoreTracking)
                        .foregroundStyle(count == 0 ? SharpitColor.mutedForeground : SharpitColor.foreground)
                        .contentTransition(.numericText(value: Double(count)))
                    Text(count == 1 ? "séance par semaine" : "séances par semaine")
                        .font(SharpitTypography.bodyEmphasis)
                        .foregroundStyle(SharpitColor.mutedForeground)
                }
                Text(count == 0
                     ? "Aucun jour choisi : le coach s'appuiera sur les jours où tu t'entraînes vraiment."
                     : "Le coach place tes séances sur ces jours et règle le volume en conséquence.")
                    .font(SharpitTypography.meta)
                    .foregroundStyle(SharpitColor.mutedForeground)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .animation(SharpitMotion.selection, value: count)
        }
    }

    private func dayColumn(_ day: Int) -> some View {
        let isOn = store.availability.availableWeekdays.contains(day)
        return VStack(spacing: SharpitSpacing.xs) {
            ZStack(alignment: .bottom) {
                Capsule().fill(SharpitColor.analysisSurfaceAlt)
                Capsule()
                    .fill(SharpitColor.primary)
                    .frame(maxHeight: isOn ? .infinity : 0)
                    .opacity(isOn ? 1 : 0)
                Image(systemName: isOn ? "figure.run" : "moon.zzz")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(isOn ? SharpitColor.primaryForeground : SharpitColor.mutedForeground.opacity(0.6))
                    .contentTransition(.symbolEffect(.replace))
                    .padding(.bottom, SharpitSpacing.sm)
            }
            .animation(SharpitMotion.selection, value: isOn)
            Text(OnboardingWeekday.shortLabels[day].prefix(1))
                .font(SharpitTypography.label)
                .foregroundStyle(isOn ? SharpitColor.foreground : SharpitColor.mutedForeground)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(OnboardingWeekday.label(day))
        .accessibilityValue(isOn ? "disponible" : "non disponible")
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { store.toggleWeekday(day) }
    }

    private func paint(at x: CGFloat, width: CGFloat) {
        guard width > 0 else { return }
        let index = min(max(Int(x / (width / CGFloat(days.count))), 0), days.count - 1)
        guard index != lastPainted else { return }
        let day = days[index]
        let value = paintValue ?? !store.availability.availableWeekdays.contains(day)
        paintValue = value
        lastPainted = index
        if store.availability.availableWeekdays.contains(day) != value {
            SharpitHaptics.play(.soft)
            store.setWeekday(day, available: value)
        }
    }
}

// MARK: - Goal

/// A race with its date, or a figure to reach. The time left is read live, so the athlete sees
/// what the plan has to work with.
struct OnboardingGoalStep: View {
    @Binding var draft: OnboardingIntentionDraft

    private var weeksLeft: Int {
        max(Calendar.current.dateComponents([.weekOfYear], from: .now, to: draft.raceDate).weekOfYear ?? 0, 0)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: SharpitSpacing.md) {
            HStack(spacing: SharpitSpacing.sm) {
                kindCard(.race, title: "Une course", symbol: "flag.checkered")
                kindCard(.metric, title: "Un palier", symbol: "gauge.with.needle")
            }

            switch draft.kind {
            case .race:
                SharpitFormField("Nom de l'épreuve", placeholder: "Marathon de Paris, 70.3 Nice…", text: $draft.raceTitle)
                VStack(alignment: .leading, spacing: SharpitSpacing.sm) {
                    DatePicker("Date", selection: $draft.raceDate, in: Date()..., displayedComponents: .date)
                        .font(SharpitTypography.bodyEmphasis)
                        .tint(SharpitColor.primary)
                    Rectangle().fill(SharpitColor.analysisGrid).frame(height: 1)
                    HStack(alignment: .firstTextBaseline, spacing: SharpitSpacing.xs) {
                        Text("\(weeksLeft)")
                            .font(SharpitTypography.gaugeScore)
                            .tracking(SharpitTypography.gaugeScoreTracking)
                            .foregroundStyle(SharpitColor.foreground)
                            .contentTransition(.numericText(value: Double(weeksLeft)))
                        Text(weeksLeft == 1 ? "semaine de préparation" : "semaines de préparation")
                            .font(SharpitTypography.bodyEmphasis)
                            .foregroundStyle(SharpitColor.mutedForeground)
                    }
                    .animation(SharpitMotion.selection, value: weeksLeft)
                }
                .padding(SharpitSpacing.cardPadding)
                .sharpitSurface(.panel)
                OnboardingPlaceField(title: "Lieu (optionnel)", text: $draft.raceLocation)
            case .metric:
                SharpitFormField("Ce que tu veux atteindre", placeholder: "FTP, VMA, allure 10 km…", text: $draft.metricTitle)
                HStack(spacing: SharpitSpacing.sm) {
                    SharpitFormField("Valeur", placeholder: "280", text: $draft.metricTargetText, keyboard: .decimalPad)
                    SharpitFormField("Unité", placeholder: "W, km/h…", text: $draft.metricUnit)
                }
            }
        }
        .animation(SharpitMotion.selection, value: draft.kind)
    }

    private func kindCard(_ kind: OnboardingIntentionKind, title: String, symbol: String) -> some View {
        let isSelected = draft.kind == kind
        return Button {
            SharpitHaptics.play(.soft)
            SharpitMotion.run(SharpitMotion.selection) { draft.kind = kind }
        } label: {
            HStack(spacing: SharpitSpacing.sm) {
                Image(systemName: symbol)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(isSelected ? SharpitColor.primary : SharpitColor.mutedForeground)
                Text(title)
                    .font(SharpitTypography.cardTitle)
                    .foregroundStyle(SharpitColor.foreground)
                Spacer(minLength: 0)
            }
            .padding(SharpitSpacing.md)
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
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }
}

// MARK: - Injuries

/// What hurts now: the declared ones first, then the zones — touching one opens its questions in
/// a sheet, where nothing is chosen in advance. The coach reads them as sensitive zones.
struct OnboardingInjuriesStep: View {
    let store: OnboardingStore
    @State private var editing: OnboardingInjuryDraft?

    var body: some View {
        VStack(alignment: .leading, spacing: SharpitSpacing.lg) {
            if !store.injuries.isEmpty {
                VStack(spacing: 0) {
                    ForEach(Array(store.injuries.enumerated()), id: \.element.id) { index, injury in
                        OnboardingInjuryRow(injury: injury) {
                            editing = injury
                        } onRemove: {
                            SharpitHaptics.play(.soft)
                            store.removeInjury(injury.bodyPart)
                        }
                        if index < store.injuries.count - 1 {
                            Rectangle().fill(SharpitColor.analysisGrid).frame(height: 1)
                        }
                    }
                }
                .padding(.horizontal, SharpitSpacing.cardPadding)
                .sharpitSurface(.panel)
            }

            VStack(alignment: .leading, spacing: SharpitSpacing.xs) {
                SharpitFieldLabel(store.injuries.isEmpty ? "Où as-tu mal ?" : "Une autre zone ?")
                LazyVGrid(
                    columns: Array(repeating: GridItem(.flexible(), spacing: SharpitSpacing.xs), count: 3),
                    spacing: SharpitSpacing.xs
                ) {
                    ForEach(OnboardingInjuryDraft.bodyParts, id: \.self) { part in
                        let declared = store.injuries.first { $0.bodyPart == part }
                        OnboardingChoiceChip(title: part, isSelected: declared != nil) {
                            editing = declared ?? OnboardingInjuryDraft(bodyPart: part)
                        }
                    }
                }
            }

            Text(store.injuries.isEmpty
                ? "Rien en cours ? Passe cette étape."
                : "Tu pourras suivre leur évolution depuis Corps.")
                .font(SharpitTypography.meta)
                .foregroundStyle(SharpitColor.mutedForeground)
        }
        .sheet(item: $editing) { draft in
            OnboardingInjurySheet(
                draft: draft,
                isDeclared: store.injuries.contains { $0.id == draft.id }
            ) { saved in
                store.saveInjury(saved)
            } onRemove: {
                store.removeInjury(draft.bodyPart)
            }
            .sharpitSheet()
            .presentationDetents([.medium, .large])
        }
    }
}

private struct OnboardingInjuryRow: View {
    let injury: OnboardingInjuryDraft
    let onEdit: () -> Void
    let onRemove: () -> Void

    var body: some View {
        HStack(spacing: SharpitSpacing.sm) {
            Button(action: onEdit) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(injury.title.prefix(1).uppercased() + injury.title.dropFirst())
                        .font(SharpitTypography.bodyEmphasis)
                        .foregroundStyle(SharpitColor.foreground)
                    Text("Gêne \((injury.level ?? .moderate).label.lowercased())")
                        .font(SharpitTypography.meta)
                        .foregroundStyle(SharpitColor.mutedForeground)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            Button(action: onRemove) {
                Image(systemName: "xmark")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(SharpitColor.mutedForeground)
                    .frame(width: 32, height: 32)
                    .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Retirer \(injury.bodyPart)")
        }
        .padding(.vertical, SharpitSpacing.sm)
    }
}

/// The questions for one zone. Nothing is picked in advance; « Ajouter » waits for every answer
/// that applies.
private struct OnboardingInjurySheet: View {
    @State var draft: OnboardingInjuryDraft
    let isDeclared: Bool
    let onSave: (OnboardingInjuryDraft) -> Void
    let onRemove: () -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: SharpitSpacing.md) {
                question("Qu'est-ce que c'est ?") {
                    ForEach(OnboardingInjuryDraft.Kind.allCases) { kind in
                        OnboardingChoiceChip(title: kind.label, isSelected: draft.kind == kind) { draft.kind = kind }
                    }
                }
                if draft.asksForSide {
                    question("Quel côté ?") {
                        ForEach(OnboardingInjuryDraft.Side.allCases) { side in
                            OnboardingChoiceChip(title: side.label, isSelected: draft.side == side) { draft.side = side }
                        }
                    }
                }
                question("Quelle gêne ?") {
                    ForEach(OnboardingInjuryDraft.Level.allCases) { level in
                        OnboardingChoiceChip(title: level.label, isSelected: draft.level == level) { draft.level = level }
                    }
                }
                Spacer(minLength: 0)
                Button {
                    SharpitHaptics.play(.soft)
                    onSave(draft)
                    dismiss()
                } label: {
                    Text(isDeclared ? "Enregistrer" : "Ajouter")
                        .font(SharpitTypography.bodyEmphasis)
                        .foregroundStyle(SharpitColor.primaryForeground)
                        .frame(maxWidth: .infinity)
                }
                .sharpitGlassButton(prominent: true)
                .tint(SharpitColor.primary)
                .disabled(!draft.isComplete)
            }
            .padding(SharpitSpacing.pageInset)
            .navigationTitle(draft.bodyPart)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Annuler") { dismiss() }
                }
                if isDeclared {
                    ToolbarItem(placement: .destructiveAction) {
                        Button("Retirer", role: .destructive) {
                            onRemove()
                            dismiss()
                        }
                    }
                }
            }
        }
    }

    private func question(_ title: String, @ViewBuilder choices: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: SharpitSpacing.xs) {
            SharpitFieldLabel(title)
            HStack(spacing: SharpitSpacing.xs) { choices() }
        }
    }
}

// MARK: - Privacy

/// The consents, just before the sources that bring the data in. The documents and health are
/// required together; AI (the coach, and the first week that follows) is optional, and says
/// what it unlocks.
struct OnboardingPrivacyStep: View {
    @Binding var consents: OnboardingConsents
    @State private var openDocument: LegalDocument?

    var body: some View {
        VStack(alignment: .leading, spacing: SharpitSpacing.md) {
            if !consents.requiredAccepted {
                Button {
                    SharpitHaptics.play(.soft)
                    SharpitMotion.run(SharpitMotion.selection) { consents.acceptAll() }
                } label: {
                    Label("Tout accepter", systemImage: "checkmark.circle")
                        .font(SharpitTypography.bodyEmphasis)
                        .foregroundStyle(SharpitColor.primary)
                        .padding(.horizontal, SharpitSpacing.md)
                        .padding(.vertical, SharpitSpacing.xs)
                        .background(SharpitColor.primary.opacity(0.10), in: Capsule())
                }
                .buttonStyle(.plain)
                .transition(.opacity)
            }

            VStack(alignment: .leading, spacing: 0) {
                ConsentCheckRow(isOn: $consents.terms, document: .terms, onRead: { openDocument = .terms }) {
                    Text("J'accepte les Conditions d'utilisation.")
                }
                Divider().padding(.leading, 44)
                ConsentCheckRow(isOn: $consents.privacy, document: .privacy, onRead: { openDocument = .privacy }) {
                    Text("J'accepte la Politique de confidentialité.")
                }
                Divider().padding(.leading, 44)
                ConsentCheckRow(isOn: $consents.health) {
                    Text("J'autorise le traitement de mes données de santé et physiologiques (récupération, fatigue, Twin).")
                }
            }
            .padding(.horizontal, SharpitSpacing.cardPadding)
            .sharpitSurface(.panel)

            SharpitEyebrow("Optionnel")
            VStack(alignment: .leading, spacing: 0) {
                ConsentCheckRow(isOn: $consents.ai) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("J'autorise le traitement par IA.")
                        Text("Le coach, les bilans rédigés et ta première semaine de séances en dépendent.")
                            .font(SharpitTypography.meta)
                            .foregroundStyle(SharpitColor.mutedForeground)
                    }
                }
                Divider().padding(.leading, 44)
                ConsentCheckRow(isOn: $consents.unofficialProviders) {
                    Text("Je comprends que certaines connexions fournisseurs peuvent être non officielles.")
                }
            }
            .padding(.horizontal, SharpitSpacing.cardPadding)
            .sharpitSurface(.panelAlt)

            Text(PrivacyCopy.healthDisclaimer)
                .font(SharpitTypography.meta)
                .foregroundStyle(SharpitColor.mutedForeground)
                .fixedSize(horizontal: false, vertical: true)
        }
        .animation(SharpitMotion.selection, value: consents.requiredAccepted)
        .sheet(item: $openDocument) { document in
            LegalDocumentSheet(document: document)
        }
    }
}

// MARK: - First week

/// The week the coach planned while the athlete linked their sources. It fills the dial as the
/// coach reasons, then lays the sessions out day by day; adding them puts them in the plan.
struct OnboardingFirstWeekStep: View {
    let store: OnboardingStore

    var body: some View {
        switch store.firstWeek {
        case .idle, .generating:
            generating
        case .ready(let summary, let sessions):
            ready(summary: summary, sessions: sessions)
        case .unavailable:
            note(
                symbol: "calendar.badge.exclamationmark",
                title: "Pas de séances générées",
                detail: "Sans le traitement par IA, le coach ne rédige pas de séances. Tu peux l'activer plus tard dans Paramètres › Confidentialité, puis demander ta semaine depuis le Plan."
            )
        case .failed(let message):
            VStack(alignment: .leading, spacing: SharpitSpacing.md) {
                note(symbol: "exclamationmark.triangle", title: "Semaine non préparée", detail: message)
                Button("Réessayer") { store.startFirstWeek() }
                    .font(SharpitTypography.bodyEmphasis)
                    .foregroundStyle(SharpitColor.primary)
            }
        }
    }

    private var generating: some View {
        GeneratingWeekView(drafts: store.firstWeekDrafts)
    }

    private func ready(summary: String, sessions: [V1GeneratedSession]) -> some View {
        VStack(alignment: .leading, spacing: SharpitSpacing.sm) {
            if !summary.isEmpty {
                Text(summary)
                    .font(SharpitTypography.body)
                    .foregroundStyle(SharpitColor.foreground)
                    .lineLimit(3)
            }
            GeneratedWeekView(sessions: sessions)
            ForEach(Array(store.firstWeekSetAside.enumerated()), id: \.offset) { _, entry in
                GeneratedSessionRow(session: entry.session, rejection: entry.reason ?? "Écartée par le contrôle de sécurité.")
            }
        }
    }

    private func note(symbol: String, title: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: SharpitSpacing.md) {
            Image(systemName: symbol)
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(SharpitColor.mutedForeground)
                .frame(width: 32)
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(SharpitTypography.cardTitle)
                    .foregroundStyle(SharpitColor.foreground)
                Text(detail)
                    .font(SharpitTypography.body)
                    .foregroundStyle(SharpitColor.mutedForeground)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(SharpitSpacing.cardPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .sharpitSurface(.panel)
    }
}

// MARK: - Sources

/// Where the readings come from. Garmin is connected natively in-app; Apple Health is switched on here.
/// Connecting nothing is a valid path: Finaliser is never held back by this step.
struct OnboardingSourcesStep: View {
    let appleHealth: AppleHealthSource
    let syncClient: any SyncServing
    let tokenProvider: () async throws -> String
    var garminClient: any GarminHandoffServing = SharpitClient()
    var mfpClient: any MyFitnessPalServing = SharpitClient()

    @State private var status: V1SyncStatus?
    @State private var isConnectingGarmin = false
    @State private var isConnectingMfp = false
    /// The last connection's outcome when it did not link Garmin, said under the card: the
    /// onboarding sits before the shell and its toasts.
    @State private var garminFailure: GarminConnectOutcome?
    @Environment(\.webAuthenticationSession) private var webAuthenticationSession

    var body: some View {
        VStack(alignment: .leading, spacing: SharpitSpacing.sm) {
            OnboardingSourceCard(
                provider: .garmin,
                title: "Garmin Connect",
                detail: "Activités GPS, fréquence cardiaque, sommeil et charge."
            ) {
                connectButton(isConnected: isConnected("garmin"), isBusy: isConnectingGarmin) {
                    Task { await connectGarmin() }
                }
            }
            if let garminFailure {
                Text(garminFailure.message)
                    .font(SharpitTypography.meta)
                    .foregroundStyle(garminFailure.tone == .error ? SharpitColor.signalRisk : SharpitColor.mutedForeground)
                    .padding(.horizontal, SharpitSpacing.xxs)
            }
            OnboardingSourceCard(
                provider: .appleHealth,
                title: "Apple Santé",
                detail: appleHealthDetail
            ) {
                Toggle("Apple Santé", isOn: appleHealthBinding)
                    .labelsHidden()
                    .tint(SharpitColor.primary)
                    .disabled(!appleHealth.isAvailable)
            }
            OnboardingSourceCard(
                provider: .myFitnessPal,
                title: "MyFitnessPal",
                detail: "Ton journal alimentaire, pour que le coach voie ce que tu manges."
            ) {
                connectButton(isConnected: isConnected("myfitnesspal"), isBusy: false) {
                    isConnectingMfp = true
                }
            }

            Text("Tout est optionnel et se règle plus tard dans Paramètres › Sources.")
                .font(SharpitTypography.meta)
                .foregroundStyle(SharpitColor.mutedForeground)
                .padding(.horizontal, SharpitSpacing.xxs)
                .padding(.top, SharpitSpacing.xxs)
        }
        .task { await loadStatus() }
        .sheet(isPresented: $isConnectingMfp) {
            MyFitnessPalConnectSheet(client: mfpClient, tokenProvider: tokenProvider) {
                SharpitHaptics.play(.success)
                Task { await loadStatus() }
            }
            .sharpitSheet()
        }
    }

    private func isConnected(_ key: String) -> Bool {
        status?.providers.contains(where: { $0.key == key }) ?? false
    }

    private var appleHealthDetail: String {
        let line = ConnectionsReadout.appleHealthSubtitle(isAvailable: appleHealth.isAvailable, state: appleHealth.state)
        return appleHealth.isAvailable && !line.isProblem ? "Pas, fréquence cardiaque au repos et sommeil." : line.text
    }

    @ViewBuilder
    private func connectButton(isConnected: Bool, isBusy: Bool, action: @escaping () -> Void) -> some View {
        if isConnected {
            Image(systemName: "checkmark.circle.fill")
                .font(.title3.weight(.semibold))
                .foregroundStyle(SharpitColor.primary)
                .transition(.symbolEffect(.appear))
                .accessibilityLabel("Connecté")
        } else {
            Button {
                action()
            } label: {
                if isBusy {
                    ProgressView().tint(SharpitColor.primaryForeground)
                } else {
                    Text("Connecter")
                        .font(SharpitTypography.meta.weight(.semibold))
                        .foregroundStyle(SharpitColor.primaryForeground)
                }
            }
            .sharpitGlassButton(prominent: true)
            .tint(SharpitColor.primary)
            .controlSize(.small)
            .disabled(isBusy)
        }
    }

    private var appleHealthBinding: Binding<Bool> {
        Binding(
            get: { appleHealth.isEnabled },
            set: { on in
                if on {
                    Task { await appleHealth.enable(token: tokenProvider) }
                } else {
                    appleHealth.disable()
                }
            }
        )
    }

    /// Garmin opens in an in-app sheet (SHARPIT ADR-047). The history import starts once the
    /// shell sees Garmin connected, so the step only reads the sources again.
    private func connectGarmin() async {
        guard !isConnectingGarmin else { return }
        isConnectingGarmin = true
        defer { isConnectingGarmin = false }
        let outcome = await GarminConnect.run(
            client: garminClient,
            tokenProvider: tokenProvider,
            authenticate: webAuthenticationSession.garminConnect
        )
        garminFailure = outcome.isLinked ? nil : outcome
        if outcome.isLinked {
            SharpitHaptics.play(.success)
            await loadStatus()
        }
    }

    private func loadStatus() async {
        guard let token = try? await tokenProvider() else { return }
        status = try? await syncClient.syncStatus(token: token)
    }
}

/// One source in the sources step: its logo, what it brings, and its control — the control
/// says whether it is linked, on a plain surface so a switch stays legible in both themes.
private struct OnboardingSourceCard<Control: View>: View {
    let provider: ProviderLogo.Provider
    let title: String
    let detail: String
    @ViewBuilder let control: Control

    var body: some View {
        HStack(spacing: SharpitSpacing.sm) {
            ProviderLogo(provider: provider)
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(SharpitTypography.cardTitle)
                    .tracking(SharpitTypography.cardTitleTracking)
                    .foregroundStyle(SharpitColor.foreground)
                Text(detail)
                    .font(SharpitTypography.meta)
                    .foregroundStyle(SharpitColor.mutedForeground)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: SharpitSpacing.xs)
            control
        }
        .padding(SharpitSpacing.cardPadding)
        .sharpitSurface(.panel)
        .accessibilityElement(children: .contain)
    }
}
