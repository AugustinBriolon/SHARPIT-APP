import SwiftUI
import UIKit

private let tileColumns = [
    GridItem(.flexible(), spacing: SharpitSpacing.sm),
    GridItem(.flexible(), spacing: SharpitSpacing.sm),
]

// MARK: - Sports

/// Endurance first, complements after — the same tiles as Moi → Sports & équipement.
struct OnboardingSportsStep: View {
    let store: OnboardingStore

    @State private var hasAppeared = false

    var body: some View {
        VStack(alignment: .leading, spacing: SharpitSpacing.lg) {
            group(
                title: "Sports d'endurance",
                caption: "Au moins un — oriente les objectifs et les plans.",
                items: PracticedSportCatalog.endurance,
                firstIndex: 0
            )
            group(
                title: "Pratiques complémentaires",
                caption: "Pour le renforcement, la mobilité et la prévention.",
                items: PracticedSportCatalog.complementary,
                firstIndex: PracticedSportCatalog.endurance.count
            )
        }
        .onAppear { hasAppeared = true }
    }

    /// Tiles land one after another — the stagger is capped, so the last ones do not wait.
    private func group(
        title: String,
        caption: String,
        items: [PracticedSportItem],
        firstIndex: Int
    ) -> some View {
        VStack(alignment: .leading, spacing: SharpitSpacing.sm) {
            OnboardingSectionHeading(title: title, caption: caption)
            LazyVGrid(columns: tileColumns, spacing: SharpitSpacing.sm) {
                ForEach(Array(items.enumerated()), id: \.element.id) { offset, item in
                    PracticedSportTile(item: item, isSelected: store.sports.contains(item.id)) {
                        SharpitHaptics.play(.light)
                        SharpitMotion.run(SharpitMotion.selection) { store.toggleSport(item.id) }
                    }
                    .revealed(hasAppeared, index: firstIndex + offset + 1)
                }
            }
        }
    }
}

// MARK: - Equipment

/// Only the kit the chosen sports use: triathlon opens its three legs, and strength asks where
/// the athlete trains before listing what they own.
struct OnboardingEquipmentStep: View {
    let store: OnboardingStore

    var body: some View {
        VStack(alignment: .leading, spacing: SharpitSpacing.lg) {
            ForEach(store.equipmentSports) { sport in
                VStack(alignment: .leading, spacing: SharpitSpacing.sm) {
                    Label(sport.label, systemImage: sport.symbolName)
                        .font(SharpitTypography.cardTitle)
                        .foregroundStyle(SharpitColor.foreground)

                    if sport == .strength {
                        venuePicker
                    }

                    let items = EquipmentCatalog.items(for: sport, venue: store.strengthVenue)
                    if items.isEmpty {
                        Text("Aucun équipement spécifique requis pour ce mode de renforcement.")
                            .font(SharpitTypography.meta)
                            .foregroundStyle(SharpitColor.mutedForeground)
                    } else {
                        ForEach(items) { item in
                            EquipmentItemTile(item: item, isOwned: store.ownedEquipment.contains(item.id)) {
                                SharpitHaptics.play(.light)
                                SharpitMotion.run(SharpitMotion.selection) { store.toggleEquipment(item.id) }
                            }
                        }
                    }
                }
            }
        }
    }

    private var venuePicker: some View {
        VStack(alignment: .leading, spacing: SharpitSpacing.xs) {
            Picker("Lieu principal de renforcement", selection: venueBinding) {
                ForEach(V1AthleteEquipment.StrengthVenue.allCases) { venue in
                    Text(venue.title).tag(venue)
                }
            }
            .pickerStyle(.segmented)

            Text(store.strengthVenue.description)
                .font(SharpitTypography.meta)
                .foregroundStyle(SharpitColor.mutedForeground)
        }
    }

    private var venueBinding: Binding<V1AthleteEquipment.StrengthVenue> {
        Binding(
            get: { store.strengthVenue },
            set: { venue in SharpitMotion.run(SharpitMotion.selection) { store.setStrengthVenue(venue) } }
        )
    }
}

// MARK: - Availability

/// The days the athlete can really train, Monday first. Each day picked counts as one possible
/// session; nothing picked declares nothing, and the coach reads the days it observes instead.
struct OnboardingAvailabilityStep: View {
    let store: OnboardingStore

    @State private var hasAppeared = false

    var body: some View {
        VStack(alignment: .leading, spacing: SharpitSpacing.md) {
            OnboardingSectionHeading(
                title: "Jours disponibles",
                caption: "Indique les jours où tu as du temps pour t'entraîner."
            )

            HStack(spacing: SharpitSpacing.xxs + 1) {
                ForEach(Array(V1TrainingAvailability.weekdaysMondayFirst.enumerated()), id: \.element) { offset, day in
                    dayTile(day)
                        .revealed(hasAppeared, index: offset + 1)
                }
            }
            .onAppear { hasAppeared = true }

            availabilityFeedback
                .revealed(hasAppeared, index: 8)
        }
    }

    private func dayTile(_ day: Int) -> some View {
        let isOn = store.availability.availableWeekdays.contains(day)
        return Button {
            SharpitHaptics.play(.light)
            SharpitMotion.run(SharpitMotion.selection) { store.toggleWeekday(day) }
        } label: {
            VStack(spacing: 5) {
                Text(OnboardingWeekday.shortLabels[day])
                    .font(SharpitTypography.bodyEmphasis)
                Circle()
                    .fill(isOn ? SharpitColor.primary : Color.clear)
                    .frame(width: 5, height: 5)
            }
            .frame(maxWidth: .infinity, minHeight: 58)
            .foregroundStyle(isOn ? SharpitColor.foreground : SharpitColor.mutedForeground)
            .background(
                RoundedRectangle(cornerRadius: SharpitRadius.small, style: .continuous)
                    .fill(isOn ? SharpitColor.primary.opacity(0.18) : SharpitColor.card.opacity(0.6))
            )
            .overlay(
                RoundedRectangle(cornerRadius: SharpitRadius.small, style: .continuous)
                    .strokeBorder(isOn ? SharpitColor.primary : SharpitColor.border.opacity(0.4), lineWidth: isOn ? 1.5 : 1)
            )
        }
        .scaleEffect(isOn ? 1 : 0.98)
        .buttonStyle(.sharpitPressable)
        .accessibilityLabel(OnboardingWeekday.label(day))
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }

    private var availabilityFeedback: some View {
        HStack(spacing: SharpitSpacing.sm) {
            Image(systemName: store.availability.availableWeekdays.isEmpty ? "calendar" : "calendar.badge.clock")
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(store.availability.availableWeekdays.isEmpty ? SharpitColor.mutedForeground : SharpitColor.primary)
                .frame(width: 32)

            VStack(alignment: .leading, spacing: 2) {
                if let reading = OnboardingWeekday.reading(store.availability) {
                    Text(reading)
                        .font(SharpitTypography.bodyEmphasis)
                        .foregroundStyle(SharpitColor.foreground)
                    Text("Le coach ajustera le volume hebdomadaire à ces créneaux.")
                        .font(SharpitTypography.meta)
                        .foregroundStyle(SharpitColor.mutedForeground)
                } else {
                    Text("Semaine libre")
                        .font(SharpitTypography.bodyEmphasis)
                        .foregroundStyle(SharpitColor.foreground)
                    Text("Tu pourras placer tes séances au feeling ou le définir plus tard.")
                        .font(SharpitTypography.meta)
                        .foregroundStyle(SharpitColor.mutedForeground)
                }
            }
            Spacer()
        }
        .padding(SharpitSpacing.cardPadding)
        .sharpitSurface(.panel)
        .animation(SharpitMotion.selection, value: store.availability.availableWeekdays)
    }
}

// MARK: - Intention

/// A first goal in a few fields — a race with its date, or a figure to reach. Everything else
/// (format, chrono, notes) is completed later from the goal itself.
struct OnboardingIntentionStep: View {
    @Binding var draft: OnboardingIntentionDraft

    var body: some View {
        VStack(alignment: .leading, spacing: SharpitSpacing.md) {
            HStack(spacing: SharpitSpacing.sm) {
                goalKindCard(
                    kind: .race,
                    title: "Une course",
                    subtitle: "Objectif compétition",
                    symbol: "flag.checkered"
                )
                goalKindCard(
                    kind: .metric,
                    title: "Un palier",
                    subtitle: "Objectif chiffré",
                    symbol: "gauge.with.needle"
                )
            }

            VStack(spacing: SharpitSpacing.xs) {
                switch draft.kind {
                case .race:
                    inputField(
                        title: "Nom de l'épreuve",
                        placeholder: "Ex: Marathon de Paris, UTMB, 70.3…",
                        symbol: "trophy",
                        text: $draft.raceTitle
                    )

                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Label("Date de la course", systemImage: "calendar")
                                .font(SharpitTypography.cardTitle)
                                .foregroundStyle(SharpitColor.foreground)
                            Spacer()
                            DatePicker(
                                "",
                                selection: $draft.raceDate,
                                in: Date()...,
                                displayedComponents: .date
                            )
                            .labelsHidden()
                        }
                    }
                    .padding(SharpitSpacing.cardPadding)
                    .sharpitSurface(.panel)

                    inputField(
                        title: "Lieu (optionnel)",
                        placeholder: "Ex: Paris, Nice…",
                        symbol: "mappin.and.ellipse",
                        text: $draft.raceLocation
                    )

                case .metric:
                    inputField(
                        title: "Métrique cible",
                        placeholder: "Ex: FTP vélo, VMA, Allure 10k…",
                        symbol: "target",
                        text: $draft.metricTitle
                    )

                    HStack(spacing: SharpitSpacing.sm) {
                        inputField(
                            title: "Valeur",
                            placeholder: "280",
                            symbol: "number",
                            text: $draft.metricTargetText,
                            keyboard: .decimalPad
                        )
                        inputField(
                            title: "Unité",
                            placeholder: "W, km/h…",
                            symbol: "chart.bar",
                            text: $draft.metricUnit
                        )
                    }
                }
            }
            .animation(SharpitMotion.selection, value: draft.kind)
        }
    }

    private func goalKindCard(
        kind: OnboardingIntentionKind,
        title: String,
        subtitle: String,
        symbol: String
    ) -> some View {
        let isSelected = draft.kind == kind
        return Button {
            SharpitHaptics.play(.light)
            SharpitMotion.run(SharpitMotion.selection) {
                draft.kind = kind
            }
        } label: {
            HStack(spacing: SharpitSpacing.xs) {
                Image(systemName: symbol)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(isSelected ? SharpitColor.primary : SharpitColor.mutedForeground)
                    .frame(width: 28)

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(SharpitTypography.cardTitle)
                        .foregroundStyle(SharpitColor.foreground)
                    Text(subtitle)
                        .font(SharpitTypography.meta)
                        .foregroundStyle(SharpitColor.mutedForeground)
                }
                Spacer()
            }
            .padding(SharpitSpacing.cardPadding)
            .background(
                RoundedRectangle(cornerRadius: SharpitRadius.panel, style: .continuous)
                    .fill(isSelected ? SharpitColor.primary.opacity(0.12) : SharpitColor.card.opacity(0.6))
            )
            .overlay(
                RoundedRectangle(cornerRadius: SharpitRadius.panel, style: .continuous)
                    .strokeBorder(isSelected ? SharpitColor.primary : SharpitColor.border.opacity(0.4), lineWidth: isSelected ? 1.5 : 1)
            )
        }
        .buttonStyle(.sharpitPressable)
    }

    private func inputField(
        title: String,
        placeholder: String,
        symbol: String,
        text: Binding<String>,
        keyboard: UIKeyboardType = .default
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(title, systemImage: symbol)
                .font(SharpitTypography.meta.weight(.medium))
                .foregroundStyle(SharpitColor.mutedForeground)

            TextField(placeholder, text: text)
                .font(SharpitTypography.body)
                .foregroundStyle(SharpitColor.foreground)
                .keyboardType(keyboard)
                .submitLabel(.done)
        }
        .padding(SharpitSpacing.cardPadding)
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
    var garminClient: any GarminConnecting = SharpitClient()

    @State private var status: V1SyncStatus?
    @State private var showingGarminSheet = false

    var body: some View {
        VStack(alignment: .leading, spacing: SharpitSpacing.md) {
            garminCard
            appleHealthCard

            Text("Optionnel • Ces connexions peuvent être activées ou modifiées à tout moment dans Paramètres → Sources.")
                .font(SharpitTypography.meta)
                .foregroundStyle(SharpitColor.mutedForeground)
                .padding(.horizontal, 4)
                .padding(.top, SharpitSpacing.xxs)
        }
        .task { await loadStatus() }
        .sheet(isPresented: $showingGarminSheet) {
            GarminConnectSheet(
                garminClient: garminClient,
                tokenProvider: tokenProvider
            ) {
                Task { await loadStatus() }
            }
        }
    }

    private var isGarminConnected: Bool {
        status?.providers.contains(where: { $0.key == "garmin" }) ?? false
    }

    private var garminCard: some View {
        Button {
            SharpitHaptics.play(.light)
            showingGarminSheet = true
        } label: {
            HStack(spacing: SharpitSpacing.sm) {
                ProviderLogo(provider: .garmin)

                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: SharpitSpacing.xs) {
                        Text("Garmin Connect")
                            .font(SharpitTypography.cardTitle)
                            .foregroundStyle(SharpitColor.foreground)

                        if isGarminConnected {
                            Label("Connecté", systemImage: "checkmark.circle.fill")
                                .font(SharpitTypography.label)
                                .foregroundStyle(SharpitColor.primary)
                        }
                    }

                    Text("Activités GPS, fréquence cardiaque, sommeil et charge.")
                        .font(SharpitTypography.meta)
                        .foregroundStyle(SharpitColor.mutedForeground)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                }

                Spacer(minLength: SharpitSpacing.xs)

                if isGarminConnected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(SharpitColor.primary)
                } else {
                    Text("Connecter")
                        .font(SharpitTypography.meta.weight(.semibold))
                        .foregroundStyle(SharpitColor.primaryForeground)
                        .padding(.horizontal, SharpitSpacing.sm)
                        .padding(.vertical, 6)
                        .background(SharpitColor.primary, in: Capsule())
                }
            }
            .padding(SharpitSpacing.cardPadding)
            .sharpitSurface(.panel)
            .overlay(
                RoundedRectangle(cornerRadius: SharpitRadius.panel, style: .continuous)
                    .strokeBorder(isGarminConnected ? SharpitColor.primary.opacity(0.4) : Color.clear, lineWidth: 1)
            )
            .contentShape(.rect)
        }
        .buttonStyle(.sharpitPressable)
        .accessibilityHint("Connecter Garmin directement dans l'application")
    }

    private var appleHealthCard: some View {
        let line = ConnectionsReadout.appleHealthSubtitle(
            isAvailable: appleHealth.isAvailable,
            state: appleHealth.state
        )

        return HStack(spacing: SharpitSpacing.sm) {
            ProviderLogo(provider: .appleHealth)

            VStack(alignment: .leading, spacing: 3) {
                Text("Apple Santé")
                    .font(SharpitTypography.cardTitle)
                    .foregroundStyle(SharpitColor.foreground)

                Text("Pas quotidiens, fréquence cardiaque au repos & sommeil.")
                    .font(SharpitTypography.meta)
                    .foregroundStyle(line.isProblem ? SharpitColor.signalRisk : SharpitColor.mutedForeground)
                    .lineLimit(2)
            }

            Spacer(minLength: SharpitSpacing.xs)

            Toggle("", isOn: appleHealthBinding)
                .labelsHidden()
                .tint(SharpitColor.primary)
                .disabled(!appleHealth.isAvailable)
        }
        .padding(SharpitSpacing.cardPadding)
        .sharpitSurface(.panel)
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

    private func loadStatus() async {
        guard let token = try? await tokenProvider() else { return }
        status = try? await syncClient.syncStatus(token: token)
    }
}

// MARK: - Shared

private struct OnboardingSectionHeading: View {
    let title: String
    let caption: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(SharpitTypography.sectionTitle)
                .tracking(SharpitTypography.sectionTitleTracking)
                .foregroundStyle(SharpitColor.foreground)
            Text(caption)
                .font(SharpitTypography.meta)
                .foregroundStyle(SharpitColor.mutedForeground)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
