import SwiftUI

/// What Apple Health holds, compared with what SHARPIT reads from Garmin — measured on the
/// athlete's own phone before Apple Health is trusted as a source.
struct HealthCoverageView: View {
    @State private var store: HealthCoverageStore

    init(reader: any HealthReading) {
        _store = State(initialValue: HealthCoverageStore(reader: reader))
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: SharpitSpacing.section) {
                Text("Ce qu'Apple Santé contient sur les \(HealthCoverageStore.windowDays) derniers jours, signal par signal, et qui l'a écrit.")
                    .font(SharpitTypography.body)
                    .foregroundStyle(SharpitColor.mutedForeground)
                content
            }
            .padding(SharpitSpacing.pageInset)
        }
        .background(SharpitCanvasBackground())
        .navigationTitle("Diagnostic Apple Santé")
        .navigationBarTitleDisplayMode(.inline)
        .task { if store.phase == .idle { await store.run() } }
    }

    @ViewBuilder
    private var content: some View {
        switch store.phase {
        case .idle, .reading:
            ProgressView("Lecture d'Apple Santé…")
                .frame(maxWidth: .infinity)
        case .unavailable:
            Label("Apple Santé n'est pas disponible sur cet appareil.", systemImage: "heart.slash")
                .foregroundStyle(SharpitColor.mutedForeground)
        case .failed(let message):
            Label(message, systemImage: "exclamationmark.triangle")
                .foregroundStyle(SharpitColor.signalCaution)
        case .ready(let rows):
            VStack(alignment: .leading, spacing: SharpitSpacing.sm) {
                summary(rows)
                VStack(spacing: 0) {
                    ForEach(rows) { row in
                        CoverageRowView(row: row)
                        if row.id != rows.last?.id {
                            Rectangle().fill(SharpitColor.analysisGrid).frame(height: 1)
                        }
                    }
                }
                .padding(.horizontal, SharpitSpacing.md)
                .sharpitSurface(.panel)
                Text("Apple Santé ne dit pas si une lecture a été refusée : un signal absent peut aussi venir d'un accès non accordé dans Réglages › Santé.")
                    .font(SharpitTypography.meta)
                    .foregroundStyle(SharpitColor.mutedForeground)
            }
        }
    }

    private func summary(_ rows: [HealthCoverageRow]) -> some View {
        let covered = rows.filter { $0.verdict == .covered }.count
        let comparable = rows.filter { $0.verdict != .noEquivalent }.count
        return HStack(spacing: SharpitSpacing.sm) {
            SharpitStatTile(caption: "Couverts", value: "\(covered)/\(comparable)", tone: SharpitColor.signalRecovery)
            SharpitStatTile(
                caption: "Garmin seul",
                value: "\(rows.filter { $0.verdict == .noEquivalent }.count)",
                note: "sans équivalent Apple"
            )
        }
        .fixedSize(horizontal: false, vertical: true)
    }
}

private struct CoverageRowView: View {
    let row: HealthCoverageRow

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: SharpitSpacing.sm) {
            Image(systemName: symbol)
                .foregroundStyle(tone)
                .frame(width: 20)
            VStack(alignment: .leading, spacing: 2) {
                Text(row.signal.label)
                    .font(SharpitTypography.bodyEmphasis)
                    .foregroundStyle(SharpitColor.foreground)
                Text(detail)
                    .font(SharpitTypography.meta)
                    .foregroundStyle(SharpitColor.mutedForeground)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
            Text(row.signal.usedFor)
                .font(SharpitTypography.label)
                .tracking(SharpitTypography.labelTracking)
                .textCase(.uppercase)
                .foregroundStyle(SharpitColor.mutedForeground)
        }
        .padding(.vertical, SharpitSpacing.sm)
        .accessibilityElement(children: .combine)
    }

    private var symbol: String {
        switch row.verdict {
        case .covered: "checkmark.circle.fill"
        case .partial: "circle.lefthalf.filled"
        case .missing: "xmark.circle"
        case .noEquivalent: "minus.circle"
        }
    }

    private var tone: Color {
        switch row.verdict {
        case .covered: SharpitColor.signalRecovery
        case .partial: SharpitColor.signalCaution
        case .missing: SharpitColor.signalRisk
        case .noEquivalent: SharpitColor.signalNeutral
        }
    }

    private var detail: String {
        switch row.verdict {
        case .noEquivalent:
            return "Calculé par Garmin, jamais écrit dans Apple Santé"
        case .missing:
            return "Absent d'Apple Santé"
        case .covered, .partial:
            let days = "\(row.dayCount) j sur \(HealthCoverageStore.windowDays)"
            let sources = row.sources.joined(separator: ", ")
            return sources.isEmpty ? days : "\(days) · \(sources)"
        }
    }
}
