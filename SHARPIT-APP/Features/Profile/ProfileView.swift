import SwiftData
import SwiftUI

/// Réglages → Profil: athlete's stable attributes, identity and circadian rhythm.
/// Modern, tactile bento cards with quick selectors, instant age calculation,
/// and reactive auto-save without manual save confirmation button.
struct ProfileView: View {
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
        .heightCm, .targetWeightKg, .sleepTargetHours, .sleepBedtime,
    ]

    var body: some View {
        ScrollView {
            VStack(spacing: SharpitSpacing.lg) {
                athleteHeaderCard

                physiologySection

                sleepRhythmSection

                weightTargetSection
            }
            .padding(.horizontal, SharpitSpacing.pageInset)
            .padding(.vertical, SharpitSpacing.md)
        }
        .background(SharpitCanvasBackground())
        .navigationTitle("Profil")
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
        }
        .onChange(of: store.profile) { _, newProfile in
            if !hasLoaded || form.patch(against: newProfile).isEmpty {
                form = ProfileFormState(profile: newProfile)
                hasLoaded = true
            }
        }
        .scrollDismissesKeyboard(.interactively)
    }

    // MARK: - Athlete Header Card

    private var athleteHeaderCard: some View {
        HStack(spacing: SharpitSpacing.md) {
            ZStack {
                Circle()
                    .fill(SharpitColor.primary.opacity(0.12))
                    .frame(width: 48, height: 48)
                Image(systemName: "person.crop.circle.fill")
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundStyle(SharpitColor.primary)
            }

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text("Athlète SHARPIT")
                        .font(SharpitTypography.cardTitle)
                        .foregroundStyle(SharpitColor.foreground)

                    if store.profile.isPro {
                        Text("PRO")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(SharpitColor.primaryForeground)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(SharpitColor.primary, in: Capsule())
                    }
                }

                Text("Taille, âge et rythmes personnels — repères clés pour le coach.")
                    .font(SharpitTypography.meta)
                    .foregroundStyle(SharpitColor.mutedForeground)
            }

            Spacer()
        }
        .padding(SharpitSpacing.cardPadding)
        .sharpitSurface(.panel)
    }

    // MARK: - Physiology Section (Taille & Âge)

    private var physiologySection: some View {
        sectionCard(
            title: "Physiologie",
            subtitle: "Caractéristiques corporelles de référence.",
            symbolName: "figure.stand",
            color: SharpitColor.primary
        ) {
            VStack(spacing: SharpitSpacing.md) {
                ProfileInputField(
                    label: "Taille",
                    text: $form.heightCm,
                    placeholder: "178",
                    unit: "cm",
                    keyboard: .numberPad,
                    error: form.error(for: .heightCm),
                    hint: "Nécessaire au calcul d'IMC et de puissance relative",
                    onChange: scheduleAutoSave
                )

                birthDateRow
            }
        }
    }

    private var birthDateRow: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Date de naissance")
                    .font(SharpitTypography.meta)
                    .foregroundStyle(SharpitColor.mutedForeground)

                Spacer()

                if let age = ProfileAge.years(since: form.birthDate) {
                    Text("\(age) ans")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(SharpitColor.primary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(SharpitColor.primary.opacity(0.12), in: Capsule())
                }
            }

            DatePicker(
                "Date de naissance",
                selection: Binding(
                    get: { form.birthDate ?? Self.defaultBirthDate },
                    set: {
                        form.birthDate = $0
                        scheduleAutoSave()
                    }
                ),
                in: Self.birthDateRange,
                displayedComponents: .date
            )
            .labelsHidden()
            .datePickerStyle(.compact)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(SharpitColor.card, in: RoundedRectangle(cornerRadius: SharpitRadius.small))
            .overlay(
                RoundedRectangle(cornerRadius: SharpitRadius.small)
                    .strokeBorder(SharpitColor.border.opacity(0.6), lineWidth: 1)
            )
        }
    }

    // MARK: - Sleep & Circadian Rhythm Section

    private var sleepRhythmSection: some View {
        sectionCard(
            title: "Sommeil & Récupération",
            subtitle: "Repères pour l'analyse de tes nuits et de ta régularité circadienne.",
            symbolName: "moon.stars.fill",
            color: Color(red: 0.55, green: 0.45, blue: 0.95)
        ) {
            VStack(spacing: SharpitSpacing.md) {
                VStack(alignment: .leading, spacing: 8) {
                    ProfileInputField(
                        label: "Objectif de sommeil",
                        text: $form.sleepTargetHours,
                        placeholder: "8,0",
                        unit: "h",
                        keyboard: .decimalPad,
                        error: form.error(for: .sleepTargetHours),
                        hint: "Entre 4 et 12 heures",
                        onChange: scheduleAutoSave
                    )

                    // Quick duration pills
                    sleepPillSelector
                }

                ProfileInputField(
                    label: "Coucher visé",
                    text: $form.sleepBedtime,
                    placeholder: "22:30",
                    unit: "",
                    keyboard: .numbersAndPunctuation,
                    error: form.error(for: .sleepBedtime),
                    hint: "Format hh:mm (ex: 22:30) · Repère de régularité",
                    onChange: scheduleAutoSave
                )
            }
        }
    }

    private var sleepPillSelector: some View {
        HStack(spacing: SharpitSpacing.xs) {
            ForEach([("7,0", "7 h"), ("7,5", "7h30"), ("8,0", "8 h"), ("8,5", "8h30"), ("9,0", "9 h")], id: \.0) { target, label in
                let isSelected = form.sleepTargetHours == target || form.sleepTargetHours == target.replacingOccurrences(of: ",", with: ".")
                Button {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    withAnimation(.snappy(duration: 0.2)) {
                        form.sleepTargetHours = target
                    }
                    scheduleAutoSave()
                } label: {
                    Text(label)
                        .font(.system(size: 11, weight: isSelected ? .bold : .medium))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 7)
                        .background(
                            isSelected ? Color(red: 0.55, green: 0.45, blue: 0.95).opacity(0.18) : SharpitColor.analysisGrid.opacity(0.35),
                            in: RoundedRectangle(cornerRadius: SharpitRadius.small)
                        )
                        .foregroundStyle(isSelected ? Color(red: 0.55, green: 0.45, blue: 0.95) : SharpitColor.foreground)
                        .overlay(
                            RoundedRectangle(cornerRadius: SharpitRadius.small)
                                .strokeBorder(isSelected ? Color(red: 0.55, green: 0.45, blue: 0.95) : Color.clear, lineWidth: 1.5)
                        )
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: - Weight Target Section

    private var weightTargetSection: some View {
        sectionCard(
            title: "Objectif de poids",
            subtitle: "Pris en compte pour la lecture nutritionnelle et les ratios W/kg.",
            symbolName: "scalemass.fill",
            color: Color(red: 0.18, green: 0.82, blue: 0.65)
        ) {
            ProfileInputField(
                label: "Poids cible",
                text: $form.targetWeightKg,
                placeholder: "72",
                unit: "kg",
                keyboard: .decimalPad,
                error: form.error(for: .targetWeightKg),
                hint: "Optionnel · Ne déclenche aucune alerte restrictive",
                onChange: scheduleAutoSave
            )
        }
    }

    // MARK: - Helpers & Auto-Save

    private func sectionCard<Content: View>(
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
                        .fill(color.opacity(0.14))
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

    private static let birthDateRange: ClosedRange<Date> = {
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = TimeZone(identifier: "UTC")!
        let earliest = utc.date(from: DateComponents(year: 1920, month: 1, day: 1))!
        return earliest...Date.now
    }()

    private static let defaultBirthDate: Date = {
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = TimeZone(identifier: "UTC")!
        return utc.date(from: DateComponents(year: 1990, month: 1, day: 1)) ?? .now
    }()
}

// MARK: - Profile Input Field Component

private struct ProfileInputField: View {
    let label: String
    @Binding var text: String
    let placeholder: String
    let unit: String
    var keyboard: UIKeyboardType = .numberPad
    var error: String?
    var hint: String?
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
                } else if let hint {
                    Text(hint)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(SharpitColor.mutedForeground)
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

                if !unit.isEmpty {
                    Text(unit)
                        .font(SharpitTypography.meta)
                        .foregroundStyle(SharpitColor.mutedForeground)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(SharpitColor.analysisGrid.opacity(0.35), in: RoundedRectangle(cornerRadius: 6))
                }
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

/// The athlete's age in whole years, as the web's `athleteAgeYears` computes it.
nonisolated enum ProfileAge {
    static func years(since birthDate: Date?, now: Date = .now) -> Int? {
        guard let birthDate else { return nil }
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = TimeZone(identifier: "UTC")!
        guard let years = utc.dateComponents([.year], from: birthDate, to: now).year, years >= 0 else {
            return nil
        }
        return years
    }
}

