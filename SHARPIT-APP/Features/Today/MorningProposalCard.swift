import SwiftUI

/// The night's proposal for today's session, under the verdict: what changes in one line, why in
/// one sentence, one tap to take it or keep the plan. The plan and the proposal side by side wait
/// under « Voir le détail ». It shows only while the server waits for an answer, after the night.
struct MorningProposalCard: View {
    let proposal: V1TodayMorningProposal
    /// Opens the morning check-in, which refines the proposal; nil where it cannot be opened.
    var onCheckIn: (() -> Void)?
    let onAnswer: (_ accept: Bool) -> Void

    @State private var showsDetail = false

    private var invitesCheckIn: Bool { proposal.checkInDone == false && onCheckIn != nil }

    private var isEasing: Bool { proposal.direction == .down }

    var body: some View {
        VStack(alignment: .leading, spacing: SharpitSpacing.md) {
            SharpitCardHeader(
                title: isEasing ? "Ta nuit propose d'alléger" : "Ta nuit permet d'en faire plus",
                symbol: isEasing ? "moon.zzz.fill" : "bolt.heart.fill",
                subtitle: MorningProposalReadout.change(from: proposal.from, to: proposal.to),
                showsChevron: false
            )

            Text(proposal.why)
                .font(SharpitTypography.meta)
                .foregroundStyle(SharpitColor.mutedForeground)
                .fixedSize(horizontal: false, vertical: true)

            if showsDetail {
                VStack(alignment: .leading, spacing: SharpitSpacing.sm) {
                    side("Prévu", proposal.from, emphasized: false)
                    side("Proposé", proposal.to, emphasized: true)
                }
                .transition(.opacity)
            }

            Button {
                withAnimation(SharpitMotion.reveal) { showsDetail.toggle() }
            } label: {
                Label(showsDetail ? "Masquer le détail" : "Voir le détail",
                      systemImage: showsDetail ? "chevron.up" : "chevron.down")
                    .labelStyle(.titleAndIcon)
                    .font(SharpitTypography.meta.weight(.semibold))
                    .foregroundStyle(SharpitColor.foreground)
                    .contentShape(.rect)
            }
            .buttonStyle(.plain)

            if invitesCheckIn, let onCheckIn {
                checkInInvitation(onCheckIn)
            }

            HStack(spacing: SharpitSpacing.md) {
                Button("Garder le plan") { onAnswer(false) }
                    .font(SharpitTypography.system(size: 17, weight: .semibold, relativeTo: .headline))
                    .foregroundStyle(SharpitColor.mutedForeground)
                    .buttonStyle(.sharpitPressable)
                    .fixedSize()
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
            HStack(spacing: SharpitSpacing.xs) {
                Image(systemName: "face.smiling")
                    .accessibilityHidden(true)
                Text("Affine avec ton check-in du matin")
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(SharpitColor.mutedForeground.opacity(0.45))
                    .accessibilityHidden(true)
            }
            .font(SharpitTypography.meta)
            .foregroundStyle(SharpitColor.foreground)
            .contentShape(.rect)
        }
        .buttonStyle(.sharpitPressable)
        .accessibilityHint("Lue sur ta nuit seulement. Ouvre le check-in du matin")
    }

    private func side(_ caption: String, _ side: V1TodayMorningProposal.Side, emphasized: Bool) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("\(caption) · \(MorningProposalReadout.headline(side))")
                .font(SharpitTypography.bodyEmphasis)
                .foregroundStyle(emphasized ? SharpitColor.foreground : SharpitColor.mutedForeground)
            if let description = side.description, !description.isEmpty {
                Text(description)
                    .font(SharpitTypography.meta)
                    .foregroundStyle(SharpitColor.mutedForeground)
                    .fixedSize(horizontal: false, vertical: true)
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

    /// « Endurance 75 min → Récupération 55 min »: the whole change, for the card's one line.
    static func change(from: V1TodayMorningProposal.Side, to: V1TodayMorningProposal.Side) -> String {
        "\(headlineParts(from).joined(separator: " ")) → \(headlineParts(to).joined(separator: " "))"
    }

    /// The headline's halves, for a column too narrow to hold them on one line.
    static func headlineParts(_ side: V1TodayMorningProposal.Side) -> [String] {
        let parts = [side.intensityLabel, side.durationMin.map { "\($0) min" }].compactMap { $0 }
        return parts.isEmpty ? ["Séance"] : parts
    }
}
