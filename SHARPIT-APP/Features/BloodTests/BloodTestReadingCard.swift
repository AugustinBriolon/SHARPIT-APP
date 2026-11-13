import SwiftUI

/// One test's athlete reading, fetched when its detail opens (SHARPIT ADR-129).
@MainActor
@Observable
final class BloodTestReadingStore {
    enum Phase: Equatable {
        case loading
        case loaded(V1BloodTestReading)
        case proRequired
        case failed
    }

    private(set) var phase: Phase = .loading
    private let client: any BloodTestReading
    private let tokenProvider: () async throws -> String

    init(client: any BloodTestReading = BloodTestClient(), tokenProvider: @escaping () async throws -> String) {
        self.client = client
        self.tokenProvider = tokenProvider
    }

    func load(testId: String) async {
        do {
            let reading = try await SharpitRetry.run {
                try await client.reading(testId: testId, token: try await tokenProvider())
            }
            phase = .loaded(reading)
        } catch SharpitAPIError.proRequired {
            phase = .proRequired
        } catch {
            phase = .failed
        }
    }
}

/// « Lecture sportive »: what the training before the sample can explain, and what goes to a doctor.
struct BloodTestReadingCard: View {
    let store: BloodTestReadingStore

    var body: some View {
        switch store.phase {
        case .loading:
            EmptyView()
        case .proRequired:
            SharpitProTeaser(
                title: String(localized: "Lecture sportive"),
                message: String(localized: "Ce que ton entraînement explique dans tes résultats, et ce qui mérite l'avis d'un médecin.")
            )
        case .failed:
            // Secondary to the table: says nothing rather than an error under real values.
            EmptyView()
        case .loaded(let reading):
            content(reading)
        }
    }

    private func content(_ reading: V1BloodTestReading) -> some View {
        VStack(alignment: .leading, spacing: SharpitSpacing.sm) {
            SharpitCardHeader(
                title: String(localized: "Lecture sportive"),
                symbol: "figure.run",
                subtitle: String(localized: "\(reading.training.sessionsInWeek) séance(s) les 7 jours avant le prélèvement"),
                showsChevron: false
            )
            if reading.findings.isEmpty {
                Text("Rien dans ces résultats que l'entraînement aide à lire.")
                    .font(SharpitTypography.meta)
                    .foregroundStyle(SharpitColor.mutedForeground)
            } else {
                ForEach(reading.findings, id: \.key) { finding in
                    BloodTestFindingRow(finding: finding)
                }
            }
            Text("Lecture d'entraînement, pas un diagnostic.")
                .font(SharpitTypography.meta)
                .foregroundStyle(SharpitColor.mutedForeground)
        }
        .padding(SharpitSpacing.cardPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .sharpitSurface(.panel)
    }
}

private struct BloodTestFindingRow: View {
    let finding: V1BloodTestReading.Finding

    var body: some View {
        VStack(alignment: .leading, spacing: SharpitSpacing.xs) {
            HStack(spacing: SharpitSpacing.xs) {
                Image(systemName: finding.tone == .doctor ? "stethoscope" : "figure.run")
                    .foregroundStyle(finding.tone == .doctor ? SharpitColor.signalCaution : SharpitColor.mutedForeground)
                    .accessibilityHidden(true)
                Text(markers)
                    .font(SharpitTypography.bodyEmphasis)
                    .foregroundStyle(SharpitColor.foreground)
            }
            Text(finding.text)
                .font(SharpitTypography.body)
                .foregroundStyle(SharpitColor.foreground)
                .fixedSize(horizontal: false, vertical: true)
            Text(finding.source)
                .font(SharpitTypography.meta)
                .foregroundStyle(SharpitColor.mutedForeground)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, SharpitSpacing.xs)
        .accessibilityElement(children: .combine)
    }

    private var markers: String {
        finding.markerKeys.map { BloodMarkerCatalog.marker($0)?.label ?? $0 }.formatted(.list(type: .and))
    }
}
