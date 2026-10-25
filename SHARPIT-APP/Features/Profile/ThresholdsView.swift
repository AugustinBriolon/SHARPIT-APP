import SwiftData
import SwiftUI

/// Réglages → Seuils & repères: the yardstick load is read against. One white card per
/// discipline, its references as rows — name and what the value means on the left, the figure
/// typed in place on the right — saved as they are typed.
struct ThresholdsView: View {
    @State private var store: AthleteProfileStore
    @State private var form = ProfileFormState()
    @State private var autoSaveTask: Task<Void, Never>?
    @State private var hasLoaded = false
    /// The records' estimates; nil for a client that offers none.
    @State private var suggestions: ThresholdSuggestionStore?

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
        _suggestions = State(initialValue: (client as? any ThresholdEstimating).map {
            ThresholdSuggestionStore(client: $0, tokenProvider: tokenProvider)
        })
    }

    private static let ownedFields: [ProfileFormField] = [
        .ftpW, .maxHr, .lthr, .runThresholdPace, .runEasyPace, .swimCss, .poolLength,
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: SharpitSpacing.lg) {
                sourceLine

                if let suggestions, suggestions.preview?.hasChanges == true {
                    ThresholdSuggestionCard(
                        store: suggestions,
                        onApply: applyEstimates
                    )
                    .transition(.opacity)
                }

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
        .task {
            if store.phase != .loaded {
                await store.load()
            }
            form = ProfileFormState(profile: store.profile)
            hasLoaded = true
            await store.loadHistory()
            await suggestions?.loadPreview()
        }
        // The server's profile after an apply: the form takes the stored values,
        // even where the server wrote them differently from what was shown.
        .onChange(of: suggestions?.revision) { _, _ in
            form = ProfileFormState(profile: store.profile)
        }
        .animation(SharpitMotion.reveal, value: suggestions?.preview)
        .onChange(of: store.profile) { _, newProfile in
            if !hasLoaded || form.patch(against: newProfile).isEmpty {
                form = ProfileFormState(profile: newProfile)
                hasLoaded = true
            }
        }
        .scrollDismissesKeyboard(.interactively)
    }

    // MARK: - Source

    /// Where the figures come from, said once above the cards rather than as a card of its own.
    private var sourceLine: some View {
        Label {
            Text(sourceText)
        } icon: {
            Image(systemName: store.profile.thresholdsSyncedAt != nil ? "arrow.triangle.2.circlepath" : "hand.point.up.left")
        }
        .font(SharpitTypography.meta)
        .foregroundStyle(SharpitColor.mutedForeground)
        .padding(.horizontal, SharpitSpacing.xxs)
    }

    private var sourceText: String {
        if let syncedAt = store.profile.thresholdsSyncedAt {
            return String(localized: "Importés de ta montre ") + SyncReadout.age(of: syncedAt, now: .now) + String(localized: " — ils s'y règlent aussi.")
        }
        return String(localized: "Saisis à la main. Ils règlent tes zones et la charge de chaque séance.")
    }

    // MARK: - Disciplines

    private var cardioSection: some View {
        disciplineCard(title: String(localized: "Cardio"), symbol: "heart") {
            ThresholdRow(
                label: String(localized: "FC max"),
                text: $form.maxHr,
                placeholder: "190",
                unit: "bpm",
                keyboard: .numberPad,
                error: form.error(for: .maxHr),
                hint: nil,
                onChange: scheduleAutoSave
            )
            ThresholdRow(
                label: String(localized: "Seuil lactique"),
                text: $form.lthr,
                placeholder: "168",
                unit: "bpm",
                keyboard: .numberPad,
                error: form.error(for: .lthr),
                hint: lthrHint,
                onChange: scheduleAutoSave
            )
        }
    }

    private var lthrHint: String {
        guard let lthr = ProfileFieldFormat.parseInteger(form.lthr),
              let maxHr = ProfileFieldFormat.parseInteger(form.maxHr), maxHr > 0
        else { return "LTHR" }
        let pct = Int((Double(lthr) / Double(maxHr) * 100).rounded())
        return String(localized: "LTHR · \(pct) % de la FC max")
    }

    private var bikeSection: some View {
        disciplineCard(title: String(localized: "Vélo"), symbol: "bicycle") {
            ThresholdRow(
                label: "FTP",
                text: $form.ftpW,
                placeholder: "280",
                unit: "W",
                keyboard: .numberPad,
                error: form.error(for: .ftpW),
                hint: ftpHint,
                onChange: scheduleAutoSave
            )
        }
    }

    private var ftpHint: String {
        guard let w = ProfileFieldFormat.parseInteger(form.ftpW),
              let weight = store.profile.targetWeightKg, weight > 0
        else { return String(localized: "Puissance tenue une heure") }
        return Self.oneDecimal(Double(w) / weight) + " W/kg"
    }

    private var runSection: some View {
        disciplineCard(title: String(localized: "Course à pied"), symbol: "figure.run") {
            ThresholdRow(
                label: String(localized: "Allure seuil"),
                text: $form.runThresholdPace,
                placeholder: "4:15",
                unit: "/km",
                keyboard: .numbersAndPunctuation,
                error: form.error(for: .runThresholdPace),
                hint: paceHint(form.runThresholdPace),
                onChange: scheduleAutoSave
            )
            ThresholdRow(
                label: String(localized: "Allure endurance"),
                text: $form.runEasyPace,
                placeholder: derivedEasyPacePlaceholder,
                unit: "/km",
                keyboard: .numbersAndPunctuation,
                error: form.error(for: .runEasyPace),
                hint: easyPaceHint,
                onChange: scheduleAutoSave
            )
        }
    }

    private var derivedEasyPacePlaceholder: String {
        guard let threshold = ProfileFieldFormat.parsePace(form.runThresholdPace), threshold > 0 else {
            return "5:00"
        }
        let derived = Int((threshold * 1.15).rounded())
        return ProfileFieldFormat.pace(Double(derived))
    }

    private var easyPaceHint: String? {
        if let hint = paceHint(form.runEasyPace) { return "Z2 · " + hint }
        if form.runEasyPace.trimmingCharacters(in: .whitespaces).isEmpty,
           ProfileFieldFormat.parsePace(form.runThresholdPace) != nil {
            return String(localized: "Z2 · vide, déduite du seuil")
        }
        return "Z2"
    }

    private func paceHint(_ text: String) -> String? {
        guard let paceSec = ProfileFieldFormat.parsePace(text), paceSec > 0 else { return nil }
        return Self.oneDecimal(3600.0 / paceSec) + " km/h"
    }

    /// « 2,6 », « 10,8 »: the comma the rest of the app reads.
    private static func oneDecimal(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(1)).locale(SharpitLocale.current))
    }

    private var swimSection: some View {
        disciplineCard(title: String(localized: "Natation"), symbol: "figure.pool.swim") {
            ThresholdRow(
                label: String(localized: "Vitesse critique"),
                text: $form.swimCss,
                placeholder: "1:38",
                unit: "/100 m",
                keyboard: .numbersAndPunctuation,
                error: form.error(for: .swimCss),
                hint: String(localized: "CSS · allure seuil en continu"),
                onChange: scheduleAutoSave
            )
            poolLengthRow
        }
    }

    private var poolLengthRow: some View {
        HStack(spacing: SharpitSpacing.sm) {
            Text("Bassin")
                .font(SharpitTypography.bodyEmphasis)
                .foregroundStyle(SharpitColor.foreground)
            Spacer(minLength: SharpitSpacing.xs)
            SharpitSegmentedControl(
                selection: Binding(
                    get: { form.poolLength },
                    set: { form.poolLength = $0; scheduleAutoSave() }
                ),
                options: ["25", "50"].map { .init(value: $0, label: "\($0) m") }
            )
            .frame(width: 148)
        }
        .padding(.horizontal, SharpitSpacing.rowPaddingX)
        .padding(.vertical, SharpitSpacing.sm)
    }

    // MARK: - Measured by the watch

    @ViewBuilder
    private var estimatesSection: some View {
        let running = store.profile.vo2maxRunning
        let cycling = store.profile.vo2maxCycling
        if running != nil || cycling != nil {
            disciplineCard(title: String(localized: "Mesuré par ta montre"), symbol: "applewatch") {
                if let running { measuredRow(String(localized: "VO₂max course"), value: running) }
                if let cycling { measuredRow(String(localized: "VO₂max vélo"), value: cycling) }
            }
        }
    }

    private func measuredRow(_ title: String, value: Int) -> some View {
        HStack(spacing: SharpitSpacing.sm) {
            Text(title)
                .font(SharpitTypography.bodyEmphasis)
                .foregroundStyle(SharpitColor.foreground)
            Spacer(minLength: SharpitSpacing.xs)
            SharpitRowFigure(value: "\(value)", unit: "ml/kg/min")
        }
        .padding(.horizontal, SharpitSpacing.rowPaddingX)
        .frame(minHeight: SharpitSpacing.rowHeight)
        .accessibilityElement(children: .combine)
    }

    // MARK: - History

    @ViewBuilder
    private var historySection: some View {
        if !store.history.isEmpty {
            disciplineCard(title: String(localized: "Historique"), symbol: "clock.arrow.circlepath") {
                ForEach(store.history) { snapshot in
                    historyRow(snapshot)
                }
            }
        }
    }

    private func historyRow(_ snapshot: V1ThresholdSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: SharpitSpacing.xs) {
                Text(snapshot.createdAt.sharpitFormatted(.dateTime.day().month(.abbreviated).year()))
                    .font(SharpitTypography.bodyEmphasis)
                    .foregroundStyle(SharpitColor.foreground)
                Spacer(minLength: SharpitSpacing.xs)
                Text(snapshot.sourceLabel)
                    .font(SharpitTypography.meta)
                    .foregroundStyle(SharpitColor.mutedForeground)
            }
            Text(formattedSnapshotValues(snapshot))
                .font(SharpitTypography.meta)
                .foregroundStyle(SharpitColor.mutedForeground)
        }
        .padding(.horizontal, SharpitSpacing.rowPaddingX)
        .padding(.vertical, SharpitSpacing.sm)
        .accessibilityElement(children: .combine)
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

    // MARK: - Card

    /// A sport is told by its glyph in the ink tile, never by a colour (ADR-085).
    private func disciplineCard<Content: View>(
        title: String,
        symbol: String,
        subtitle: String? = nil,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: SharpitSpacing.sm) {
            SharpitCardHeader(title: title, symbol: symbol, subtitle: subtitle, showsChevron: false)
            // The last row's own padding already sits above the card's: pulled in so the foot
            // does not read as an empty row.
            SharpitInsetGroup { content() }
                .padding(.bottom, -SharpitSpacing.sm)
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
            performAutoSave()
        }
    }

    @MainActor
    private func performAutoSave() {
        guard Self.ownedFields.allSatisfy({ form.error(for: $0) == nil }) else { return }
        let patch = form.patch(against: store.profile)
        guard !patch.isEmpty else { return }
        store.save(patch)
        // A threshold typed by hand may settle or reopen a proposal.
        if let suggestions {
            Task {
                await store.settle()
                await suggestions.loadPreview()
            }
        }
    }

    // MARK: - Estimates

    /// The kept proposals show in the fields on the tap; a value being typed is saved first,
    /// so the estimate is written after it rather than raced by it.
    private func applyEstimates() {
        guard let suggestions else { return }
        autoSaveTask?.cancel()
        performAutoSave()
        suggestions.apply(to: store)
        form = ProfileFormState(profile: store.profile)
    }
}

// MARK: - Threshold Row

/// One reference as a row: its name and what it means on the left, the figure typed in place on
/// the right. A tap anywhere on the row puts the cursor in the figure.
private struct ThresholdRow: View {
    let label: String
    @Binding var text: String
    let placeholder: String
    let unit: String
    var keyboard: UIKeyboardType = .numberPad
    var error: String?
    var hint: String?
    var onChange: () -> Void

    @FocusState private var isFocused: Bool

    var body: some View {
        HStack(spacing: SharpitSpacing.sm) {
            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                    .font(SharpitTypography.bodyEmphasis)
                    .foregroundStyle(SharpitColor.foreground)
                if let line = error ?? hint {
                    Text(line)
                        .font(SharpitTypography.meta)
                        .foregroundStyle(error != nil ? SharpitColor.signalRisk : SharpitColor.mutedForeground)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: SharpitSpacing.xs)
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                TextField(placeholder, text: $text)
                    .font(SharpitTypography.data)
                    .foregroundStyle(error != nil ? SharpitColor.signalRisk : SharpitColor.foreground)
                    .multilineTextAlignment(.trailing)
                    .keyboardType(keyboard)
                    .focused($isFocused)
                    .frame(width: 72)
                    .onChange(of: text) { _, _ in onChange() }
                Text(unit)
                    .font(SharpitTypography.meta)
                    .foregroundStyle(SharpitColor.mutedForeground)
            }
        }
        .padding(.horizontal, SharpitSpacing.rowPaddingX)
        .padding(.vertical, SharpitSpacing.sm)
        .frame(minHeight: SharpitSpacing.rowHeight)
        .contentShape(.rect)
        .onTapGesture { isFocused = true }
    }
}
