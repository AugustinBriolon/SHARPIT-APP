import SwiftUI

extension View {
    /// Content arriving in order: faded and lifted a few points, with the capped stagger
    /// `SharpitMotion` owns, so a screen composes itself rather than popping in at once.
    func revealed(_ isVisible: Bool, index: Int) -> some View {
        opacity(isVisible ? 1 : 0)
            // Reduced motion keeps the fade and drops the travel.
            .offset(y: isVisible || SharpitMotion.reduceMotion ? 0 : 12)
            .animation(SharpitMotion.reveal.delay(SharpitMotion.staggerDelay(index: index)), value: isVisible)
    }
}
