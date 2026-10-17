import SwiftUI

/// The night's proposal for today's session, under the verdict: what changes, why, the plan
/// beside the proposal, and one tap to take it or keep the plan. It shows only while the
/// server waits for an answer, after the morning check-in.
struct MorningProposalCard: View {
    let proposal: V1TodayMorningProposal
    /// Opens the morning check-in, which refines the proposal; nil where it cannot be opened.
    var onCheckIn: (() -> Void)?
    let onAnswer: (_ accept: Bool) -> Void

    private var invitesCheckIn: Bool { proposal.checkInDone == false && onCheckIn != nil }

    private var isEasing: Bool { proposal.direction == .down }

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    /// Side by side, the plan and the proposal ran off the screen at the accessibility sizes.
    private var pairLayout: AnyLayout {
        dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: SharpitSpacing.sm))
            : AnyLayout(HStackLayout(alignment: .top, spacing: SharpitSpacing.sm))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: SharpitSpacing.md) {
            SharpitCardHeader(
                title: proposal.changeSummary,
                symbol: isEasing ? "moon.zzz.fill" : "bolt.heart.fill",
                subtitle: isEasing ? "Ta nuit propose d'alléger" : "Ta nuit permet d'en faire plus",
                showsChevron: false
            )

            Text(proposal.why)
                .font(SharpitTypography.body)
                .foregroundStyle(SharpitColor.mutedForeground)
                .fixedSize(horizontal: false, vertical: true)

            pairLayout {
                side("Prévu", proposal.from, emphasized: false)
                Image(systemName: dynamicTypeSize.isAccessibilitySize ? "arrow.down" : "arrow.right")
                    .font(SharpitTypography.label)
                    .foregroundStyle(SharpitColor.mutedForeground)
                    .padding(.top, dynamicTypeSize.isAccessibilitySize ? 0 : 18)
                    .accessibilityHidden(true)
                side("Proposé", proposal.to, emphasized: true)
            }

            if invitesCheckIn, let onCheckIn {
                checkInInvitation(onCheckIn)
            }

            pairLayout {
                SharpitPrimaryButton(title: "Garder le plan", style: .secondary) { onAnswer(false) }
                SharpitPrimaryButton(title: isEasing ? "Alléger" : "Augmenter") { onAnswer(true) }
            }
        }
        .padding(SharpitSpacing.cardPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .sharpitSurface(.panel)
    }

    /// Read from the night alone so far: the check-in adds how the athlete feels.
    private func checkInInvitation(_ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: SharpitSpacing.sm) {
                SharpitIconTile(symbol: "face.smiling", size: 32)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Lue sur ta nuit seulement")
                        .font(SharpitTypography.bodyEmphasis)
                        .foregroundStyle(SharpitColor.foreground)
                    Text("Fais ton check-in du matin : la proposition s'affine avec ton ressenti.")
                        .font(SharpitTypography.meta)
                        .foregroundStyle(SharpitColor.mutedForeground)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(SharpitColor.mutedForeground.opacity(0.45))
                    .accessibilityHidden(true)
            }
            .padding(SharpitSpacing.sm)
            .sharpitConcentricBackground(SharpitColor.insetGroup, minimum: SharpitRadius.row)
            .contentShape(Rectangle())
        }
        .buttonStyle(.sharpitPressable)
        .accessibilityHint("Ouvre le check-in du matin")
    }

    private func side(_ caption: String, _ side: V1TodayMorningProposal.Side, emphasized: Bool) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(caption)
                .font(SharpitTypography.system(size: 15, weight: .regular, relativeTo: .subheadline))
                .foregroundStyle(SharpitColor.mutedForeground)
            // A narrow column (iPhone mini) breaks between intensity and duration, never inside them.
            ViewThatFits(in: .horizontal) {
                Text(MorningProposalReadout.headline(side)).lineLimit(1)
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(MorningProposalReadout.headlineParts(side), id: \.self) { Text($0) }
                }
            }
            .font(SharpitTypography.system(size: 17, weight: .bold, relativeTo: .body, digits: true))
            .foregroundStyle(emphasized ? SharpitColor.foreground : SharpitColor.mutedForeground)
            if let description = side.description, !description.isEmpty {
                Text(description)
                    .font(SharpitTypography.meta)
                    .foregroundStyle(SharpitColor.mutedForeground)
                    .lineLimit(2)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

enum MorningProposalReadout {
    /// « Endurance · 35 min », either half alone, or « Séance » when the server sent neither.
    static func headline(_ side: V1TodayMorningProposal.Side) -> String {
        headlineParts(side).joined(separator: " · ")
    }

    /// The headline's halves, for a column too narrow to hold them on one line.
    static func headlineParts(_ side: V1TodayMorningProposal.Side) -> [String] {
        let parts = [side.intensityLabel, side.durationMin.map { "\($0) min" }].compactMap { $0 }
        return parts.isEmpty ? ["Séance"] : parts
    }
}
