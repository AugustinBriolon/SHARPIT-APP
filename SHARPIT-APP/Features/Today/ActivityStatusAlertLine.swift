import SwiftUI

/// A line shown under the Today verdict plate when the athlete's training mode is not `active`:
/// the mode as a status pill, then when it ends — or, held until changed, the plan's first
/// consequence. Given the store it opens the mode's drawer, so the warning is also the way to
/// lift it.
struct ActivityStatusAlertLine: View {
    let status: ActivityStatusId
    var retention: ActivityStatusRetention = .untilModified
    var store: ActivityStatusStore?

    @State private var isPresented = false

    var body: some View {
        if let store {
            Button { isPresented = true } label: { content }
                .buttonStyle(.sharpitPressable)
                .accessibilityHint("Changer ton statut d'activité")
                .sheet(isPresented: $isPresented) { ActivityStatusDrawer(store: store) }
        } else {
            content
        }
    }

    private var content: some View {
        HStack(spacing: SharpitSpacing.xs) {
            CliniqueStatusPill(status.label, status: status.clinique)
            // Two lines: the longest consequence does not fit beside the pill on a narrow iPhone.
            Text(detail)
                .font(SharpitTypography.system(size: 13, weight: .regular, relativeTo: .caption))
                .foregroundStyle(SharpitColor.slate)
                .multilineTextAlignment(.leading)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            if store != nil {
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(SharpitColor.slate)
                    .accessibilityHidden(true)
            }
        }
        .padding(.vertical, SharpitSpacing.xs)
        .frame(minHeight: SharpitSpacing.minimumTouchTarget)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(status.label). \(status.alertLine)")
    }

    private var detail: String {
        ActivityStatusReadout.resumption(retention) ?? status.effects.first?.text ?? ""
    }
}
