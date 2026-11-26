import SwiftUI

/// Where something SHARPIT adds (an analysis, a computed metric) would sit, below SharpIt Pro:
/// its name, what it brings, and the way to Pro. The athlete's own data is never behind one.
struct SharpitProTeaser: View {
    let title: String
    let message: String

    @Environment(ProStore.self) private var pro: ProStore?
    @State private var isShowingPaywall = false

    var body: some View {
        if let pro {
            Button { isShowingPaywall = true } label: { content }
                .buttonStyle(.sharpitPressable)
                .accessibilityHint("Ouvre SharpIt Pro")
                .sheet(isPresented: $isShowingPaywall) { SharpitProPaywallSheet(store: pro) }
        } else {
            content
        }
    }

    /// Clinique's « hors Pro » state (`docs/adr/0035`): what the feature is over the Pro pill, what
    /// it does in a sentence, and one ink button — in a card bordered in the coach's tone.
    private var content: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline, spacing: SharpitSpacing.xs) {
                Text(title)
                    .font(SharpitTypography.system(size: 17, weight: .semibold, relativeTo: .body))
                    .foregroundStyle(SharpitColor.foreground)
                    .multilineTextAlignment(.leading)
                Spacer(minLength: 0)
                CliniqueStatusPill("Pro", status: .pro)
            }
            Text(message)
                .font(SharpitTypography.system(size: 15, weight: .regular, relativeTo: .subheadline))
                .foregroundStyle(SharpitColor.slate)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
            Text("Voir Pro")
                .font(SharpitTypography.system(size: 15, weight: .semibold, relativeTo: .subheadline))
                .foregroundStyle(SharpitColor.primaryForeground)
                .padding(.horizontal, 22)
                .frame(minHeight: SharpitSpacing.minimumTouchTarget)
                .background(SharpitColor.primary, in: Capsule())
        }
        .cliniqueCard(border: SharpitColor.pillarCoach.opacity(0.35))
        .accessibilityElement(children: .combine)
    }
}
