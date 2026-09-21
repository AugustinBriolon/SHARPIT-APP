import SwiftUI

enum SharpitMotion {
    static let revealResponse: Double = 0.32
    static let revealDamping: Double = 0.86
    static let fadeDuration: TimeInterval = 0.28
    static let staggerStep: TimeInterval = 0.048
    static let countUpDuration: TimeInterval = 0.42
    static let gaugeFillDuration: TimeInterval = 0.72
    /// Past this many items a stagger stops adding delay: a long list would otherwise
    /// keep its last rows invisible for more than a second.
    static let maxStaggeredItems = 6
    static let selectionResponse: Double = 0.24
    static let selectionDamping: Double = 0.82

    static var reduceMotion: Bool {
        UIAccessibility.isReduceMotionEnabled
    }

    static var reveal: Animation {
        if reduceMotion {
            return .easeOut(duration: 0.01)
        }
        return .spring(response: revealResponse, dampingFraction: revealDamping)
    }

    static var fade: Animation {
        if reduceMotion {
            return .easeOut(duration: 0.01)
        }
        return .easeOut(duration: fadeDuration)
    }

    /// Overnight gauges: empty → filled with a smooth ease-in-out.
    static var gaugeFill: Animation {
        if reduceMotion {
            return .easeOut(duration: 0.01)
        }
        return .easeInOut(duration: gaugeFillDuration)
    }

    /// A control following the finger — segmented answers, chips. Faster than `reveal`
    /// because the athlete is waiting on it, not watching it.
    static var selection: Animation {
        if reduceMotion {
            return .easeOut(duration: 0.01)
        }
        return .spring(response: selectionResponse, dampingFraction: selectionDamping)
    }

    static func staggerDelay(index: Int) -> TimeInterval {
        reduceMotion ? 0 : Double(min(max(index, 0), maxStaggeredItems)) * staggerStep
    }

    static func run(_ animation: Animation = reveal, _ body: () -> Void) {
        if reduceMotion {
            var transaction = Transaction()
            transaction.disablesAnimations = true
            withTransaction(transaction, body)
        } else {
            withAnimation(animation, body)
        }
    }
}
