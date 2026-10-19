import SwiftUI

/// Glyphs SF Symbols has no drawing for, kept as custom symbols in `SharedSymbols.xcassets`
/// (compiled into the app and the widgets).
nonisolated enum SharpitCustomSymbol {
    /// Three rings: swim, bike, run.
    static let triathlon = "triathlon.circles"

    /// VoiceOver label per custom symbol; a name absent here is an SF Symbol.
    static let accessibilityLabels = [triathlon: String(localized: "Triathlon")]
}

extension Image {
    /// An SF Symbol, or one of the app's own symbols (`SharpitCustomSymbol`) — same sizing,
    /// weight and foreground style either way.
    init(sharpitSymbol name: String) {
        if let label = SharpitCustomSymbol.accessibilityLabels[name] {
            self.init(name, label: Text(label))
        } else {
            self.init(systemName: name)
        }
    }
}
