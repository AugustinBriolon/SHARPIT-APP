import SwiftUI

/// « Consommation » — the athlete's coach budget at a glance: what is spent, what is left, over
/// which window and when it comes back. Read from the quota the coach already holds.
struct CoachUsageSheet: View {
    let quota: V1CoachQuota?
    let onUpgrade: () -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                if let quota {
                    usage(quota)
                        .padding(SharpitSpacing.md)
                } else {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                        .padding(.top, SharpitSpacing.xl)
                }
            }
            .navigationTitle("Consommation")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("OK") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .sharpitSheet()
    }

    private func usage(_ quota: V1CoachQuota) -> some View {
        VStack(alignment: .leading, spacing: SharpitSpacing.md) {
            SharpitCardHeader(
                title: quota.isPro ? String(localized: "Coach Pro") : String(localized: "Coach gratuit"),
                symbol: "gauge.with.dots.needle.33percent",
                showsChevron: false
            )
            SharpitProgressBar(
                label: String(localized: "Utilisé"),
                value: CoachQuotaReadout.usedPercent(quota),
                fraction: quota.usedRatio,
                style: .ink
            )
            row(String(localized: "Échanges restants"), CoachQuotaReadout.questionsLeft(quota))
            row(String(localized: "Renouvellement"), CoachQuotaReadout.resetLine(quota))
            if !quota.isPro {
                Button("Passer Pro") { onUpgrade() }
                    .font(SharpitTypography.meta.weight(.semibold))
                    .foregroundStyle(SharpitColor.foreground)
            }
        }
        .padding(SharpitSpacing.cardPadding)
        .sharpitSurface(.panel)
    }

    private func row(_ label: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label)
                .foregroundStyle(SharpitColor.mutedForeground)
            Spacer(minLength: SharpitSpacing.xs)
            Text(value)
                .fontWeight(.semibold)
                .foregroundStyle(SharpitColor.foreground)
                .multilineTextAlignment(.trailing)
        }
        .font(SharpitTypography.system(size: 16, weight: .regular, relativeTo: .body))
        .accessibilityElement(children: .combine)
    }
}
