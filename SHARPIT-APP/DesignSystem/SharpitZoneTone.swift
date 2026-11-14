import SwiftUI

/// The five training zones, easy to hard, in Clinique's intensity scale (blue, green, yellow,
/// orange, red — `--zone-1` … `--zone-5`). Every zone bar and the coloured route read them here.
enum SharpitZoneTone {
    static func color(_ index: Int) -> Color {
        [SharpitColor.zone1, SharpitColor.zone2, SharpitColor.zone3, SharpitColor.zone4, SharpitColor.zone5][min(max(index, 0), 4)]
    }
}
