import AuthenticationServices
import StoreKit
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
            SharpitFormField(String(localized: "Prénom"), placeholder: String(localized: "Ton prénom"), text: $draft.firstName)
                .textContentType(.givenName)

            VStack(alignment: .leading, spacing: SharpitSpacing.xs) {
                SharpitFieldLabel(String(localized: "Sexe"))
                SharpitSegmentedChoice(options: AthleteSex.allCases, label: \.label, selection: $draft.sex)
            }

            VStack(alignment: .leading, spacing: SharpitSpacing.xs) {
                SharpitFieldLabel(String(localized: "Taille"))
                SharpitRulerPicker(value: $draft.heightCm, range: Self.heights, unit: "cm", resting: 170)
            }

            SharpitDateField(
                title: String(localized: "Date de naissance"),
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

/// One choice of a few: picked, it fills. No symbol animation and no haptic — a choice is seen by
/// its fill, nothing more.
struct OnboardingChoiceChip: View {
    let title: String
    var symbol: String?
    let isSelected: Bool
    let onSelect: () -> Void

    var body: some View {
        Button {
            onSelect()
        } label: {
            HStack(spacing: SharpitSpacing.xs) {
                if let symbol {
                    Image(sharpitSymbol: symbol)
                        .symbolVariant(isSelected ? .fill : .none)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(isSelected ? SharpitColor.primaryForeground : SharpitColor.mutedForeground)
                        .frame(width: 22)
                }
                Text(title)
                    .font(SharpitTypography.meta.weight(.semibold))
                    .foregroundStyle(isSelected ? SharpitColor.primaryForeground : SharpitColor.foreground)
                    // A third of a 375 pt screen cannot hold « Tendon d'Achille » on one line.
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
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

// MARK: - Motivation

/// Why the athlete comes: the coaching, always in, then what they want to follow besides — each
/// a row ticked by its fill. What stays unticked leaves the app (Paramètres › Pages et widgets).
struct OnboardingMotivationStep: View {
    let store: OnboardingStore

    var body: some View {
        VStack(spacing: SharpitSpacing.sm) {
            // Always on for the coach build — same look as the others, never locked
            // (Pro is asked on the first-week step, not here).
            MotivationRow(
                symbol: "figure.run",
                title: OnboardingMotivation.coachingTitle,
                detail: OnboardingMotivation.coachingDetail,
                isSelected: true
            ) {}
            .allowsHitTesting(false)
            ForEach(OnboardingMotivation.order) { feature in
                MotivationRow(
                    symbol: feature.symbolName,
                    title: OnboardingMotivation.title(feature),
                    detail: OnboardingMotivation.detail(feature),
                    isSelected: store.motivations.contains(feature)
                ) {
                    SharpitHaptics.play(.notch(major: false))
                    SharpitMotion.run(SharpitMotion.selection) { store.toggleMotivation(feature) }
                }
            }
        }
    }
}

/// A row ticked by its fill — also the week step's intensity choice.
struct MotivationRow: View {
    let symbol: String
    let title: String
    let detail: String
    let isSelected: Bool
    let onToggle: () -> Void

    var body: some View {
        Button(action: onToggle) {
            HStack(spacing: SharpitSpacing.md) {
                SharpitIconTile(symbol: symbol, size: 44)
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(SharpitTypography.cardTitle)
                        .foregroundStyle(SharpitColor.foreground)
                    Text(detail)
                        .font(SharpitTypography.meta)
                        .foregroundStyle(SharpitColor.mutedForeground)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: SharpitSpacing.xs)
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(isSelected ? SharpitColor.primary : SharpitColor.mutedForeground.opacity(0.45))
                    .symbolEffect(.bounce, value: isSelected)
                    .accessibilityHidden(true)
            }
            .padding(SharpitSpacing.md)
            .background(
                RoundedRectangle(cornerRadius: SharpitRadius.panel, style: .continuous)
                    .fill(SharpitColor.analysisSurfaceAlt)
            )
            .overlay(
                RoundedRectangle(cornerRadius: SharpitRadius.panel, style: .continuous)
                    .strokeBorder(isSelected ? SharpitColor.primary : SharpitColor.analysisGrid, lineWidth: isSelected ? 2 : 1)
            )
            .contentShape(.rect)
        }
        .buttonStyle(.sharpitPressable)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }
}

// MARK: - Sports

/// Endurance first, complements after — the same tiles as Paramètres › Sports & équipement.
struct OnboardingSportsStep: View {
    let store: OnboardingStore

    var body: some View {
        SportChoiceGroups(selected: Set(store.sports)) { store.toggleSport($0) }
    }
}

// MARK: - Equipment

/// Only the kit the chosen sports use, one card per sport — the same cards as Paramètres.
struct OnboardingEquipmentStep: View {
    let store: OnboardingStore

    var body: some View {
        EquipmentBySport(
            sports: store.equipmentSports,
            venue: store.strengthVenue,
            owned: store.ownedEquipment,
            onVenue: { store.setStrengthVenue($0) },
            onToggle: { store.toggleEquipment($0) }
        )
    }
}

// MARK: - Week

/// Effort first, then the days that carry it: the intensity seeds a count of sessions and a
/// week spread for recovery; the athlete moves the count, then moves days with a tap. Each
/// session is a token placed on a day; once all are placed, the free days fade — the limit is
/// seen, not discovered.
struct OnboardingWeekStep: View {
    let store: OnboardingStore

    /// Shown after a tap on a faded day, until the week changes.
    @State private var showsFullHint = false

    private let days = V1TrainingAvailability.weekdaysMondayFirst

    private var picked: [Int] { store.availability.availableWeekdays }
    private var isFull: Bool { picked.count >= store.sessionsPerWeek }

    var body: some View {
        VStack(alignment: .leading, spacing: SharpitSpacing.lg) {
            VStack(spacing: SharpitSpacing.sm) {
                ForEach(TrainingIntensity.allCases) { intensity in
                    MotivationRow(
                        symbol: intensity.symbolName,
                        title: intensity.label,
                        detail: "\(intensity.detail) \(Self.sessionsLabel(intensity.idealSessions))",
                        isSelected: store.availability.intensity == intensity
                    ) {
                        SharpitMotion.run(SharpitMotion.selection) { store.setIntensity(intensity) }
                    }
                }
            }

            if store.availability.intensity != nil {
                Stepper(
                    value: Binding(get: { store.sessionsPerWeek }, set: { store.setSessionsPerWeek($0) }),
                    in: 1...7
                ) {
                    HStack(alignment: .firstTextBaseline, spacing: SharpitSpacing.xs) {
                        Text("\(store.sessionsPerWeek)")
                            .font(SharpitTypography.gaugeScore)
                            .tracking(SharpitTypography.gaugeScoreTracking)
                            .foregroundStyle(SharpitColor.foreground)
                            .contentTransition(.numericText(value: Double(store.sessionsPerWeek)))
                        Text(store.sessionsPerWeek == 1 ? String(localized: "séance par semaine") : String(localized: "séances par semaine"))
                            .font(SharpitTypography.bodyEmphasis)
                            .foregroundStyle(SharpitColor.mutedForeground)
                    }
                }
                .padding(SharpitSpacing.cardPadding)
                .sharpitSurface(.panel)

                week
                    .transition(.opacity)
            }
        }
        .animation(SharpitMotion.selection, value: store.availability)
        .onChange(of: store.availability) { showsFullHint = false }
    }

    private static func sessionsLabel(_ count: Int) -> String {
        String(localized: "Environ \(count) séances par semaine.")
    }

    private var week: some View {
        VStack(alignment: .leading, spacing: SharpitSpacing.sm) {
            HStack(alignment: .center) {
                SharpitFieldLabel(String(localized: "Tes jours"))
                Spacer(minLength: SharpitSpacing.xs)
                tokens
            }
            HStack(spacing: SharpitSpacing.xxs) {
                ForEach(days, id: \.self) { day in
                    dayKey(day)
                }
            }
            if showsFullHint {
                Text("Retire un jour pour en choisir un autre.")
                    .font(SharpitTypography.meta)
                    .foregroundStyle(SharpitColor.mutedForeground)
                    .transition(.opacity)
            }
        }
        .padding(SharpitSpacing.cardPadding)
        .sharpitSurface(.panel)
    }

    /// One token per session, filled as it finds its day.
    private var tokens: some View {
        HStack(spacing: 4) {
            ForEach(0..<store.sessionsPerWeek, id: \.self) { index in
                Capsule()
                    .fill(index < picked.count ? SharpitColor.highlight : SharpitColor.analysisSurfaceAlt)
                    .frame(width: 14, height: 6)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(String(localized: "Tes jours : \(picked.count) sur \(store.sessionsPerWeek)"))
    }

    /// The weekday letter, then its key: a lime disc with the session's number when chosen, a
    /// ring when free, faded once every session has its day.
    private func dayKey(_ day: Int) -> some View {
        let order = picked.firstIndex(of: day).map { $0 + 1 }
        let isFaded = order == nil && isFull
        return Button {
            if order == nil, isFull {
                SharpitMotion.run(SharpitMotion.selection) { showsFullHint = true }
            } else {
                SharpitMotion.run(SharpitMotion.selection) { store.toggleWeekday(day) }
            }
        } label: {
            VStack(spacing: SharpitSpacing.xxs) {
                Text(OnboardingWeekday.shortLabels[day].prefix(1))
                    .font(SharpitTypography.label)
                    .tracking(SharpitTypography.labelTracking)
                    .foregroundStyle(SharpitColor.mutedForeground)
                ZStack {
                    Circle()
                        .fill(order == nil ? Color.clear : SharpitColor.highlight)
                    Circle()
                        .strokeBorder(SharpitColor.analysisGrid, lineWidth: order == nil ? 1.5 : 0)
                    if let order {
                        Text("\(order)")
                            .font(SharpitTypography.instrument)
                            .foregroundStyle(SharpitColor.highlightForeground)
                            .transition(.scale(scale: 0.6).combined(with: .opacity))
                    }
                }
                .frame(width: 40, height: 40)
            }
            .frame(maxWidth: .infinity, minHeight: SharpitSpacing.minimumTouchTarget)
            .contentShape(.rect)
            .opacity(isFaded ? 0.35 : 1)
        }
        .buttonStyle(.sharpitPressable)
        .accessibilityLabel(OnboardingWeekday.label(day))
        .accessibilityValue(order.map { String(localized: "séance \($0)") } ?? String(localized: "repos"))
        .accessibilityAddTraits(order == nil ? .isButton : [.isButton, .isSelected])
    }
}

// MARK: - Goal

/// A race with its date, a figure to reach, or simply keeping fit. The time left is read live, so the athlete sees
/// what the plan has to work with. Race formats come from the ADR-082 catalog.
struct OnboardingGoalStep: View {
    @Binding var draft: OnboardingIntentionDraft
    /// Practiced sports — filters which race disciplines are offered.
    var sports: Set<String> = []
    /// Strength alone has no race: a palier or keeping fit.
    var isStrengthOnly = false

    private var disciplines: [RaceDiscipline] { RaceDiscipline.offered(for: sports) }

    private var formats: [RaceFormatEntry] {
        guard let discipline = draft.discipline else { return [] }
        return RaceFormatCatalog.formats(for: discipline)
    }

    private var weeksLeft: Int {
        max(Calendar.current.dateComponents([.weekOfYear], from: .now, to: draft.raceDate).weekOfYear ?? 0, 0)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: SharpitSpacing.md) {
            VStack(spacing: SharpitSpacing.sm) {
                ForEach(offeredKinds) { kind in
                    MotivationRow(
                        symbol: kind.symbolName,
                        title: kind.label,
                        detail: kind.detail,
                        isSelected: draft.kind == kind
                    ) {
                        SharpitMotion.run(SharpitMotion.selection) { draft.kind = kind }
                    }
                }
            }

            switch draft.kind {
            case .race:
                if disciplines.count > 1 {
                    SharpitSelectField(
                        title: String(localized: "Discipline"),
                        placeholder: String(localized: "Choisir"),
                        selection: disciplineSelection,
                        options: disciplines.map { ($0, $0.label) }
                    )
                }

                // A single catalog entry is auto-selected — no need to list it.
                if formats.count > 1 {
                    SharpitSelectField(
                        title: String(localized: "Format"),
                        placeholder: String(localized: "Choisir"),
                        selection: formatSelection,
                        options: formats.map { ($0.key, $0.label) }
                    )
                }

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
                        Text(weeksLeft == 1 ? String(localized: "semaine de préparation") : String(localized: "semaines de préparation"))
                            .font(SharpitTypography.bodyEmphasis)
                            .foregroundStyle(SharpitColor.mutedForeground)
                    }
                    .animation(SharpitMotion.selection, value: weeksLeft)
                }
                .padding(SharpitSpacing.cardPadding)
                .sharpitSurface(.panel)

                SharpitFormField(
                    String(localized: "Nom personnalisé (optionnel)"),
                    placeholder: draft.selectedFormat?.label ?? String(localized: "Marathon de Paris…"),
                    text: $draft.raceTitle
                )
                SharpitFormField(String(localized: "Objectif visé (optionnel)"), placeholder: String(localized: "Terminer, sub 5 h…"), text: $draft.targetPerformance)
                OnboardingPlaceField(title: String(localized: "Lieu (optionnel)"), text: $draft.raceLocation)
            case .metric:
                SharpitFormField(
                    String(localized: "Ce que tu veux atteindre"),
                    placeholder: isStrengthOnly ? String(localized: "Squat, développé couché, tractions…") : String(localized: "FTP, VMA, allure 10 km…"),
                    text: $draft.metricTitle
                )
                HStack(spacing: SharpitSpacing.sm) {
                    SharpitFormField(String(localized: "Valeur"), placeholder: isStrengthOnly ? "100" : "280", text: $draft.metricTargetText, keyboard: .decimalPad)
                    SharpitFormField(String(localized: "Unité"), placeholder: isStrengthOnly ? String(localized: "kg, reps…") : "W, km/h…", text: $draft.metricUnit)
                }
            case .habit:
                EmptyView()
            }
        }
        .animation(SharpitMotion.selection, value: draft.kind)
        .animation(SharpitMotion.selection, value: draft.discipline)
        .onAppear(perform: seedDisciplineIfNeeded)
    }

    /// Strength alone has no race to run.
    private var offeredKinds: [OnboardingIntentionKind] {
        isStrengthOnly ? [.metric, .habit] : OnboardingIntentionKind.allCases
    }

    private var disciplineSelection: Binding<RaceDiscipline?> {
        Binding(
            get: { draft.discipline },
            set: { next in
                guard let next else { return }
                SharpitMotion.run(SharpitMotion.selection) {
                    draft.discipline = next
                    if RaceFormatCatalog.entry(key: draft.formatKey)?.discipline != next {
                        draft.formatKey = RaceFormatCatalog.formats(for: next).first?.key ?? ""
                    }
                }
            }
        )
    }

    private var formatSelection: Binding<String?> {
        Binding(
            get: { draft.formatKey.isEmpty ? nil : draft.formatKey },
            set: { next in
                SharpitMotion.run(SharpitMotion.selection) {
                    draft.formatKey = next ?? ""
                }
            }
        )
    }

    private func seedDisciplineIfNeeded() {
        guard draft.kind == .race else { return }
        if draft.discipline == nil, let preferred = RaceDiscipline.preferred(for: sports) {
            draft.discipline = preferred
        }
        if let discipline = draft.discipline {
            let available = RaceFormatCatalog.formats(for: discipline)
            if draft.formatKey.isEmpty || RaceFormatCatalog.entry(key: draft.formatKey)?.discipline != discipline {
                draft.formatKey = available.first?.key ?? ""
            }
        }
    }
}

// MARK: - Injuries

/// The body step: what was declared first, then the silhouette — touching a zone opens its
/// questions in a sheet, its side taken from where the finger landed — then the health grounds,
/// conditions with no zone, each asked where the athlete is with it (SHARPIT ADR-124).
struct OnboardingInjuriesStep: View {
    let store: OnboardingStore
    @State private var editing: OnboardingInjuryDraft?
    @State private var editingGround: HealthGroundCatalog.Entry?
    @State private var face: SensitiveZoneBody.Face = .front

    private var figure: SensitiveZoneFigure { SensitiveZoneFigure(sex: store.identity.sex) }

    var body: some View {
        VStack(alignment: .leading, spacing: SharpitSpacing.lg) {
            if !store.injuries.isEmpty {
                VStack(spacing: SharpitSpacing.xs) {
                    ForEach(store.injuries) { injury in
                        OnboardingInjuryRow(injury: injury) {
                            editing = injury
                        } onRemove: {
                            store.removeInjury(injury.bodyPart)
                        }
                    }
                }
            }

            VStack(spacing: SharpitSpacing.sm) {
                SharpitFieldLabel(String(localized: "Touche la zone concernée"))
                    .frame(maxWidth: .infinity, alignment: .leading)
                SharpitSegmentedControl(
                    selection: $face,
                    options: [
                        .init(value: .front, label: String(localized: "Face")),
                        .init(value: .back, label: String(localized: "Dos")),
                    ]
                )
                SensitiveZoneBodyMap(
                    face: face,
                    spots: SensitiveZoneBody.spots(on: face, offered: OnboardingInjuryDraft.bodyParts, figure: figure),
                    tint: { spot in isDeclared(spot) ? SharpitColor.highlight : nil },
                    onTap: open,
                    height: 400,
                    figure: figure
                )
                .frame(maxWidth: .infinity)
            }

            groundsBlock
        }
        .sheet(item: $editing) { draft in
            OnboardingZoneSheet(
                draft: draft,
                isDeclared: store.injuries.contains { $0.id == draft.id }
            ) { saved in
                store.saveInjury(saved)
            } onRemove: {
                store.removeInjury(draft.bodyPart)
            }
            .sharpitSheet()
        }
        .sheet(item: $editingGround) { entry in
            HealthGroundSheet(
                entry: entry,
                declared: store.healthGrounds.first { $0.key == entry.key }
            ) { saved in
                store.saveHealthGround(saved)
            } onRemove: {
                store.removeHealthGround(entry.key)
            }
            .sharpitSheet()
        }
    }

    /// One row per ground: its stage once declared, a chevron to open its question.
    private var groundsBlock: some View {
        VStack(alignment: .leading, spacing: SharpitSpacing.sm) {
            SharpitFieldLabel(String(localized: "Un terrain à ménager ?"))
            VStack(spacing: 0) {
                let entries = HealthGroundCatalog.entries(for: store.identity.sex)
                ForEach(Array(entries.enumerated()), id: \.element.id) { index, entry in
                    groundRow(entry)
                    if index < entries.count - 1 {
                        Rectangle().fill(SharpitColor.analysisGrid).frame(height: 1).padding(.leading, 56)
                    }
                }
            }
            .padding(.vertical, SharpitSpacing.xs)
            .padding(.horizontal, SharpitSpacing.sm)
            .sharpitSurface(.panel)
        }
    }

    private func groundRow(_ entry: HealthGroundCatalog.Entry) -> some View {
        let declared = store.healthGrounds.first { $0.key == entry.key }
        return Button {
            editingGround = entry
        } label: {
            HStack(spacing: SharpitSpacing.sm) {
                SharpitIconTile(symbol: entry.symbolName, size: 36)
                VStack(alignment: .leading, spacing: 2) {
                    Text(entry.label)
                        .font(SharpitTypography.bodyEmphasis)
                        .foregroundStyle(SharpitColor.foreground)
                    if let declared {
                        Text(declared.details ?? entry.stage(declared.stage)?.label ?? "")
                            .font(SharpitTypography.meta)
                            .foregroundStyle(SharpitColor.mutedForeground)
                            .lineLimit(1)
                    }
                }
                Spacer(minLength: SharpitSpacing.xs)
                if declared != nil {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(SharpitColor.highlightForeground, SharpitColor.highlight)
                        .accessibilityHidden(true)
                }
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(SharpitColor.mutedForeground.opacity(0.6))
                    .accessibilityHidden(true)
            }
            .padding(.vertical, SharpitSpacing.sm)
            .contentShape(.rect)
        }
        .buttonStyle(.sharpitPressable)
        .accessibilityValue(declared.flatMap { entry.stage($0.stage)?.label } ?? "")
        .accessibilityAddTraits(declared == nil ? .isButton : [.isButton, .isSelected])
    }

    private func isDeclared(_ spot: SensitiveZoneBody.Spot) -> Bool {
        guard let injury = store.injuries.first(where: { $0.bodyPart == spot.part }) else { return false }
        return SensitiveZoneBody.isSelected(spot, part: injury.bodyPart, side: injury.side?.rawValue ?? "NA")
    }

    /// A declared zone opens as declared; a new one starts on the side touched.
    private func open(_ spot: SensitiveZoneBody.Spot) {
        SharpitHaptics.play(.notch(major: false))
        editing = store.injuries.first { $0.bodyPart == spot.part }
            ?? OnboardingInjuryDraft(bodyPart: spot.part, side: OnboardingInjuryDraft.Side(rawValue: spot.side.rawValue))
    }
}

private struct OnboardingInjuryRow: View {
    let injury: OnboardingInjuryDraft
    let onEdit: () -> Void
    let onRemove: () -> Void

    @State private var offset: CGFloat = 0
    @State private var isRevealed = false
    @State private var hasPassedDeleteThreshold = false

    private let buttonWidth: CGFloat = 76
    private let deleteThreshold: CGFloat = -136

    private var subtitle: String {
        guard let kind = injury.kind else { return "" }
        guard injury.asksForState else { return kind.label }
        var parts = [kind.label]
        if let pain = injury.pain { parts.append(String(localized: "\(pain)/10")) }
        if let onset = injury.onset { parts.append(onset.label.lowercased()) }
        return parts.joined(separator: " · ")
    }

    private var severityColor: Color { ZoneSeverityTint.color(injury.asksForState ? injury.pain : nil) }

    var body: some View {
        ZStack(alignment: .trailing) {
            // Delete action surface revealed on swipe
            deleteBackground

            // Discreet front card
            cardContent
                .offset(x: offset)
                .simultaneousGesture(dragGesture)
        }
        .clipShape(RoundedRectangle(cornerRadius: SharpitSpacing.cardRadius, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(injury.title). \(subtitle)")
        .accessibilityHint(String(localized: "Touchez pour modifier, balayez vers la gauche pour supprimer."))
        .accessibilityAction(named: String(localized: "Supprimer")) {
            triggerRemove()
        }
    }

    private var deleteBackground: some View {
        Button {
            triggerRemove()
        } label: {
            ZStack {
                Rectangle()
                    .fill(SharpitColor.destructive)

                HStack {
                    Spacer()
                    VStack(spacing: SharpitSpacing.xxs) {
                        Image(systemName: "trash.fill")
                            .font(.system(size: 16, weight: .semibold))
                        Text(String(localized: "Supprimer"))
                            .font(.system(size: 11, weight: .semibold))
                    }
                    .foregroundStyle(SharpitColor.destructiveForeground)
                    .frame(width: buttonWidth)
                    .scaleEffect(hasPassedDeleteThreshold ? 1.15 : 1.0)
                    .animation(.spring(response: 0.25, dampingFraction: 0.75), value: hasPassedDeleteThreshold)
                }
            }
        }
        .buttonStyle(.plain)
    }

    private var cardContent: some View {
        HStack(alignment: .center, spacing: SharpitSpacing.sm) {
            Circle()
                .fill(severityColor)
                .frame(width: 8, height: 8)

            VStack(alignment: .leading, spacing: 3) {
                Text(injury.title.prefix(1).uppercased() + injury.title.dropFirst())
                    .font(SharpitTypography.bodyEmphasis)
                    .foregroundStyle(SharpitColor.foreground)
                    .lineLimit(1)

                Text(subtitle)
                    .font(SharpitTypography.meta)
                    .foregroundStyle(SharpitColor.mutedForeground)
                    .lineLimit(1)
            }

            Spacer(minLength: SharpitSpacing.xs)

            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(SharpitColor.mutedForeground.opacity(0.35))
        }
        .padding(.horizontal, SharpitSpacing.md)
        .padding(.vertical, SharpitSpacing.sm + 2)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: SharpitSpacing.cardRadius, style: .continuous)
                .fill(SharpitColor.card)
        )
        .overlay(
            RoundedRectangle(cornerRadius: SharpitSpacing.cardRadius, style: .continuous)
                .strokeBorder(SharpitColor.border.opacity(0.7), lineWidth: 1)
        )
        .contentShape(.rect)
        .onTapGesture {
            if isRevealed {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
                    offset = 0
                    isRevealed = false
                }
            } else {
                onEdit()
            }
        }
    }

    private var dragGesture: some Gesture {
        DragGesture(minimumDistance: 10, coordinateSpace: .local)
            .onChanged { value in
                let translationX = value.translation.width
                // Only track horizontal gestures
                if abs(translationX) < abs(value.translation.height) && abs(offset) < 2 {
                    return
                }

                if isRevealed {
                    let proposed = -buttonWidth + translationX
                    if proposed > 0 {
                        // Rubber-band resistance towards the right past 0
                        offset = proposed * 0.15
                    } else {
                        offset = proposed
                    }
                } else {
                    if translationX > 0 {
                        // Rubber-band resistance to the right
                        offset = translationX * 0.15
                    } else {
                        offset = translationX
                    }
                }

                let crossed = offset < deleteThreshold
                if crossed != hasPassedDeleteThreshold {
                    hasPassedDeleteThreshold = crossed
                    SharpitHaptics.play(.notch(major: crossed))
                }
            }
            .onEnded { value in
                let velocityX = value.velocity.width

                if offset < deleteThreshold || velocityX < -550 {
                    // Full swipe to delete
                    triggerRemove()
                } else if offset < -36 || velocityX < -150 {
                    // Snap open to reveal delete button
                    isRevealed = true
                    withAnimation(.spring(response: 0.32, dampingFraction: 0.82)) {
                        offset = -buttonWidth
                    }
                } else {
                    // Snap back closed
                    isRevealed = false
                    withAnimation(.spring(response: 0.32, dampingFraction: 0.82)) {
                        offset = 0
                    }
                }
                hasPassedDeleteThreshold = false
            }
    }

    private func triggerRemove() {
        SharpitHaptics.play(.notch(major: true))
        withAnimation(.spring(response: 0.28, dampingFraction: 0.88)) {
            offset = -400
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) {
            withAnimation(SharpitMotion.reveal) {
                onRemove()
            }
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

            SharpitEyebrow(String(localized: "Optionnel"))
            VStack(alignment: .leading, spacing: 0) {
                ConsentCheckRow(isOn: $consents.ai) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("J'autorise le traitement par IA.")
                        Text("Le coach, les bilans rédigés et ta première semaine de séances en dépendent.")
                            .font(SharpitTypography.meta)
                            .foregroundStyle(SharpitColor.mutedForeground)
                    }
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

/// The week the coach planned while the athlete linked their sources.
/// For free athletes, details are locked and a subscription screen is proposed.
struct OnboardingFirstWeekStep: View {
    let store: OnboardingStore
    @Environment(ProStore.self) private var pro: ProStore?

    var body: some View {
        switch store.firstWeek {
        case .idle, .generating:
            generating
        case .ready(let summary, let sessions):
            ready(summary: summary, sessions: sessions)
        case .unavailable:
            note(
                symbol: "calendar.badge.exclamationmark",
                title: String(localized: "Pas de séances générées"),
                detail: String(localized: "Sans le traitement par IA, le coach ne rédige pas de séances. Tu peux l'activer plus tard dans Paramètres › Confidentialité, puis demander ta semaine depuis le Plan.")
            )
        case .failed(let message):
            VStack(alignment: .leading, spacing: SharpitSpacing.md) {
                note(symbol: "exclamationmark.triangle", title: String(localized: "Semaine non préparée"), detail: message)
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
            if pro?.isPro == true {
                HStack(spacing: SharpitSpacing.xs) {
                    Image(systemName: "checkmark.seal.fill")
                        .foregroundStyle(SharpitColor.primary)
                    Text(String(localized: "Semaine débloquée avec SharpIt Pro"))
                        .font(SharpitTypography.meta.weight(.semibold))
                        .foregroundStyle(SharpitColor.primary)
                }
            } else {
                HStack(spacing: SharpitSpacing.xs) {
                    Image(systemName: "sparkles")
                        .foregroundStyle(SharpitColor.primary)
                    Text(String(localized: "Plan personnalisé par ton coach"))
                        .font(SharpitTypography.meta.weight(.semibold))
                        .foregroundStyle(SharpitColor.primary)
                }
            }

            if !summary.isEmpty {
                Text(summary)
                    .font(SharpitTypography.body)
                    .foregroundStyle(SharpitColor.foreground)
                    .lineLimit(4)
            }

            GeneratedWeekView(sessions: sessions)

            ForEach(Array(store.firstWeekSetAside.enumerated()), id: \.offset) { _, entry in
                GeneratedSessionRow(session: entry.session, rejection: entry.reason ?? String(localized: "Écartée par le contrôle de sécurité."))
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

/// Where the readings come from: Apple Health, Strava, Garmin, Withings, Google Calendar, Apple Calendar.
/// Connecting nothing is a valid path: Finaliser is never held back by this step.
struct OnboardingSourcesStep: View {
    let appleHealth: AppleHealthSource
    var appleCalendar: AppleCalendarSource = AppleCalendarSource(client: SharpitClient())
    let tokenProvider: () async throws -> String
    var hasAccount: Bool = true
    var onAccountNeeded: (() -> Void)? = nil
    var oauthHandoffClient: any ProviderOAuthHandoffServing = SharpitClient()
    var syncClient: any SyncServing = SharpitClient()
    var sourcePrefsClient: any SourcePrefsServing = SharpitClient()

    @Environment(\.webAuthenticationSession) private var webAuthenticationSession
    @State private var status: V1SyncStatus?
    @State private var connectingOAuth: DisconnectableSource?
    @State private var errorMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: SharpitSpacing.sm) {
            OnboardingSourceCard(
                provider: .appleHealth,
                title: String(localized: "Apple Santé"),
                detail: appleHealthDetail
            ) {
                Toggle("Apple Santé", isOn: appleHealthBinding)
                    .labelsHidden()
                    .disabled(!appleHealth.isAvailable)
            }

            OnboardingSourceCard(
                provider: .strava,
                title: String(localized: "Strava"),
                detail: String(localized: "Toutes tes sorties GPS, même sans montre.")
            ) {
                oauthControl(for: .strava)
            }

            OnboardingSourceCard(
                provider: .garmin,
                title: String(localized: "Garmin"),
                detail: String(localized: "Séances, sommeil et VFC de ta montre, et tes séances prévues envoyées dessus.")
            ) {
                oauthControl(for: .garmin)
            }

            OnboardingSourceCard(
                provider: .withings,
                title: String(localized: "Withings"),
                detail: String(localized: "Poids et composition corporelle de ta balance.")
            ) {
                oauthControl(for: .withings)
            }

            OnboardingSourceCard(
                provider: .google,
                title: String(localized: "Google Agenda"),
                detail: String(localized: "Créneaux libres et occupés pour tes séances.")
            ) {
                oauthControl(for: .google)
            }

            OnboardingSourceCard(
                provider: .appleCalendar,
                title: String(localized: "Calendrier Apple"),
                detail: String(localized: "Séances dans ton agenda et créneaux occupés.")
            ) {
                Toggle("Calendrier Apple", isOn: appleCalendarBinding)
                    .labelsHidden()
            }

            if let errorMessage {
                HStack(spacing: SharpitSpacing.xs) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(SharpitColor.signalRisk)
                    Text(errorMessage)
                        .font(SharpitTypography.meta)
                        .foregroundStyle(SharpitColor.signalRisk)
                }
                .padding(.horizontal, SharpitSpacing.xxs)
                .transition(.opacity)
            }

            Text("Tout est optionnel et se règle plus tard dans Paramètres › Sources.")
                .font(SharpitTypography.meta)
                .foregroundStyle(SharpitColor.mutedForeground)
                .padding(.horizontal, SharpitSpacing.xxs)
                .padding(.top, SharpitSpacing.xxs)
        }
        .task { await loadStatus() }
    }

    private func isOAuthConnected(_ source: DisconnectableSource) -> Bool {
        status?.providers.contains(where: { $0.key == source.statusKey }) ?? false
    }

    @ViewBuilder
    private func oauthControl(for source: DisconnectableSource) -> some View {
        if connectingOAuth == source {
            ProgressView()
                .frame(width: 44, height: 28)
        } else if isOAuthConnected(source) {
            SharpitPill(String(localized: "Connecté"), style: .lime)
        } else {
            Button {
                if !hasAccount {
                    onAccountNeeded?()
                } else {
                    Task { await connectOAuth(source) }
                }
            } label: {
                SharpitPill(String(localized: "Connecter"), style: .neutral)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Connecter \(source.name)")
        }
    }

    private func connectOAuth(_ source: DisconnectableSource) async {
        guard connectingOAuth == nil else { return }
        connectingOAuth = source
        errorMessage = nil
        defer { connectingOAuth = nil }
        let outcome = await ProviderOAuthConnect.run(
            source: source,
            client: oauthHandoffClient,
            tokenProvider: tokenProvider,
            authenticate: webAuthenticationSession.providerOAuthConnect
        )
        if outcome.isLinked {
            await loadStatus()
        } else if outcome != .cancelled {
            errorMessage = outcome.message(for: source)
        }
    }

    private func loadStatus() async {
        guard let token = try? await tokenProvider() else { return }
        status = try? await syncClient.syncStatus(token: token)
        if let prefs = try? await sourcePrefsClient.sourcePrefs(token: token) {
            appleCalendar.syncLinkedFromServer(prefs.connected.contains(AppleCalendarSync.providerId))
        }
    }

    private var appleHealthDetail: String {
        let line = ConnectionsReadout.appleHealthSubtitle(isAvailable: appleHealth.isAvailable, state: appleHealth.state)
        return appleHealth.isAvailable && !line.isProblem ? String(localized: "Séances, sommeil, VFC et poids, ceux de ta montre aussi.") : line.text
    }

    private var appleHealthBinding: Binding<Bool> {
        Binding(
            get: { appleHealth.isEnabled },
            set: { on in
                if !hasAccount {
                    onAccountNeeded?()
                    return
                }
                if on {
                    Task { await appleHealth.enable(token: tokenProvider) }
                } else {
                    Task { await appleHealth.disable(token: tokenProvider) }
                }
            }
        )
    }

    private var appleCalendarBinding: Binding<Bool> {
        Binding(
            get: { appleCalendar.isLinked },
            set: { on in
                if !hasAccount {
                    onAccountNeeded?()
                    return
                }
                if on {
                    Task { await appleCalendar.enable(token: tokenProvider) }
                } else {
                    Task { await appleCalendar.disable(token: tokenProvider) }
                }
            }
        )
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
