import SwiftUI

extension View {
    /// Content arriving on a screen: faded in over a few points of rise (`SharpitMotion.arrival`),
    /// the same on every screen. Reduce Motion keeps the fade and drops the travel.
    func arrived(_ isVisible: Bool, delay: TimeInterval = 0) -> some View {
        opacity(isVisible ? 1 : 0)
            .offset(y: isVisible || SharpitMotion.reduceMotion ? 0 : SharpitMotion.arrivalTravel)
            .animation(
                SharpitMotion.arrival.delay(SharpitMotion.reduceMotion ? 0 : delay),
                value: isVisible
            )
    }

    /// Content arriving in order, with the capped stagger `SharpitMotion` owns, so a screen
    /// composes itself rather than popping in at once.
    func revealed(_ isVisible: Bool, index: Int) -> some View {
        arrived(isVisible, delay: SharpitMotion.staggerDelay(index: index))
    }
}
