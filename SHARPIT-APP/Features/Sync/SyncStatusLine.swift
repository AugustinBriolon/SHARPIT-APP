import SwiftUI

/// How fresh the day's data is, in one quiet line above the verdict.
struct SyncStatusLine: View {
    let sync: ProviderSyncStore

    var body: some View {
        TimelineView(.periodic(from: .now, by: 60)) { context in
            if let caption = SyncReadout.caption(state: sync.state, lastSyncAt: sync.lastSyncAt, now: context.date) {
                HStack(spacing: SharpitSpacing.xxs + 2) {
                    if sync.state == .syncing {
                        ProgressView().controlSize(.mini)
                    } else {
                        Image(systemName: sync.state == .failed ? "exclamationmark.arrow.triangle.2.circlepath" : "checkmark.circle")
                            .foregroundStyle(sync.state == .failed ? SharpitColor.signalCaution : SharpitColor.mutedForeground)
                    }
                    Text(caption)
                        .contentTransition(.opacity)
                }
                .font(SharpitTypography.meta)
                .foregroundStyle(SharpitColor.mutedForeground)
                .frame(maxWidth: .infinity, alignment: .leading)
                .animation(SharpitMotion.fade, value: caption)
                .accessibilityElement(children: .combine)
            }
        }
    }
}
