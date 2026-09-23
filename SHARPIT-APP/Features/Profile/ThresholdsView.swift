import SwiftData
import SwiftUI

/// Réglages → Seuils & repères: the yardstick load is read against.
/// Modern, tactile and sportive bento layout with dynamic conversions (W/kg, km/h, % LTHR)
/// and reactive auto-save without manual confirmation button.
struct ThresholdsView: View {
    @State private var store: AthleteProfileStore
    @Environment(SharpitToastCenter.self) private var toastCenter: SharpitToastCenter?
    @State private var form = ProfileFormState()
    @State private var autoSaveTask: Task<Void, Never>?
    @State private var hasLoaded = false

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

    private static let ownedFields: [ProfileFormField] = [
        .ftpW, .maxHr, .lthr, .runThresholdPace, .swimCss, .poolLength,
    ]

    var body: some View {
        ScrollView {
            VStack(spacing: SharpitSpacing.lg) {
                confidenceCard

                cardioSection

                bikeSection

                runSection

                swimSection

                estimatesSection

                historySection
            }
            .padding(.horizontal, SharpitSpacing.pageInset)
            .padding(.vertical, SharpitSpacing.md)
        }
        .background(SharpitCanvasBackground())
        .navigationTitle("Seuils & repères")
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
            if store.phase != .loaded {
                await store.load()
            }
            form = ProfileFormState(profile: store.profile)
            hasLoaded = true
            await store.loadHistory()
        }
        .onChange(of: store.profile) { _, newProfile in
            if !hasLoaded || form.patch(against: newProfile).isEmpty {
                form = ProfileFormState(profile: newProfile)
                hasLoaded = true
            }
        }
        .scrollDismissesKeyboard(.interactively)
    }

    // MARK: - Confidence & Source Card

    private var confidenceCard: some View {
        HStack(spacing: SharpitSpacing.md) {
            ZStack {
                Circle()
                    .fill((store.profile.thresholdsSyncedAt != nil ? SharpitColor.signalRecovery : SharpitColor.primary).opacity(0.14))
                    .frame(width: 44, height: 44)
                Image(systemName: store.profile.thresholdsSyncedAt != nil ? "arrow.triangle.2.circlepath" : "person.badge.shield.checkmark.fill")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(store.profile.thresholdsSyncedAt != nil ? SharpitColor.signalRecovery : SharpitColor.primary)
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(store.profile.thresholdsSyncedAt != nil ? "Synchronisé avec Garmin" : "Calibrations manuelles")
                    .font(SharpitTypography.bodyEmphasis)
                    .foregroundStyle(SharpitColor.foreground)

                Text(confidenceSubtitle)
                    .font(SharpitTypography.meta)
                    .foregroundStyle(SharpitColor.mutedForeground)
            }

            Spacer()
        }
        .padding(SharpitSpacing.cardPadding)
        .sharpitSurface(.panel)
    }

    private var confidenceSubtitle: String {
        if let syncedAt = store.profile.thresholdsSyncedAt {
            return "Importé " + SyncReadout.age(of: syncedAt, now: .now) + " · Se règle sur Garmin"
        }
        return "Ces repères personnalisés orientent les intensités et les zones d'effort."
    }

    // MARK: - Cardio Section

    private var cardioSection: some View {
        disciplineContainer(
            title: "Cardio",
            subtitle: "Repères de pulsation pour le calibrage des zones cardiaques.",
            symbolName: "heart.fill",
            color: SharpitColor.signalRisk
        ) {
            VStack(spacing: SharpitSpacing.sm) {
                ThresholdInputField(
                    label: "FC max",
                    text: $form.maxHr,
                    placeholder: "190",
                    unit: "bpm",
                    keyboard: .numberPad,
                    error: form.error(for: .maxHr),
                    dynamicHint: fcMaxHint,
                    onChange: scheduleAutoSave
                )

                ThresholdInputField(
                    label: "LTHR (Seuil lactique)",
                    text: $form.lthr,
                    placeholder: "168",
                    unit: "bpm",
                    keyboard: .numberPad,
                    error: form.error(for: .lthr),
                    dynamicHint: lthrHint,
                    onChange: scheduleAutoSave
                )
            }
        }
    }

    private var fcMaxHint: String? {
        guard let hr = ProfileFieldFormat.parseInteger(form.maxHr) else { return nil }
        return "\(hr) bpm max"
    }

    private var lthrHint: String? {
        guard let lthr = ProfileFieldFormat.parseInteger(form.lthr) else { return nil }
        if let maxHr = ProfileFieldFormat.parseInteger(form.maxHr), maxHr > 0 {
            let pct = Int((Double(lthr) / Double(maxHr) * 100).rounded())
            return "Bascule à \(pct)% de FC max"
        }
        return "Bascule aérobie / anaérobie"
    }

    // MARK: - Bike Section

    private var bikeSection: some View {
        disciplineContainer(
            title: "Cyclisme / Vélo",
            subtitle: "Puissance de référence pour les zones de watts et la charge vélo.",
            symbolName: "bicycle",
            color: SharpitSportColor.color(SharpitSportColor.bike)
        ) {
            ThresholdInputField(
                label: "FTP (Functional Threshold Power)",
                text: $form.ftpW,
                placeholder: "280",
                unit: "W",
                keyboard: .numberPad,
                error: form.error(for: .ftpW),
                dynamicHint: ftpHint,
                onChange: scheduleAutoSave
            )
        }
    }

    private var ftpHint: String? {
        guard let w = ProfileFieldFormat.parseInteger(form.ftpW) else { return nil }
        if let targetWeight = store.profile.targetWeightKg, targetWeight > 0 {
            let ratio = Double(w) / targetWeight
            return String(format: "%.1f W/kg", ratio)
        }
        return "Effort max soutenable 1h"
    }

    // MARK: - Run Section

    private var runSection: some View {
        disciplineContainer(
            title: "Course à pied",
            subtitle: "Allure seuil pour les intensités tempo, seuil et le rTSS.",
            symbolName: "figure.run",
            color: SharpitSportColor.color(SharpitSportColor.run)
        ) {
            ThresholdInputField(
                label: "Allure seuil",
                text: $form.runThresholdPace,
                placeholder: "4:15",
                unit: "/km",
                keyboard: .numbersAndPunctuation,
                error: form.error(for: .runThresholdPace),
                dynamicHint: runPaceHint,
                onChange: scheduleAutoSave
            )
        }
    }

    private var runPaceHint: String? {
        guard let paceSec = ProfileFieldFormat.parsePace(form.runThresholdPace), paceSec > 0 else { return nil }
        let kmh = 3600.0 / paceSec
        return String(format: "%.1f km/h", kmh)
    }

    // MARK: - Swim Section

    private var swimSection: some View {
        disciplineContainer(
            title: "Natation",
            subtitle: "Vitesse critique de nage (CSS) et longueur de bassin habituelle.",
            symbolName: "figure.pool.swim",
            color: SharpitSportColor.color(SharpitSportColor.swim)
        ) {
            VStack(spacing: SharpitSpacing.sm) {
                ThresholdInputField(
                    label: "Vitesse critique (CSS)",
                    text: $form.swimCss,
                    placeholder: "1:38",
                    unit: "/100 m",
                    keyboard: .numbersAndPunctuation,
                    error: form.error(for: .swimCss),
                    dynamicHint: "Allure seuil en continu",
                    onChange: scheduleAutoSave
                )

                poolLengthSelector
            }
        }
    }

    private var poolLengthSelector: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Longueur de bassin")
                .font(SharpitTypography.meta)
                .foregroundStyle(SharpitColor.mutedForeground)

            HStack(spacing: SharpitSpacing.xs) {
                ForEach([25, 50], id: \.self) { length in
                    let isSelected = form.poolLength == "\(length)"
                    Button {
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        withAnimation(.snappy(duration: 0.2)) {
                            form.poolLength = "\(length)"
                        }
                        scheduleAutoSave()
                    } label: {
                        HStack(spacing: 6) {
                            Text("\(length) m")
                                .font(SharpitTypography.bodyEmphasis)
                            if isSelected {
                                Image(systemName: "checkmark")
                                    .font(.system(size: 11, weight: .bold))
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(
                            isSelected ? SharpitSportColor.color(SharpitSportColor.swim).opacity(0.18) : SharpitColor.card,
                            in: RoundedRectangle(cornerRadius: SharpitRadius.small)
                        )
                        .foregroundStyle(isSelected ? SharpitSportColor.color(SharpitSportColor.swim) : SharpitColor.foreground)
                        .overlay(
                            RoundedRectangle(cornerRadius: SharpitRadius.small)
                                .strokeBorder(isSelected ? SharpitSportColor.color(SharpitSportColor.swim) : SharpitColor.border.opacity(0.6), lineWidth: isSelected ? 1.5 : 1)
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    // MARK: - VO₂max Estimates Section

    @ViewBuilder
    private var estimatesSection: some View {
        let running = store.profile.vo2maxRunning
        let cycling = store.profile.vo2maxCycling
        if running != nil || cycling != nil {
            VStack(alignment: .leading, spacing: SharpitSpacing.sm) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Mesuré pour toi")
                        .font(SharpitTypography.sectionTitle)
                        .foregroundStyle(SharpitColor.foreground)

                    Text("Estimé par ta montre Garmin. Se règle sur Garmin, pas ici.")
                        .font(SharpitTypography.meta)
                        .foregroundStyle(SharpitColor.mutedForeground)
                }

                HStack(spacing: SharpitSpacing.sm) {
                    if let running {
                        vo2maxCard(title: "VO₂max course", value: running, icon: "figure.run", color: SharpitSportColor.color(SharpitSportColor.run))
                    }
                    if let cycling {
                        vo2maxCard(title: "VO₂max vélo", value: cycling, icon: "bicycle", color: SharpitSportColor.color(SharpitSportColor.bike))
                    }
                }
            }
        }
    }

    private func vo2maxCard(title: String, value: Int, icon: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                ZStack {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(color.opacity(0.15))
                        .frame(width: 28, height: 28)
                    Image(systemName: icon)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(color)
                }
                Spacer()
                Text("Garmin")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(SharpitColor.mutedForeground)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(SharpitColor.analysisGrid.opacity(0.3), in: Capsule())
            }

            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text("\(value)")
                        .font(.system(size: 24, weight: .bold, design: .rounded))
                        .foregroundStyle(SharpitColor.foreground)
                    Text("ml/kg/min")
                        .font(.system(size: 11))
                        .foregroundStyle(SharpitColor.mutedForeground)
                }

                Text(title)
                    .font(SharpitTypography.meta)
                    .foregroundStyle(SharpitColor.mutedForeground)
            }
        }
        .padding(SharpitSpacing.cardPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .sharpitSurface(.panel)
    }

    // MARK: - History Section

    @ViewBuilder
    private var historySection: some View {
        if !store.history.isEmpty {
            VStack(alignment: .leading, spacing: SharpitSpacing.sm) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Historique des calibrations")
                        .font(SharpitTypography.sectionTitle)
                        .foregroundStyle(SharpitColor.foreground)

                    Text("Évolution de tes repères enregistrés au fil des tests et saisons.")
                        .font(SharpitTypography.meta)
                        .foregroundStyle(SharpitColor.mutedForeground)
                }

                VStack(spacing: SharpitSpacing.xs) {
                    ForEach(store.history) { snapshot in
                        historyRow(snapshot)
                    }
                }
            }
        }
    }

    private func historyRow(_ snapshot: V1ThresholdSnapshot) -> some View {
        HStack(alignment: .center, spacing: SharpitSpacing.sm) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(snapshot.createdAt.sharpitFormatted(.dateTime.day().month(.abbreviated).year()))
                        .font(SharpitTypography.bodyEmphasis)
                        .foregroundStyle(SharpitColor.foreground)

                    Text(snapshot.sourceLabel)
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(SharpitColor.primary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(SharpitColor.primary.opacity(0.12), in: Capsule())
                }

                Text(formattedSnapshotValues(snapshot))
                    .font(SharpitTypography.meta)
                    .foregroundStyle(SharpitColor.mutedForeground)
            }

            Spacer()
        }
        .padding(SharpitSpacing.cardPadding)
        .sharpitSurface(.panel)
    }

    private func formattedSnapshotValues(_ snapshot: V1ThresholdSnapshot) -> String {
        var parts: [String] = []
        if let ftpW = snapshot.ftpW { parts.append("\(ftpW) W") }
        if let lthr = snapshot.lthr { parts.append("\(lthr) bpm") }
        if let pace = snapshot.runThresholdPaceSecPerKm {
            parts.append(ProfileFieldFormat.pace(pace) + " /km")
        }
        if let css = snapshot.swimCssSecPer100m {
            parts.append(ProfileFieldFormat.pace(css) + " /100 m")
        }
        return parts.isEmpty ? "—" : parts.joined(separator: " · ")
    }

    // MARK: - Container Helper

    private func disciplineContainer<Content: View>(
        title: String,
        subtitle: String,
        symbolName: String,
        color: Color,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: SharpitSpacing.md) {
            HStack(spacing: SharpitSpacing.sm) {
                ZStack {
                    RoundedRectangle(cornerRadius: SharpitRadius.small, style: .continuous)
                        .fill(color.opacity(0.15))
                        .frame(width: 36, height: 36)
                    Image(systemName: symbolName)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(color)
                }

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

            content()
        }
        .padding(SharpitSpacing.cardPadding)
        .sharpitSurface(.panel)
    }

    // MARK: - Auto-Save

    private func scheduleAutoSave() {
        guard hasLoaded else { return }
        autoSaveTask?.cancel()
        autoSaveTask = Task {
            try? await Task.sleep(nanoseconds: 600_000_000)
            guard !Task.isCancelled else { return }
            await performAutoSave()
        }
    }

    @MainActor
    private func performAutoSave() async {
        guard Self.ownedFields.allSatisfy({ form.error(for: $0) == nil }) else { return }
        let patch = form.patch(against: store.profile)
        guard !patch.isEmpty else { return }

        let success = await store.save(patch)
        if !success, let err = store.saveError {
            toastCenter?.show(err, symbol: "exclamationmark.triangle.fill", tone: .error)
        }
    }
}

// MARK: - Threshold Input Field

private struct ThresholdInputField: View {
    let label: String
    @Binding var text: String
    let placeholder: String
    let unit: String
    var keyboard: UIKeyboardType = .numberPad
    var error: String?
    var dynamicHint: String?
    var onChange: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(label)
                    .font(SharpitTypography.meta)
                    .foregroundStyle(error != nil ? SharpitColor.signalRisk : SharpitColor.mutedForeground)

                Spacer()

                if let error {
                    Text(error)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(SharpitColor.signalRisk)
                } else if let dynamicHint {
                    Text(dynamicHint)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(SharpitColor.primary)
                }
            }

            HStack(spacing: SharpitSpacing.xs) {
                TextField(placeholder, text: $text)
                    .font(.system(size: 19, weight: .semibold, design: .rounded))
                    .foregroundStyle(SharpitColor.foreground)
                    .keyboardType(keyboard)
                    .onChange(of: text) { _, _ in
                        onChange()
                    }

                Text(unit)
                    .font(SharpitTypography.meta)
                    .foregroundStyle(SharpitColor.mutedForeground)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(SharpitColor.analysisGrid.opacity(0.35), in: RoundedRectangle(cornerRadius: 6))
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(SharpitColor.card, in: RoundedRectangle(cornerRadius: SharpitRadius.small))
            .overlay(
                RoundedRectangle(cornerRadius: SharpitRadius.small)
                    .strokeBorder(error != nil ? SharpitColor.signalRisk : SharpitColor.border.opacity(0.6), lineWidth: error != nil ? 1.5 : 1)
            )
        }
    }
}
