import SwiftUI
import UIKit

/// On a screen that shows one day, a horizontal swipe means two things depending on where it
/// starts: from the left edge, back (the system's pop); anywhere else, the day before (to the
/// right) or the day after (to the left). iOS 26 pops from anywhere on the screen, so these
/// screens keep its edge gesture only.
///
/// The day turns as Apple's own day views do: the page follows the finger, holds back where no
/// day lies (after today), and leaves on the side it was pushed to while the next day comes in
/// from the other. A day picked in the strip or the calendar comes in from its side of time —
/// later from the right, earlier from the left. With Reduce Motion, the day only fades in.
///
/// A finger that starts on a row or a button and slides sideways turns the day without opening
/// what it touched: the turn is a UIKit pan that refuses vertical drags (the scroll keeps them)
/// and, once it begins, is exclusive, so UIKit fails the control's pending tap — the contract
/// `UIScrollView` keeps with its content.
nonisolated enum DaySwipe {
    enum Step: Equatable { case previous, next }
    enum Axis: Equatable { case horizontal, vertical }

    /// The band along the left edge that stays the system's back gesture.
    static let edgeWidth: CGFloat = 28
    /// A day turns past this horizontal travel…
    static let minimumTravel: CGFloat = 60
    /// …when the swipe is clearly more sideways than vertical (scrolling wins otherwise).
    static let dominance: CGFloat = 1.6
    /// A shorter swipe still turns the day when it is thrown at least this far.
    static let flickTravel: CGFloat = 180
    /// How far a picked day comes in from: a nudge that says which way time went, not a page.
    static let pickTravel: CGFloat = 56
    /// How far past nothing the page gives before it resists, as a scroll view's edge does.
    static let rubberBand: CGFloat = 0.55
    /// Travel under which a touch is still undecided between a tap, a scroll and a turn.
    static let decisionTravel: CGFloat = 10
    /// UIScrollView's normal deceleration, per millisecond: how far a released drag coasts.
    static let deceleration: CGFloat = 0.998

    static func step(startX: CGFloat, translation: CGSize, predictedEnd: CGSize? = nil) -> Step? {
        guard axis(startX: startX, translation: translation) == .horizontal else { return nil }
        let dx = translation.width
        if abs(dx) >= minimumTravel { return dx > 0 ? .previous : .next }
        // A flick: short, but thrown the same way.
        if let thrown = predictedEnd?.width, abs(thrown) >= flickTravel, (thrown > 0) == (dx > 0) {
            return dx > 0 ? .previous : .next
        }
        return nil
    }

    /// Whether a drag is turning the day or scrolling the page.
    static func axis(startX: CGFloat, translation: CGSize) -> Axis {
        guard startX > edgeWidth, translation.width != 0,
              abs(translation.width) >= abs(translation.height) * dominance
        else { return .vertical }
        return .horizontal
    }

    /// Nil while the finger has barely moved; then whether the drag is a day turn rather than
    /// a scroll, a tap or the edge's back gesture.
    static func isTurn(startX: CGFloat, translation: CGSize) -> Bool? {
        guard hypot(translation.width, translation.height) >= decisionTravel else { return nil }
        return axis(startX: startX, translation: translation) == .horizontal
    }

    /// Where a released drag would come to rest, coasting as a scroll view does.
    static func projected(_ translation: CGSize, velocity: CGSize) -> CGSize {
        let coast = deceleration / (1 - deceleration) / 1000
        return CGSize(
            width: translation.width + velocity.width * coast,
            height: translation.height + velocity.height * coast
        )
    }

    /// Where the page sits under the finger: with it when a day lies that way, held back
    /// (UIScrollView's rubber band) when none does.
    static func offset(for dx: CGFloat, canTurn: Bool, width: CGFloat) -> CGFloat {
        guard !canTurn else { return dx }
        let limit = max(width, 1)
        let resisted = (1 - 1 / (abs(dx) * rubberBand / limit + 1)) * limit
        return dx < 0 ? -resisted : resisted
    }

    /// Which way time went between two days; nil for the same day.
    static func step(from old: Date, to new: Date, calendar: Calendar = .current) -> Step? {
        let old = calendar.startOfDay(for: old)
        let new = calendar.startOfDay(for: new)
        if new == old { return nil }
        return new > old ? .next : .previous
    }

    /// The day a step lands on; never past today.
    static func day(after step: Step, from day: Date, today: Date = .now, calendar: Calendar = .current) -> Date? {
        let offset = step == .previous ? -1 : 1
        guard let target = calendar.date(byAdding: .day, value: offset, to: day) else { return nil }
        if step == .next, calendar.startOfDay(for: target) > calendar.startOfDay(for: today) { return nil }
        return target
    }

    /// The day after comes in from the right (the trailing side), the day before from the left.
    static func entrySign(_ step: Step) -> CGFloat { step == .next ? 1 : -1 }
}

/// Where a new day's page starts before it settles.
nonisolated private struct DayArrival: Equatable {
    var offset: CGFloat = 0
    var opacity: Double = 1
}

private struct DaySwipeModifier: ViewModifier {
    let day: Date
    let onSelect: (Date) -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// Where the finger holds the page while it drags.
    @State private var dragOffset: CGFloat = 0
    /// Where the page rests once the finger is gone: home, or aside while it leaves.
    @State private var restingOffset: CGFloat = 0
    @State private var width: CGFloat = 390
    /// The step a swipe committed to, until the day it asked for shows.
    @State private var pendingStep: DaySwipe.Step?
    @State private var arrival = DayArrival()
    @State private var arrivals = 0

    func body(content: Content) -> some View {
        let arrival = arrival
        return content
            .contentShape(.rect)
            .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width = $0 }
            .keyframeAnimator(initialValue: DayArrival(), trigger: arrivals) { page, value in
                page
                    .offset(x: value.offset)
                    .opacity(value.opacity)
            } keyframes: { _ in
                KeyframeTrack(\.offset) {
                    MoveKeyframe(arrival.offset)
                    SpringKeyframe(0, duration: 0.42, spring: .snappy)
                }
                KeyframeTrack(\.opacity) {
                    MoveKeyframe(arrival.opacity)
                    LinearKeyframe(1, duration: 0.22)
                }
            }
            .offset(x: restingOffset + dragOffset)
            .gesture(DayTurnGesture(onChange: follow, onEnd: end, onCancel: settle))
            .onChange(of: day) { old, new in arrive(from: old, to: new) }
            .background(EdgeOnlyPopGesture())
    }

    private var canTurnNext: Bool { DaySwipe.day(after: .next, from: day) != nil }

    private func follow(_ translation: CGSize) {
        guard !reduceMotion, pendingStep == nil else { return }
        let dx = translation.width
        dragOffset = DaySwipe.offset(for: dx, canTurn: dx > 0 || canTurnNext, width: width)
    }

    /// A turn the system took back: the page goes home.
    private func settle() {
        restingOffset += dragOffset
        dragOffset = 0
        withAnimation(SharpitMotion.selection) { restingOffset = 0 }
    }

    private func end(_ release: DayTurnRelease) {
        // Pick the page up where the finger left it.
        let released = dragOffset
        dragOffset = 0
        guard pendingStep == nil else { return }
        restingOffset = released

        let predictedEnd = DaySwipe.projected(release.translation, velocity: release.velocity)
        guard let step = DaySwipe.step(startX: release.startX, translation: release.translation, predictedEnd: predictedEnd),
              let target = DaySwipe.day(after: step, from: day)
        else {
            withAnimation(SharpitMotion.selection) { restingOffset = 0 }
            return
        }
        guard !reduceMotion else {
            onSelect(target)
            return
        }

        pendingStep = step
        // The page keeps the finger's speed on its way out.
        let exit = -DaySwipe.entrySign(step) * width
        let speed = max(abs(release.velocity.width), 900)
        let duration = min(max(abs(exit - released) / speed, 0.12), 0.24)
        withAnimation(.easeOut(duration: duration)) {
            restingOffset = exit
        } completion: {
            onSelect(target)
            Task {
                // A day that never comes (refused, or the screen moved on) gives the page back.
                try? await Task.sleep(for: .milliseconds(800))
                guard pendingStep == step else { return }
                pendingStep = nil
                withAnimation(SharpitMotion.reveal) { restingOffset = 0 }
            }
        }
    }

    private func arrive(from old: Date, to new: Date) {
        let swiped = pendingStep
        pendingStep = nil
        guard let step = swiped ?? DaySwipe.step(from: old, to: new) else { return }
        var still = Transaction()
        still.disablesAnimations = true
        withTransaction(still) { restingOffset = 0 }
        if reduceMotion {
            arrival = DayArrival(offset: 0, opacity: 0)
        } else if swiped != nil {
            // The whole page, from the side the finger pulled it from.
            arrival = DayArrival(offset: DaySwipe.entrySign(step) * width, opacity: 1)
        } else {
            arrival = DayArrival(offset: DaySwipe.entrySign(step) * DaySwipe.pickTravel, opacity: 0)
        }
        arrivals += 1
    }
}

extension View {
    /// Swipe right for the day before, left for the day after; back stays on the left edge.
    /// Every change of `day`, swiped or picked, slides the new day in from its side.
    func daySwipe(day: Date, onSelect: @escaping (Date) -> Void) -> some View {
        modifier(DaySwipeModifier(day: day, onSelect: onSelect))
    }
}

/// Turns off iOS 26's pop-from-anywhere while the screen shows, so a swipe in the middle
/// changes the day; the edge pop is untouched.
private struct EdgeOnlyPopGesture: UIViewControllerRepresentable {
    func makeUIViewController(context: Context) -> Controller { Controller() }
    func updateUIViewController(_ controller: Controller, context: Context) {}

    final class Controller: UIViewController {
        override func viewDidLoad() {
            super.viewDidLoad()
            view.isUserInteractionEnabled = false
            view.backgroundColor = .clear
        }

        override func viewDidAppear(_ animated: Bool) {
            super.viewDidAppear(animated)
            setContentPop(enabled: false)
        }

        override func viewWillDisappear(_ animated: Bool) {
            super.viewWillDisappear(animated)
            setContentPop(enabled: true)
        }

        private func setContentPop(enabled: Bool) {
            if #available(iOS 26.0, *) {
                navigationController?.interactiveContentPopGestureRecognizer?.isEnabled = enabled
            }
        }
    }
}

/// A day turn as it was let go, in window coordinates.
nonisolated struct DayTurnRelease: Equatable {
    var startX: CGFloat
    var translation: CGSize
    var velocity: CGSize
}

/// A pan that fails as soon as the finger moves more vertically than sideways, or starts on the
/// back-gesture edge, so the scroll view and the navigation pop keep those touches. It never
/// recognizes alongside other gestures: once it begins, UIKit fails the tap of the control under
/// the finger instead of letting it fire on lift.
private final class DayTurnRecognizer: UIPanGestureRecognizer {
    private var start: CGPoint = .zero
    /// The finger, read from the touches themselves: the pan's own location only follows the
    /// moves handed to `super`, which an undecided turn holds back.
    private var current: CGPoint = .zero

    /// Travel since touch-down, unlike `translation(in:)`, which starts after the pan's own slop.
    var travel: CGSize {
        CGSize(width: current.x - start.x, height: current.y - start.y)
    }

    override init(target: Any?, action: Selector?) {
        super.init(target: target, action: action)
        maximumNumberOfTouches = 1
    }

    /// A scroll view's pan never stops a turn: on a real finger it can begin first, on a few
    /// points of travel, and would otherwise fail the turn before it is decided.
    override func canBePrevented(by preventingGestureRecognizer: UIGestureRecognizer) -> Bool {
        guard !(preventingGestureRecognizer.view is UIScrollView) else { return false }
        return super.canBePrevented(by: preventingGestureRecognizer)
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) {
        if state == .possible, let touch = touches.first {
            start = touch.location(in: nil)
            current = start
        }
        super.touchesBegan(touches, with: event)
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent) {
        if let touch = touches.first {
            current = touch.location(in: nil)
        }
        if state == .possible {
            switch DaySwipe.isTurn(startX: start.x, translation: travel) {
            case nil:
                return
            case false?:
                state = .failed
                return
            case true?:
                break
            }
        }
        super.touchesMoved(touches, with: event)
    }
}

private struct DayTurnGesture: UIGestureRecognizerRepresentable {
    let onChange: (CGSize) -> Void
    let onEnd: (DayTurnRelease) -> Void
    let onCancel: () -> Void

    func makeUIGestureRecognizer(context: Context) -> DayTurnRecognizer {
        DayTurnRecognizer()
    }

    func handleUIGestureRecognizerAction(_ recognizer: DayTurnRecognizer, context: Context) {
        switch recognizer.state {
        case .began, .changed:
            onChange(recognizer.travel)
        case .ended:
            let travel = recognizer.travel
            let velocity = recognizer.velocity(in: nil)
            onEnd(DayTurnRelease(
                startX: recognizer.location(in: nil).x - travel.width,
                translation: travel,
                velocity: CGSize(width: velocity.x, height: velocity.y)
            ))
        case .cancelled, .failed:
            onCancel()
        default:
            break
        }
    }
}
