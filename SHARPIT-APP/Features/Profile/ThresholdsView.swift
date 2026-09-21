import SwiftUI

/// Réglages → Seuils & repères: the yardstick load is read against.
///
/// Editable whatever the reading density. Repairing a stale threshold is maintenance, and the
/// web makes the same call: what stays expert is the display of the metrics a threshold
/// scales — TSS, IF, zones — not setting the ruler itself.
struct ThresholdsView: View {
    @State private var store: AthleteProfileStore
    @State private var form = ProfileFormState()

    init(client: any AthleteProfileServing, tokenProvider: @escaping () async throws -> String) {
        _store = State(initialValue: AthleteProfileStore(client: client, tokenProvider: tokenProvider))
    }

    private static let ownedFields: [ProfileFormField] = [
        .ftpW, .maxHr, .lthr, .runThresholdPace, .swimCss, .poolLength,
    ]

    var body: some View {
        ProfileFormScaffold(
            title: "Seuils & repères",
            subtitle: "FTP, allure seuil, FC max — le repère contre lequel ta charge est lue. Un seuil faux fausse toute la lecture.",
            store: store,
            form: $form,
            ownedFields: Self.ownedFields
        ) {
            confidence
            SharpitFieldGroup("Vélo") {
                SharpitField(
                    label: "FTP",
                    text: $form.ftpW,
                    placeholder: "280",
                    unit: "W",
                    error: form.error(for: .ftpW)
                )
            }
            SharpitFieldGroup("Cardio") {
                SharpitField(
                    label: "FC max",
                    text: $form.maxHr,
                    placeholder: "190",
                    unit: "bpm",
                    error: form.error(for: .maxHr)
                )
                SharpitField(
                    label: "LTHR",
                    text: $form.lthr,
                    placeholder: "168",
                    unit: "bpm",
                    hint: "FC au seuil lactique — la bascule, pas le maximum.",
                    error: form.error(for: .lthr)
                )
            }
            SharpitFieldGroup("Course") {
                SharpitField(
                    label: "Allure seuil",
                    text: $form.runThresholdPace,
                    placeholder: "4:15",
                    unit: "/km",
                    keyboard: .numbersAndPunctuation,
                    error: form.error(for: .runThresholdPace)
                )
            }
            SharpitFieldGroup("Natation") {
                SharpitField(
                    label: "Vitesse critique",
                    text: $form.swimCss,
                    placeholder: "1:38",
                    unit: "/100 m",
                    keyboard: .numbersAndPunctuation,
                    error: form.error(for: .swimCss)
                )
                SharpitField(
                    label: "Longueur de bassin",
                    text: $form.poolLength,
                    placeholder: "25",
                    unit: "m",
                    error: form.error(for: .poolLength)
                )
            }
            estimates
            history
        }
        .task { await store.loadHistory() }
    }

    /// Where the current values come from, as the closing line of the causal column.
    @ViewBuilder
    private var confidence: some View {
        if let syncedAt = store.profile.thresholdsSyncedAt {
            Label(
                "Importés de Garmin " + SyncReadout.age(of: syncedAt, now: .now),
                systemImage: "arrow.triangle.2.circlepath"
            )
            .font(SharpitTypography.meta)
            .foregroundStyle(SharpitColor.mutedForeground)
        } else {
            Label("Aucun import Garmin — ces valeurs sont les tiennes.", systemImage: "hand.raised")
                .font(SharpitTypography.meta)
                .foregroundStyle(SharpitColor.mutedForeground)
        }
    }

    /// VO₂max is read, never typed: it comes from Garmin or from an estimate, and the web's
    /// patch validator refuses it.
    @ViewBuilder
    private var estimates: some View {
        let running = store.profile.vo2maxRunning
        let cycling = store.profile.vo2maxCycling
        if running != nil || cycling != nil {
            VStack(alignment: .leading, spacing: SharpitSpacing.sm) {
                SharpitEyebrow("Mesuré pour toi")
                HStack(spacing: SharpitSpacing.sm) {
                    if let running {
                        SharpitStatTile(caption: "VO₂max course", value: "\(running)", unit: "ml/kg/min")
                    }
                    if let cycling {
                        SharpitStatTile(caption: "VO₂max vélo", value: "\(cycling)", unit: "ml/kg/min")
                    }
                }
                .fixedSize(horizontal: false, vertical: true)
                Text("Estimé par ta montre. Se règle sur Garmin, pas ici.")
                    .font(SharpitTypography.meta)
                    .foregroundStyle(SharpitColor.mutedForeground)
            }
        }
    }

    /// What the thresholds were before, so a wrong value can be recognised as new.
    @ViewBuilder
    private var history: some View {
        if !store.history.isEmpty {
            VStack(alignment: .leading, spacing: SharpitSpacing.sm) {
                SharpitEyebrow("Historique")
                VStack(spacing: 0) {
                    Group(subviews: snapshotRows) { subviews in
                        ForEach(subviews.indices, id: \.self) { index in
                            if index > subviews.startIndex {
                                Rectangle()
                                    .fill(SharpitColor.analysisGrid)
                                    .frame(height: SharpitStroke.hairline)
                            }
                            subviews[index]
                        }
                    }
                }
                .padding(.horizontal, SharpitSpacing.md)
                .sharpitSurface(.panel)
            }
        }
    }

    private var snapshotRows: some View {
        ForEach(store.history) { snapshot in
            ThresholdSnapshotRow(snapshot: snapshot)
        }
    }
}

private struct ThresholdSnapshotRow: View {
    let snapshot: V1ThresholdSnapshot

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: SharpitSpacing.sm) {
            VStack(alignment: .leading, spacing: 2) {
                Text(snapshot.createdAt.formatted(.dateTime.day().month(.abbreviated).year()))
                    .font(SharpitTypography.bodyEmphasis)
                    .foregroundStyle(SharpitColor.foreground)
                Text(snapshot.sourceLabel)
                    .font(SharpitTypography.meta)
                    .foregroundStyle(SharpitColor.mutedForeground)
            }
            Spacer(minLength: SharpitSpacing.xs)
            Text(values)
                .font(SharpitTypography.meta)
                .foregroundStyle(SharpitColor.mutedForeground)
                .multilineTextAlignment(.trailing)
        }
        .padding(.vertical, SharpitSpacing.sm)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    /// Only what the snapshot recorded: a snapshot written by a cycling test says nothing
    /// about the swim.
    private var values: String {
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
}
