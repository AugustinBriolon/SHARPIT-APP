import SwiftUI

/// The five training zones, easy to hard, in the app's intensity signals — the web's five chart
/// tones. Every zone bar reads them from here.
enum SharpitZoneTone {
    static func color(_ index: Int) -> Color {
        [SharpitColor.signalRecovery, SharpitColor.signalBase, SharpitColor.signalTempo, SharpitColor.signalThreshold, SharpitColor.signalVo2][min(max(index, 0), 4)]
    }
}
