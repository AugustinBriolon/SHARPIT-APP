import SwiftUI

/// A scale answered with one finger: its name, the answer in words, then one track of steps
/// that fills up to the answer. A tap or a slide along the track sets it — the whole row is
/// the target, never a small tile to aim at. Ink only: an answer is not a warning.
struct CliniqueScale: View {
    let title: String
    let values: [Int]
    let selection: Int?
    /// What a step stands for, « Dur »; nil where the scale has no word for it.
    var word: (Int) -> String? = { _ in nil }
    /// What the two ends of the track mean.
    let ends: (low: String, high: String)
    let onPick: (Int) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                Text(title)
                    .font(SharpitTypography.system(size: 16, weight: .semibold, relativeTo: .body))
                    .foregroundStyle(SharpitColor.foreground)
                Spacer(minLength: SharpitSpacing.xs)
                Text(CliniqueScaleReadout.answer(selection, outOf: values.last ?? 0, word: selection.flatMap(word)))
                    .font(SharpitTypography.system(size: 15, weight: selection == nil ? .regular : .semibold, relativeTo: .subheadline, digits: true))
                    .foregroundStyle(selection == nil ? SharpitColor.slate : SharpitColor.foreground)
                    .contentTransition(.opacity)
            }
            track
            HStack {
                Text(ends.low)
                Spacer(minLength: SharpitSpacing.xs)
                Text(ends.high)
            }
            .font(SharpitTypography.system(size: 13, weight: .regular, relativeTo: .caption))
            .foregroundStyle(SharpitColor.slate)
        }
        .animation(SharpitMotion.selection, value: selection)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
        .accessibilityValue(CliniqueScaleReadout.answer(selection, outOf: values.last ?? 0, word: selection.flatMap(word)))
        .accessibilityAdjustableAction { direction in
            let current = selection.flatMap(values.firstIndex(of:))
            switch direction {
            case .increment: pick(at: min((current ?? -1) + 1, values.count - 1))
            case .decrement: pick(at: max((current ?? 1) - 1, 0))
            @unknown default: break
            }
        }
    }

    /// The steps as one track, 44 pt tall under the finger though the marks are thin.
    private var track: some View {
        GeometryReader { geo in
            HStack(spacing: 4) {
                ForEach(values, id: \.self) { value in
                    Capsule()
                        .fill(value <= (selection ?? Int.min) ? SharpitColor.foreground : SharpitColor.divider)
                        .frame(height: 10)
                }
            }
            .frame(maxHeight: .infinity)
            .contentShape(.rect)
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { pick(at: CliniqueScaleReadout.step(at: $0.location.x, width: geo.size.width, count: values.count)) }
            )
        }
        .frame(height: 44)
        .onAppear { SharpitHaptics.prepare() }
    }

    private func pick(at index: Int) {
        guard values.indices.contains(index), values[index] != selection else { return }
        SharpitHaptics.play(.notch(major: false))
        onPick(values[index])
    }
}

nonisolated enum CliniqueScaleReadout {
    /// The step under the finger, held inside the track when the finger slides past an end.
    static func step(at x: CGFloat, width: CGFloat, count: Int) -> Int {
        guard width > 0, count > 0 else { return 0 }
        return min(max(Int(x / width * CGFloat(count)), 0), count - 1)
    }

    /// « 7 / 10 · Dur », « 4 / 5 », or « À noter » before any answer.
    static func answer(_ value: Int?, outOf: Int, word: String?) -> String {
        guard let value else { return String(localized: "À noter") }
        return ["\(value) / \(outOf)", word].compactMap { $0 }.joined(separator: " · ")
    }
}
