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
/// Once the drag is a day turn, child controls (rows, toggles, sheets) must not fire: a finger
/// that started on a button and slid sideways is turning the day, not opening what it touched.
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
    /// After a horizontal turn, keep buttons mute this long so a lift cannot also open them.
    static let hitSuppression: Duration = .milliseconds(200)
    /// Sideways travel that mutes child controls before the drag qualifies as a full day turn.
    /// UIScrollView cancels content touches on a similar slop; without this, a Button still fires.
    static let childMuteTravel: CGFloat = 10

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

    /// Child hits stay live while scrolling; once the drag is a day turn, they must not.
    static func blocksChildHits(axis: Axis?) -> Bool {
        axis == .horizontal
    }

    /// Mute child activation as soon as the finger has clearly moved sideways — earlier than
    /// ``axis`` / ``minimumTravel``, so a meal row or coach chip under the finger cannot open.
    static func suppressesChildActivation(startX: CGFloat, translation: CGSize) -> Bool {
        guard startX > edgeWidth else { return false }
        let dx = abs(translation.width)
        let dy = abs(translation.height)
        guard dx >= childMuteTravel else { return false }
        return dx >= dy
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

/// The drag under way, reset by the system when the finger lifts or the gesture is cancelled,
/// so a page can never stay stuck aside.
nonisolated private struct DaySwipeDrag: Equatable {
    var axis: DaySwipe.Axis?
    var offset: CGFloat = 0
    /// Sticky for the gesture lifetime: sideways travel (or a locked horizontal axis).
    var suppressesChildren = false
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
    @GestureState private var drag = DaySwipeDrag()
    /// Where the page rests once the finger is gone: home, or aside while it leaves.
    @State private var restingOffset: CGFloat = 0
    @State private var width: CGFloat = 390
    /// The step a swipe committed to, until the day it asked for shows.
    @State private var pendingStep: DaySwipe.Step?
    @State private var arrival = DayArrival()
    @State private var arrivals = 0
    /// Sticky mute for child controls: GestureState clears on lift before Button may still fire.
    @State private var blocksHits = false

    func body(content: Content) -> some View {
        let arrival = arrival
        let muted = blocksHits || drag.suppressesChildren
        // Gesture and offset live on the wrapper; child hit-testing + environment mute once the
        // finger has slid sideways, so a control under the touch cannot also open on lift.
        return ZStack {
            content
                .allowsHitTesting(!muted)
                .environment(\.sharpitSuppressesControlActivation, muted)
        }
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
        .offset(x: restingOffset + drag.offset)
        .simultaneousGesture(gesture)
        .onChange(of: day) { old, new in arrive(from: old, to: new) }
        .onChange(of: drag.suppressesChildren) { _, suppresses in
            if suppresses {
                blocksHits = true
            } else if pendingStep == nil, blocksHits {
                // GestureState cleared on lift before a Button may still fire — hold the mute.
                releaseHitsAfterSuppression()
            }
        }
        // UIKit cancels the touch on buttons under a horizontal pan (UIScrollView-like).
        // SwiftUI `allowsHitTesting` alone cannot un-arm a Button that already saw touchDown.
        .background(DaySwipeButtonCancel(onHorizontalPanBegan: {
            blocksHits = true
        }))
        .background(EdgeOnlyPopGesture())
    }

    private var gesture: some Gesture {
        let follows = !reduceMotion && pendingStep == nil
        let canTurnNext = DaySwipe.day(after: .next, from: day) != nil
        let width = width
        return DragGesture(minimumDistance: 12, coordinateSpace: .global)
            .updating($drag) { value, state, _ in
                let startX = value.startLocation.x
                let translation = value.translation
                // Mute children even when Reduce Motion skips the page-follow animation.
                if DaySwipe.suppressesChildActivation(startX: startX, translation: translation) {
                    state.suppressesChildren = true
                }
                guard follows else { return }
                if state.axis == nil {
                    state.axis = DaySwipe.axis(startX: startX, translation: translation)
                }
                guard state.axis == .horizontal else { return }
                state.suppressesChildren = true
                let dx = translation.width
                state.offset = DaySwipe.offset(for: dx, canTurn: dx > 0 || canTurnNext, width: width)
            }
            .onChanged { value in
                let startX = value.startLocation.x
                let translation = value.translation
                let axis = DaySwipe.axis(startX: startX, translation: translation)
                if DaySwipe.suppressesChildActivation(startX: startX, translation: translation)
                    || DaySwipe.blocksChildHits(axis: axis)
                {
                    blocksHits = true
                }
            }
            .onEnded { value in end(value, canTurnNext: canTurnNext) }
    }

    private func end(_ value: DragGesture.Value, canTurnNext: Bool) {
        guard pendingStep == nil else { return }
        let startX = value.startLocation.x
        let dx = value.translation.width
        let axis = DaySwipe.axis(startX: startX, translation: value.translation)
        // Pick the page up where the finger left it.
        let released = reduceMotion || axis == .vertical
            ? 0
            : DaySwipe.offset(for: dx, canTurn: dx > 0 || canTurnNext, width: width)
        restingOffset = released

        guard let step = DaySwipe.step(startX: startX, translation: value.translation, predictedEnd: value.predictedEndTranslation),
              let target = DaySwipe.day(after: step, from: day)
        else {
            withAnimation(SharpitMotion.selection) { restingOffset = 0 }
            releaseHitsAfterSuppression()
            return
        }
        // A committed turn keeps hits muted until the new day lands (or the timeout below).
        blocksHits = true
        guard !reduceMotion else {
            onSelect(target)
            releaseHitsAfterSuppression()
            return
        }

        pendingStep = step
        // The page keeps the finger's speed on its way out.
        let exit = -DaySwipe.entrySign(step) * width
        let speed = max(abs(value.velocity.width), 900)
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
                blocksHits = false
                withAnimation(SharpitMotion.reveal) { restingOffset = 0 }
            }
        }
    }

    private func arrive(from old: Date, to new: Date) {
        let swiped = pendingStep
        pendingStep = nil
        blocksHits = false
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

    /// GestureState resets before a Button may still fire on lift — hold the mute briefly.
    private func releaseHitsAfterSuppression() {
        Task { @MainActor in
            try? await Task.sleep(for: DaySwipe.hitSuppression)
            guard pendingStep == nil else { return }
            blocksHits = false
        }
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

/// A horizontal pan on the day page cancels touches in controls underneath — the same contract
/// as `UIScrollView.canCancelContentTouches`, so a finger that started on a meal row or coach
/// chip and slid sideways turns the day without opening what it touched. Vertical pans never
/// begin, so ScrollView keeps the scroll.
private struct DaySwipeButtonCancel: UIViewRepresentable {
    var onHorizontalPanBegan: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onHorizontalPanBegan: onHorizontalPanBegan)
    }

    func makeUIView(context: Context) -> BridgeView {
        let view = BridgeView()
        view.backgroundColor = .clear
        view.isUserInteractionEnabled = false
        context.coordinator.attach(to: view)
        return view
    }

    func updateUIView(_ uiView: BridgeView, context: Context) {
        context.coordinator.onHorizontalPanBegan = onHorizontalPanBegan
        context.coordinator.attach(to: uiView)
    }

    final class BridgeView: UIView {
        var onDidMoveToWindow: (() -> Void)?

        override func didMoveToWindow() {
            super.didMoveToWindow()
            onDidMoveToWindow?()
        }
    }

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        var onHorizontalPanBegan: () -> Void
        private let pan = UIPanGestureRecognizer()
        private weak var bridge: UIView?
        private weak var host: UIView?

        init(onHorizontalPanBegan: @escaping () -> Void) {
            self.onHorizontalPanBegan = onHorizontalPanBegan
            super.init()
            pan.cancelsTouchesInView = true
            pan.delegate = self
            pan.addTarget(self, action: #selector(handlePan(_:)))
            // Match SwiftUI day-swipe slop so a tiny nudge is still a tap.
            pan.minimumNumberOfTouches = 1
            pan.maximumNumberOfTouches = 1
        }

        func attach(to bridge: BridgeView) {
            self.bridge = bridge
            bridge.onDidMoveToWindow = { [weak self] in
                self?.installOnHost()
            }
            installOnHost()
        }

        private func installOnHost() {
            guard let bridge else { return }
            // Prefer the enclosing scroll view (buttons live in its content); else the
            // nearest full-size ancestor in the hosting tree.
            var nextHost: UIView?
            var cursor: UIView? = bridge.superview
            while let current = cursor {
                if current is UIScrollView {
                    nextHost = current
                    break
                }
                if nextHost == nil,
                   current.bounds.width >= bridge.bounds.width,
                   current.bounds.height > bridge.bounds.height + 1
                {
                    nextHost = current
                }
                cursor = current.superview
            }
            nextHost = nextHost ?? bridge.superview
            guard let nextHost, host !== nextHost else { return }
            host?.removeGestureRecognizer(pan)
            nextHost.addGestureRecognizer(pan)
            host = nextHost
        }

        @objc private func handlePan(_ gesture: UIPanGestureRecognizer) {
            if gesture.state == .began {
                onHorizontalPanBegan()
            }
        }

        func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
            guard let pan = gestureRecognizer as? UIPanGestureRecognizer,
                  let view = pan.view
            else { return false }
            let point = pan.translation(in: view)
            let translation = CGSize(width: point.x, height: point.y)
            let startX = pan.location(in: view).x - point.x
            // Same early mute as SwiftUI day-swipe — not the stricter day-turn axis lock.
            return DaySwipe.suppressesChildActivation(startX: startX, translation: translation)
        }

        func gestureRecognizer(
            _ gestureRecognizer: UIGestureRecognizer,
            shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
        ) -> Bool {
            true
        }
    }
}
