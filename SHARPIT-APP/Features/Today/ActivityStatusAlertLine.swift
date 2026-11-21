import SwiftUI

/// A one-line alert shown under the Today verdict plate when the athlete's training
/// mode is not `active`.
///
/// Uses `ActivityStatusId` for copy and tone — no new store, no second button. The mode
/// chip in the controls row remains the only way to change the mode; this line only warns.
struct ActivityStatusAlertLine: View {
    let status: ActivityStatusId

    var body: some View {
        HStack(spacing: SharpitSpacing.xs) {
            Image(systemName: status.symbolName)
                .font(SharpitTypography.label)
                .foregroundStyle(status.tone)
                .accessibilityHidden(true)

            Text(status.alertLine)
                .font(SharpitTypography.bodyEmphasis)
                .foregroundStyle(SharpitColor.foreground)
        }
        .padding(.horizontal, SharpitSpacing.sm)
        .padding(.vertical, SharpitSpacing.xs)
        .background(status.tone.opacity(0.08), in: Capsule())
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(status.label). \(status.alertLine)")
    }
}
