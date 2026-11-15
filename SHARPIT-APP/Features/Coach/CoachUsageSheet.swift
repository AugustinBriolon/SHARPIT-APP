import SwiftUI

/// « Consommation » — the athlete's coach budget at a glance: what is spent, what is left, over
/// which window and when it comes back. Read from the quota the coach already holds.
struct CoachUsageSheet: View {
    let quota: V1CoachQuota?
    let onUpgrade: () -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            CliniqueSheetTitle(String(localized: "Consommation"))
            if let quota {
                usage(quota)
            } else {
                ProgressView()
                    .frame(maxWidth: .infinity)
                    .padding(.top, SharpitSpacing.xl)
            }
        }
        .padding(.horizontal, 24)
        .padding(.top, 30)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(SharpitColor.card)
        .cliniqueSheetCross { dismiss() }
        .presentationDetents([.height(quota?.isPro == false ? 440 : 380)])
        .presentationDragIndicator(.visible)
        .sharpitSheet()
    }

    private func usage(_ quota: V1CoachQuota) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            CliniqueStatusPill(
                quota.isPro ? String(localized: "Coach Pro") : String(localized: "Coach gratuit"),
                status: quota.isPro ? .pro : .unknown
            )
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(CoachQuotaReadout.usedPercent(quota))
                    .font(SharpitTypography.system(size: 44, weight: .semibold, relativeTo: .largeTitle, digits: true))
                    .tracking(-1.5)
                    .foregroundStyle(SharpitColor.foreground)
                Text("du budget utilisé")
                    .font(SharpitTypography.system(size: 16, weight: .regular, relativeTo: .callout))
                    .foregroundStyle(SharpitColor.slate)
            }
            .padding(.top, 10)
            .accessibilityElement(children: .combine)
            SharpitBarTrack(fraction: quota.usedRatio, tone: SharpitColor.pillarCoach)
                .frame(height: 6)
                .padding(.top, 10)
                .padding(.bottom, 18)
                .accessibilityHidden(true)
            CliniqueDivider()
            row(String(localized: "Échanges restants"), CoachQuotaReadout.questionsLeft(quota))
            CliniqueDivider()
            row(String(localized: "Renouvellement"), CoachQuotaReadout.resetLine(quota))
            CliniqueDivider()
            if !quota.isPro {
                Button { onUpgrade() } label: { Text("Passer Pro").frame(maxWidth: .infinity) }
                    .buttonStyle(CliniqueButtonStyle(kind: .primary, isLarge: true))
                    .padding(.top, 20)
            }
        }
    }

    private func row(_ label: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: SharpitSpacing.sm) {
            Text(label)
                .font(SharpitTypography.system(size: 15, weight: .regular, relativeTo: .body))
                .foregroundStyle(SharpitColor.foreground)
            Spacer(minLength: SharpitSpacing.xs)
            Text(value)
                .font(SharpitTypography.system(size: 15, weight: .semibold, relativeTo: .body, digits: true))
                .foregroundStyle(SharpitColor.foreground)
                .multilineTextAlignment(.trailing)
        }
        .padding(.vertical, 14)
        .accessibilityElement(children: .combine)
    }
}
