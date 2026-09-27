import AuthenticationServices
import SwiftUI
import UIKit

// MARK: - Welcome

/// What the next minutes build, in three lines — each a real step, none a promise.
struct OnboardingWelcomeStep: View {
    @State private var shown = 0

    private let lines: [(symbol: String, title: String, detail: String)] = [
        ("figure.run", "Tes sports et ta semaine", "Ce que tu pratiques, avec quoi, et quand."),
        ("flag.checkered", "Ton objectif", "Une course ou un palier vers lequel tout se construit."),
        ("calendar.badge.plus", "Ta première semaine", "Des séances placées sur tes jours, prêtes dans ton plan."),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: SharpitSpacing.md) {
            ForEach(Array(lines.enumerated()), id: \.offset) { index, line in
                HStack(alignment: .top, spacing: SharpitSpacing.md) {
                    ZStack {
                        Circle().fill(SharpitColor.primary.opacity(0.12)).frame(width: 40, height: 40)
                        Image(systemName: line.symbol)
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundStyle(SharpitColor.primary)
                            .symbolEffect(.bounce.up, value: shown > index)
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text(line.title)
                            .font(SharpitTypography.cardTitle)
                            .tracking(SharpitTypography.cardTitleTracking)
                            .foregroundStyle(SharpitColor.foreground)
                        Text(line.detail)
                            .font(SharpitTypography.body)
                            .foregroundStyle(SharpitColor.mutedForeground)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .opacity(shown > index ? 1 : 0.25)
            }
        }
        .task {
            for index in lines.indices {
                try? await Task.sleep(for: .milliseconds(SharpitMotion.reduceMotion ? 0 : 280))
                SharpitMotion.run(SharpitMotion.reveal) { shown = index + 1 }
            }
        }
    }
}

// MARK: - Sports

/// Endurance first, complements after. A tile answers the touch with its own symbol — it
/// bounces and fills — never by growing.
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

    @State private var taps = 0

    var body: some View {
        Button {
            SharpitHaptics.play(isSelected ? .soft : .light)
            taps += 1
            SharpitMotion.run(SharpitMotion.selection) { onToggle() }
        } label: {
            VStack(alignment: .leading, spacing: SharpitSpacing.sm) {
                HStack(alignment: .top) {
                    item.image
                        .symbolVariant(isSelected ? .fill : .none)
                        .font(.system(size: 30, weight: .medium))
                        .foregroundStyle(isSelected ? SharpitColor.primary : SharpitColor.mutedForeground)
                        .contentTransition(.symbolEffect(.replace.downUp.byLayer))
                        .symbolEffect(.bounce.up.byLayer, value: taps)
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
                    .fill(isSelected ? SharpitColor.primary.opacity(0.10) : SharpitColor.analysisSurface)
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
                    OnboardingVenueChip(venue: venue, isSelected: store.strengthVenue == venue) {
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

/// Where strength happens: one choice of four, its symbol filling and bouncing when picked.
private struct OnboardingVenueChip: View {
    let venue: V1AthleteEquipment.StrengthVenue
    let isSelected: Bool
    let onSelect: () -> Void

    var body: some View {
        Button {
            SharpitHaptics.play(.light)
            onSelect()
        } label: {
            HStack(spacing: SharpitSpacing.xs) {
                Image(systemName: venue.symbolName)
                    .symbolVariant(isSelected ? .fill : .none)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(isSelected ? SharpitColor.primary : SharpitColor.mutedForeground)
                    .contentTransition(.symbolEffect(.replace))
                    .symbolEffect(.bounce.up.byLayer, value: isSelected)
                    .frame(width: 22)
                Text(venue.title)
                    .font(SharpitTypography.meta.weight(.semibold))
                    .foregroundStyle(isSelected ? SharpitColor.foreground : SharpitColor.mutedForeground)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, SharpitSpacing.sm)
            .frame(minHeight: SharpitSpacing.minimumTouchTarget)
            .background(
                RoundedRectangle(cornerRadius: SharpitRadius.small, style: .continuous)
                    .fill(isSelected ? SharpitColor.primary.opacity(0.10) : SharpitColor.analysisSurfaceAlt)
            )
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }
}

private struct OnboardingEquipmentRow: View {
    let item: EquipmentCatalogItem
    let isOwned: Bool
    let onToggle: () -> Void

    var body: some View {
        Button {
            SharpitHaptics.play(.light)
            SharpitMotion.run(SharpitMotion.selection) { onToggle() }
        } label: {
            HStack(spacing: SharpitSpacing.sm) {
                Image(systemName: item.symbolName)
                    .font(.system(size: 17, weight: .medium))
                    .foregroundStyle(isOwned ? SharpitColor.primary : SharpitColor.mutedForeground)
                    .symbolEffect(.bounce, value: isOwned)
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
            SharpitHaptics.play(.light)
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
                field("Nom de l'épreuve", placeholder: "Marathon de Paris, 70.3 Nice…", text: $draft.raceTitle)
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
                field("Lieu (optionnel)", placeholder: "Paris, Nice…", text: $draft.raceLocation)
            case .metric:
                field("Ce que tu veux atteindre", placeholder: "FTP, VMA, allure 10 km…", text: $draft.metricTitle)
                HStack(spacing: SharpitSpacing.sm) {
                    field("Valeur", placeholder: "280", text: $draft.metricTargetText, keyboard: .decimalPad)
                    field("Unité", placeholder: "W, km/h…", text: $draft.metricUnit)
                }
            }
        }
        .animation(SharpitMotion.selection, value: draft.kind)
    }

    private func kindCard(_ kind: OnboardingIntentionKind, title: String, symbol: String) -> some View {
        let isSelected = draft.kind == kind
        return Button {
            SharpitHaptics.play(.light)
            SharpitMotion.run(SharpitMotion.selection) { draft.kind = kind }
        } label: {
            HStack(spacing: SharpitSpacing.sm) {
                Image(systemName: symbol)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(isSelected ? SharpitColor.primary : SharpitColor.mutedForeground)
                    .symbolEffect(.bounce, value: isSelected)
                Text(title)
                    .font(SharpitTypography.cardTitle)
                    .foregroundStyle(SharpitColor.foreground)
                Spacer(minLength: 0)
            }
            .padding(SharpitSpacing.md)
            .background(
                RoundedRectangle(cornerRadius: SharpitRadius.panel, style: .continuous)
                    .fill(isSelected ? SharpitColor.primary.opacity(0.10) : SharpitColor.analysisSurface)
            )
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }

    private func field(
        _ title: String,
        placeholder: String,
        text: Binding<String>,
        keyboard: UIKeyboardType = .default
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(SharpitTypography.label)
                .tracking(SharpitTypography.labelTracking)
                .textCase(.uppercase)
                .foregroundStyle(SharpitColor.mutedForeground)
            TextField(placeholder, text: text)
                .font(SharpitTypography.body)
                .foregroundStyle(SharpitColor.foreground)
                .keyboardType(keyboard)
                .submitLabel(.done)
        }
        .padding(SharpitSpacing.cardPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .sharpitSurface(.panel)
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
                    SharpitHaptics.play(.light)
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
        VStack(spacing: SharpitSpacing.md) {
            SharpitTickGauge(score: CGFloat(store.firstWeekProgress * 100))
                .frame(width: 180, height: 180 / SharpitTickGaugeGeometry.aspectRatio)
                .animation(SharpitMotion.gaugeFill, value: store.firstWeekProgress)
            Text("Le coach place tes séances sur tes jours, vers ton objectif.")
                .font(SharpitTypography.body)
                .foregroundStyle(SharpitColor.mutedForeground)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, SharpitSpacing.lg)
    }

    private func ready(summary: String, sessions: [V1GeneratedSession]) -> some View {
        VStack(alignment: .leading, spacing: SharpitSpacing.sm) {
            if !summary.isEmpty {
                Text(summary)
                    .font(SharpitTypography.body)
                    .foregroundStyle(SharpitColor.foreground)
                    .fixedSize(horizontal: false, vertical: true)
            }
            ForEach(Array(sessions.enumerated()), id: \.element.id) { index, session in
                OnboardingSessionRow(session: session)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .animation(SharpitMotion.reveal.delay(SharpitMotion.staggerDelay(index: index)), value: sessions.count)
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

private struct OnboardingSessionRow: View {
    let session: V1GeneratedSession

    private var day: String {
        guard let date = TrainingDayId.date(session.date) else { return session.date }
        return date.sharpitFormatted(.dateTime.weekday(.wide).day()).capitalized
    }

    var body: some View {
        HStack(spacing: SharpitSpacing.sm) {
            ZStack {
                Circle().fill(SharpitSportTone.label(for: session.type).opacity(0.14)).frame(width: 38, height: 38)
                Image(systemName: session.type.symbolName)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(SharpitSportTone.label(for: session.type))
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(day)
                    .font(SharpitTypography.label)
                    .tracking(SharpitTypography.labelTracking)
                    .textCase(.uppercase)
                    .foregroundStyle(SharpitColor.mutedForeground)
                Text(session.title)
                    .font(SharpitTypography.bodyEmphasis)
                    .foregroundStyle(SharpitColor.foreground)
                    .lineLimit(2)
            }
            Spacer(minLength: 0)
            Text("\(Int(session.durationMin)) min")
                .font(SharpitTypography.instrument)
                .foregroundStyle(SharpitColor.foreground)
        }
        .padding(SharpitSpacing.sm + 2)
        .sharpitSurface(.panel)
        .accessibilityElement(children: .combine)
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
                detail: "Activités GPS, fréquence cardiaque, sommeil et charge.",
                isConnected: isConnected("garmin")
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
                detail: appleHealthDetail,
                isConnected: appleHealth.isEnabled
            ) {
                Toggle("Apple Santé", isOn: appleHealthBinding)
                    .labelsHidden()
                    .tint(SharpitColor.primary)
                    .disabled(!appleHealth.isAvailable)
            }
            OnboardingSourceCard(
                provider: .myFitnessPal,
                title: "MyFitnessPal",
                detail: "Ton journal alimentaire, pour que le coach voie ce que tu manges.",
                isConnected: isConnected("myfitnesspal")
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
                SharpitHaptics.play(.light)
                action()
            } label: {
                if isBusy {
                    ProgressView().tint(SharpitColor.primaryForeground)
                } else {
                    Text("Connecter").font(SharpitTypography.meta.weight(.semibold))
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

/// One source in the sources step: its logo, what it brings, and its control. Connected, the
/// logo takes the brand tint's wash so the linked ones read at a glance.
private struct OnboardingSourceCard<Control: View>: View {
    let provider: ProviderLogo.Provider
    let title: String
    let detail: String
    let isConnected: Bool
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
        .background(
            RoundedRectangle(cornerRadius: SharpitRadius.panel, style: .continuous)
                .fill(isConnected ? SharpitColor.primary.opacity(0.08) : SharpitColor.analysisSurface)
        )
        .animation(SharpitMotion.selection, value: isConnected)
        .accessibilityElement(children: .contain)
    }
}
