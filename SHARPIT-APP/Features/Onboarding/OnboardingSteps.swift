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
                caption: "Les jours où tu peux réellement t'entraîner, contraintes pro et perso comprises. Un jour sélectionné compte comme une séance possible."
            )

            HStack(spacing: SharpitSpacing.xxs + 2) {
                ForEach(Array(V1TrainingAvailability.weekdaysMondayFirst.enumerated()), id: \.element) { offset, day in
                    dayTile(day)
                        .revealed(hasAppeared, index: offset + 1)
                }
            }
            .onAppear { hasAppeared = true }

            if let reading = OnboardingWeekday.reading(store.availability) {
                Text(reading)
                    .font(SharpitTypography.meta)
                    .foregroundStyle(SharpitColor.mutedForeground)
                    .contentTransition(.numericText())
                    .transition(.opacity.combined(with: .offset(y: 6)))
            }
        }
    }

    private func dayTile(_ day: Int) -> some View {
        let isOn = store.availability.availableWeekdays.contains(day)
        return Button {
            SharpitHaptics.play(.light)
            SharpitMotion.run(SharpitMotion.selection) { store.toggleWeekday(day) }
        } label: {
            Text(OnboardingWeekday.shortLabels[day])
                .font(SharpitTypography.meta.weight(.medium))
                .frame(maxWidth: .infinity, minHeight: SharpitSpacing.minimumTouchTarget)
                .foregroundStyle(isOn ? SharpitColor.highlightForeground : SharpitColor.foreground)
                .background(
                    RoundedRectangle(cornerRadius: SharpitRadius.small, style: .continuous)
                        .fill(isOn ? SharpitColor.highlight : SharpitColor.card)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: SharpitRadius.small, style: .continuous)
                        .strokeBorder(isOn ? SharpitColor.highlight : SharpitColor.border.opacity(0.6), lineWidth: 1)
                )
        }
        .scaleEffect(isOn ? 1 : 0.97)
        .buttonStyle(.sharpitPressable)
        .accessibilityLabel(OnboardingWeekday.label(day))
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }
}

// MARK: - Intention

/// A first goal in a few fields — a race with its date, or a figure to reach. Everything else
/// (format, chrono, notes) is completed later from the goal itself.
struct OnboardingIntentionStep: View {
    @Binding var draft: OnboardingIntentionDraft

    var body: some View {
        VStack(alignment: .leading, spacing: SharpitSpacing.md) {
            Picker("Type d'objectif", selection: $draft.kind) {
                ForEach(OnboardingIntentionKind.allCases) { kind in
                    Text(kind.label).tag(kind)
                }
            }
            .pickerStyle(.segmented)

            VStack(spacing: 0) {
                switch draft.kind {
                case .race:
                    field("Nom de la course", text: $draft.raceTitle, prompt: "Marathon de Paris")
                    Divider()
                    DatePicker(
                        "Date",
                        selection: $draft.raceDate,
                        in: Date()...,
                        displayedComponents: .date
                    )
                    .font(SharpitTypography.body)
                    .padding(.vertical, SharpitSpacing.xs)
                    Divider()
                    field("Lieu (optionnel)", text: $draft.raceLocation, prompt: "Paris, France")
                case .metric:
                    field("Objectif", text: $draft.metricTitle, prompt: "FTP à 280 W")
                    Divider()
                    field("Valeur cible", text: $draft.metricTargetText, prompt: "280", keyboard: .decimalPad)
                    Divider()
                    field("Unité", text: $draft.metricUnit, prompt: "W, km, min…")
                }
            }
            .padding(.horizontal, SharpitSpacing.cardPadding)
            .sharpitSurface(.panel)
            .animation(SharpitMotion.selection, value: draft.kind)
        }
    }

    private func field(
        _ label: String,
        text: Binding<String>,
        prompt: String,
        keyboard: UIKeyboardType = .default
    ) -> some View {
        LabeledContent(label) {
            TextField(label, text: text, prompt: Text(prompt))
                .keyboardType(keyboard)
                .multilineTextAlignment(.trailing)
                .submitLabel(.done)
        }
        .font(SharpitTypography.body)
        .frame(minHeight: SharpitSpacing.minimumTouchTarget)
        .padding(.vertical, SharpitSpacing.xxs)
    }
}

// MARK: - Sources

/// Where the readings come from. Garmin is connected on the web, where its sign-in lives, as in
/// Moi → Connexions; Apple Health is switched on here, because only the phone can read it.
/// Connecting nothing is a valid path: Finaliser is never held back by this step.
struct OnboardingSourcesStep: View {
    let appleHealth: AppleHealthSource
    let syncClient: any SyncServing
    let tokenProvider: () async throws -> String

    @State private var status: V1SyncStatus?

    var body: some View {
        VStack(alignment: .leading, spacing: SharpitSpacing.sm) {
            garminRow
            appleHealthRow
            Text("Tu pourras tout modifier ensuite dans Paramètres → Sources de données.")
                .font(SharpitTypography.meta)
                .foregroundStyle(SharpitColor.mutedForeground)
                .padding(.top, SharpitSpacing.xxs)
        }
        .task { await loadStatus() }
    }

    private var garminRow: some View {
        let badge = ConnectionsReadout.garmin(status: status)
        return Link(destination: APIConfiguration.baseURL.appending(path: "/settings/integrations")) {
            HStack(spacing: SharpitSpacing.sm) {
                ProviderLogo(provider: .garmin)
                sourceTitle("Garmin", status: badge.text, tone: badge.tone.color)
                Spacer(minLength: SharpitSpacing.xs)
                Image(systemName: "arrow.up.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.tertiary)
                    .accessibilityHidden(true)
            }
            .padding(SharpitSpacing.cardPadding)
            .sharpitSurface(.panel)
            .contentShape(.rect)
        }
        .buttonStyle(.sharpitPressable)
        .foregroundStyle(SharpitColor.foreground)
        .accessibilityHint("Ouvre les intégrations sur le web")
    }

    private var appleHealthRow: some View {
        let line = ConnectionsReadout.appleHealthSubtitle(
            isAvailable: appleHealth.isAvailable,
            state: appleHealth.state
        )
        return Toggle(isOn: appleHealthBinding) {
            HStack(spacing: SharpitSpacing.sm) {
                ProviderLogo(provider: .appleHealth)
                sourceTitle(
                    "Apple Santé",
                    status: line.text,
                    tone: line.isProblem ? SharpitColor.signalRisk : SharpitColor.mutedForeground
                )
            }
        }
        .tint(SharpitColor.primary)
        .disabled(!appleHealth.isAvailable)
        .padding(SharpitSpacing.cardPadding)
        .sharpitSurface(.panel)
    }

    private func sourceTitle(_ name: String, status: String, tone: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(name)
                .font(SharpitTypography.bodyEmphasis)
            Text(status)
                .font(SharpitTypography.meta)
                .foregroundStyle(tone)
                .lineLimit(1)
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
