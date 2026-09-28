import SwiftUI

/// Where the coach is while it works: one line naming what it reads, moving on every few
/// seconds, then what it writes once it writes. Never the model's raw reasoning. Shared by the
/// week generator and the plan adjustment, so every wait on the coach reads the same.
struct CoachWorkingHeader: View {
    /// What the coach goes through before writing, in order. Each fits one line on the
    /// narrowest iPhone: a line that wrapped moved everything under it each time it changed.
    let readingSteps: [String]
    /// Under the reading lines.
    let readingDetail: String
    /// Once the coach writes, its stage replaces the reading lines.
    var writingTitle: String?
    var writingDetail: String?
    /// Under the stage, e.g. that the sheet can close.
    var note: String?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var readingStep = 0

    private var isReading: Bool { writingTitle == nil }

    private var title: String {
        writingTitle ?? readingSteps[min(readingStep, readingSteps.count - 1)]
    }

    var body: some View {
        HStack(alignment: .top, spacing: SharpitSpacing.sm) {
            ProgressView()
                .controlSize(.regular)
                .padding(.top, 2)
            VStack(alignment: .leading, spacing: SharpitSpacing.xxs) {
                Text(title)
                    .font(SharpitTypography.sectionTitle)
                    .foregroundStyle(SharpitColor.foreground)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .id(title)
                    .transition(reduceMotion ? .opacity : .push(from: .bottom).combined(with: .opacity))
                Text(writingDetail ?? readingDetail)
                    .font(SharpitTypography.meta)
                    .foregroundStyle(SharpitColor.mutedForeground)
                    .contentTransition(.numericText())
                if let note {
                    Text(note)
                        .font(SharpitTypography.meta)
                        .foregroundStyle(SharpitColor.mutedForeground)
                }
            }
        }
        .accessibilityElement(children: .combine)
        .animation(SharpitMotion.fade, value: writingDetail)
        .animation(SharpitMotion.reveal, value: title)
        .clipped()
        .task(id: isReading) { await advanceReadingSteps() }
    }

    /// Moves through the reading lines until the coach writes, stopping on the last.
    private func advanceReadingSteps() async {
        while isReading, readingStep < readingSteps.count - 1 {
            try? await Task.sleep(for: .seconds(3))
            guard !Task.isCancelled, isReading else { return }
            readingStep += 1
        }
    }
}

/// The screen's main action, docked under the content: full width, a touch taller than a
/// regular glass button (near the HIG's 44 pt), short of the large size that felt heavy.
struct SharpitPrimaryButton: View {
    let title: String
    var isBusy = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: SharpitSpacing.xs) {
                if isBusy { ProgressView().tint(SharpitColor.primaryForeground) }
                Text(title)
                    .font(SharpitTypography.bodyEmphasis)
                    .foregroundStyle(SharpitColor.primaryForeground)
            }
            .frame(maxWidth: .infinity)
            .frame(minHeight: 30)
        }
        .sharpitGlassButton(prominent: true)
        .tint(SharpitColor.primary)
    }
}

/// A sheet's actions, docked at the bottom over the scrolled content: a fade keeps them
/// readable when a long list passes under them.
struct SharpitActionDock<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        VStack(spacing: SharpitSpacing.xs) { content }
            .padding(.horizontal, SharpitSpacing.pageInset)
            .padding(.vertical, SharpitSpacing.sm)
            .background(
                LinearGradient(
                    colors: [SharpitColor.background.opacity(0), SharpitColor.background.opacity(0.9), SharpitColor.background],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .ignoresSafeArea(edges: .bottom)
            )
    }
}

/// A session's sport, as a tinted round mark — the rows of a generated week and of an
/// adjustment carry the same one.
struct SharpitSportBadge: View {
    let type: V1ActivityType

    var body: some View {
        ZStack {
            Circle().fill(SharpitSportTone.label(for: type).opacity(0.14)).frame(width: 38, height: 38)
            Image(systemName: type.symbolName)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(SharpitSportTone.label(for: type))
        }
        .accessibilityHidden(true)
    }
}

/// Keeps or leaves out a proposal: its own button, since the row around it may open something.
struct SharpitKeepToggle: View {
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(isSelected ? SharpitColor.primary : SharpitColor.mutedForeground.opacity(0.4))
                .contentTransition(.symbolEffect(.replace))
                .frame(width: 44, height: 44)
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .padding(.vertical, -SharpitSpacing.sm)
        .accessibilityLabel(isSelected ? "Retirer" : "Garder")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

extension View {
    /// A placeholder row breathing while the coach works, each a beat after the one above.
    /// Still under Reduce Motion.
    func sharpitPlaceholderPulse(index: Int) -> some View {
        modifier(PlaceholderPulse(index: index))
    }
}

private struct PlaceholderPulse: ViewModifier {
    let index: Int
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .phaseAnimator(reduceMotion ? [1.0] : [1.0, 0.45]) { row, opacity in
                row.opacity(opacity)
            } animation: { _ in
                .easeInOut(duration: 0.9).delay(Double(index) * 0.15)
            }
            .accessibilityHidden(true)
    }
}
