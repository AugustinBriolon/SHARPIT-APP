import CoreGraphics
import Foundation

/// Vertical dismiss math for in-app banners (toast / ressenti reminder).
///
/// Swipe **up** follows the finger; closes past ~40 % of height or on a fast flick;
/// otherwise springs back. Downward drag is rubber-banded. Pure — unit-tested, no UIKit.
nonisolated enum SharpitBannerDismiss {
    /// Fraction of banner height that commits a dismiss when dragged up.
    static let closeFraction: CGFloat = 0.40
    /// Upward flick (pt/s, SwiftUI y grows downward → negative is up).
    static let flickVelocity: CGFloat = -900
    /// UIScrollView-style rubber band for downward overscroll.
    static let rubberBand: CGFloat = 0.55
    /// Same coast factor as `DaySwipe.deceleration`.
    static let deceleration: CGFloat = 0.998

    /// Offset under the finger: free upward, resisted downward.
    static func offset(translationY: CGFloat, height: CGFloat) -> CGFloat {
        if translationY <= 0 { return translationY }
        let limit = max(height, 1)
        let resisted = (1 - 1 / (translationY * rubberBand / limit + 1)) * limit
        return resisted
    }

    /// Where a released drag would rest, coasting as a scroll view does.
    static func projected(translationY: CGFloat, velocityY: CGFloat) -> CGFloat {
        let coast = deceleration / (1 - deceleration) / 1000
        return translationY + velocityY * coast
    }

    /// Whether the gesture should dismiss (up past 40 % or a fast upward flick).
    static func shouldDismiss(
        height: CGFloat,
        translationY: CGFloat,
        velocityY: CGFloat
    ) -> Bool {
        guard translationY < 0 || velocityY < 0 else { return false }
        let threshold = max(height, 1) * closeFraction
        if -translationY >= threshold { return true }
        if velocityY <= flickVelocity { return true }
        let predicted = projected(translationY: translationY, velocityY: velocityY)
        return -predicted >= threshold
    }
}
