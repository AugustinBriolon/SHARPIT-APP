import SwiftUI

/// The first-login wizard, shown full screen after sign-up and before the tabs.
///
/// The web's `/onboarding` rendered natively: the same five steps and the same writes. The
/// progress rail and the back control stay pinned above the step, the step's actions stay
/// docked below it, and only the step itself scrolls.
struct OnboardingView: View {
    @State private var store: OnboardingStore
    let appleHealth: AppleHealthSource
    let syncClient: any SyncServing
    let tokenProvider: () async throws -> String
    /// Called once the bootstrap beat is over — the gate then shows Résumé.
    let onFinished: () -> Void

    init(
        store: OnboardingStore,
        appleHealth: AppleHealthSource,
        syncClient: any SyncServing,
        tokenProvider: @escaping () async throws -> String,
        onFinished: @escaping () -> Void
    ) {
        _store = State(initialValue: store)
        self.appleHealth = appleHealth
        self.syncClient = syncClient
        self.tokenProvider = tokenProvider
        self.onFinished = onFinished
    }

    var body: some View {
        ZStack {
            SharpitCanvasBackground()
            switch store.phase {
            case .loading:
                ProgressView()
                    .controlSize(.large)
                    .tint(SharpitColor.primary)
                    .accessibilityLabel("Chargement de ton profil")
            case .steps:
                steps
                    .transition(.asymmetric(
                        insertion: .opacity,
                        removal: .opacity.combined(with: .scale(scale: 0.98))
                    ))
            case .bootstrap:
                OnboardingBootstrapView(onDone: onFinished)
                    .transition(.opacity.combined(with: .scale(scale: 1.04)))
            }
        }
        .task { await store.load() }
    }

    /// The rail and the actions stay put; only the page between them moves. A step pushes in
    /// from the side the athlete is heading — trailing forward, leading back — the way a
    /// navigation stack does, so the wizard reads as one continuous place.
    private var steps: some View {
        VStack(spacing: 0) {
            OnboardingProgressHeader(step: store.step, isBusy: store.isBusy) {
                store.goBack()
            }

            ZStack {
                OnboardingStepPage(step: store.step) {
                    stepContent
                }
                .id(store.step)
                .transition(.push(from: store.isMovingForward ? .trailing : .leading))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .clipped()

            OnboardingActionBar(store: store)
        }
        .sensoryFeedback(.selection, trigger: store.step)
    }

    @ViewBuilder
    private var stepContent: some View {
        switch store.step {
        case .sports:
            OnboardingSportsStep(store: store)
        case .equipment:
            OnboardingEquipmentStep(store: store)
        case .availability:
            OnboardingAvailabilityStep(store: store)
        case .intention:
            OnboardingIntentionStep(draft: $store.intention)
        case .sources:
            OnboardingSourcesStep(
                appleHealth: appleHealth,
                syncClient: syncClient,
                tokenProvider: tokenProvider
            )
        }
    }
}

/// One step's page: its title, its intro and its content arriving in that order, each a beat
/// after the last, so a new step composes itself rather than appearing all at once.
private struct OnboardingStepPage<Content: View>: View {
    let step: OnboardingStep
    @ViewBuilder let content: Content

    @State private var hasAppeared = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: SharpitSpacing.lg) {
                VStack(alignment: .leading, spacing: SharpitSpacing.xs) {
                    Text(step.title)
                        .font(SharpitTypography.pageTitle)
                        .tracking(SharpitTypography.pageTitleTracking)
                        .foregroundStyle(SharpitColor.foreground)
                        .accessibilityAddTraits(.isHeader)
                        .revealed(hasAppeared, index: 1)
                    Text(step.intro)
                        .font(SharpitTypography.body)
                        .foregroundStyle(SharpitColor.mutedForeground)
                        .fixedSize(horizontal: false, vertical: true)
                        .revealed(hasAppeared, index: 2)
                }

                content
                    .revealed(hasAppeared, index: 3)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, SharpitSpacing.pageInset)
            .padding(.top, SharpitSpacing.md)
            .padding(.bottom, SharpitSpacing.xl)
        }
        .scrollDismissesKeyboard(.interactively)
        .scrollIndicators(.hidden)
        .onAppear { hasAppeared = true }
    }
}

// MARK: - Wayfinding

/// One continuous rail that extends as the athlete advances, with ticks so the remaining steps
/// stay countable. From step 2 the leading label is a back control naming the *previous* step,
/// so the athlete always knows where going back lands — as on the web.
private struct OnboardingProgressHeader: View {
    let step: OnboardingStep
    let isBusy: Bool
    let onBack: () -> Void

    var body: some View {
        VStack(spacing: SharpitSpacing.sm) {
            HStack(spacing: SharpitSpacing.sm) {
                if let previous = step.previous {
                    Button(action: onBack) {
                        Label(previous.label, systemImage: "chevron.left")
                            .font(SharpitTypography.bodyEmphasis)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(SharpitColor.foreground)
                    .disabled(isBusy)
                    .frame(minHeight: SharpitSpacing.minimumTouchTarget)
                    .accessibilityLabel("Revenir à \(previous.label)")
                    .transition(.opacity.combined(with: .move(edge: .leading)))
                } else {
                    Text(step.label)
                        .font(SharpitTypography.bodyEmphasis)
                        .foregroundStyle(SharpitColor.foreground)
                        .frame(minHeight: SharpitSpacing.minimumTouchTarget)
                }
                Spacer(minLength: SharpitSpacing.xs)
                Text("\(step.position)/\(OnboardingStep.count)")
                    .font(SharpitTypography.meta)
                    .monospacedDigit()
                    .contentTransition(.numericText(value: Double(step.position)))
                    .foregroundStyle(SharpitColor.mutedForeground)
                    .accessibilityHidden(true)
            }

            OnboardingProgressRail(position: step.position, count: OnboardingStep.count)
        }
        .padding(.horizontal, SharpitSpacing.pageInset)
        .padding(.bottom, SharpitSpacing.sm)
        .background(SharpitCanvasBackground())
    }
}

/// Fills inclusively: reaching a step counts it as attained, so step 2 of 5 sits at 40%.
private struct OnboardingProgressRail: View {
    let position: Int
    let count: Int

    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            ZStack(alignment: .leading) {
                Capsule().fill(SharpitColor.border.opacity(0.7))
                Capsule()
                    .fill(SharpitColor.primary)
                    .frame(width: width * CGFloat(position) / CGFloat(max(count, 1)))
                ForEach(1..<max(count, 1), id: \.self) { tick in
                    Rectangle()
                        .fill(SharpitColor.background)
                        .frame(width: 2)
                        .offset(x: width * CGFloat(tick) / CGFloat(count) - 1)
                }
            }
            // A spring rather than a linear fill: the rail settles like a physical slider.
            .animation(SharpitMotion.reveal, value: position)
        }
        .frame(height: 4)
        .clipShape(Capsule())
        .accessibilityElement()
        .accessibilityLabel("Progression")
        .accessibilityValue("Étape \(position) sur \(count)")
    }
}

// MARK: - Actions

/// The step's actions, docked above the home indicator: Passer when the step is optional, and
/// the forward action — Finaliser on the last step, which marks the wizard's end.
private struct OnboardingActionBar: View {
    let store: OnboardingStore

    var body: some View {
        VStack(alignment: .leading, spacing: SharpitSpacing.xs) {
            if let error = store.error {
                Label(error, systemImage: "exclamationmark.triangle")
                    .font(SharpitTypography.meta)
                    .foregroundStyle(SharpitColor.signalRisk)
                    .fixedSize(horizontal: false, vertical: true)
                    .transition(.opacity)
            } else if store.step == .sports, !store.canContinueFromSports {
                Text("Choisis au moins un sport d'endurance pour continuer.")
                    .font(SharpitTypography.meta)
                    .foregroundStyle(SharpitColor.mutedForeground)
            }

            HStack(spacing: SharpitSpacing.sm) {
                if store.step.allowsSkip {
                    Button {
                        Task { await store.skip() }
                    } label: {
                        Text("Passer")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .tint(SharpitColor.foreground)
                }

                Button {
                    SharpitHaptics.play(.light)
                    Task { await store.advance() }
                } label: {
                    HStack(spacing: SharpitSpacing.xs) {
                        if store.isBusy {
                            ProgressView()
                                .tint(SharpitColor.primaryForeground)
                        }
                        Text(forwardLabel)
                            .contentTransition(.opacity)
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(SharpitColor.primary)
                .disabled(!canAdvance)
            }
            .controlSize(.large)
            .disabled(store.isBusy)
        }
        .animation(SharpitMotion.fade, value: store.error)
        .animation(SharpitMotion.selection, value: store.step)
        .padding(.horizontal, SharpitSpacing.pageInset)
        .padding(.top, SharpitSpacing.sm)
        .padding(.bottom, SharpitSpacing.xs)
        .background(SharpitCanvasBackground())
    }

    private var forwardLabel: String {
        if store.step == .sources {
            return store.isBusy ? "Finalisation…" : "Finaliser"
        }
        return "Continuer"
    }

    private var canAdvance: Bool {
        switch store.step {
        case .sports: store.canContinueFromSports
        case .intention: store.intention.isValid
        case .equipment, .availability, .sources: true
        }
    }
}

// MARK: - Bootstrap

/// A short beat after Finaliser — no real work, just pacing before Résumé, with the web's
/// lines (`use-bootstrap-line-cycle.ts`). A ring closes as the lines advance and settles into
/// a check, so the wizard ends on something finished rather than on a spinner.
struct OnboardingBootstrapView: View {
    static let lines = [
        "Onboarding terminé…",
        "Ton Twin se met en place…",
        "Première lecture en cours…",
        "Bienvenue sur Résumé…",
    ]

    let onDone: () -> Void

    @State private var index = 0
    @State private var progress: Double = 0
    @State private var isComplete = false
    @State private var hasAppeared = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: SharpitSpacing.lg) {
            ZStack {
                Circle()
                    .stroke(SharpitColor.analysisGrid, lineWidth: 3)
                Circle()
                    .trim(from: 0, to: progress)
                    .stroke(SharpitColor.primary, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                Image(systemName: "checkmark")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(SharpitColor.primary)
                    .opacity(isComplete ? 1 : 0)
                    .scaleEffect(isComplete ? 1 : 0.4)
                    .symbolEffect(.bounce, value: isComplete)
            }
            .frame(width: 56, height: 56)
            .revealed(hasAppeared, index: 0)

            Text(Self.lines[index])
                .font(SharpitTypography.sectionTitle)
                .tracking(SharpitTypography.sectionTitleTracking)
                .foregroundStyle(SharpitColor.foreground)
                .multilineTextAlignment(.center)
                .id(index)
                .transition(.asymmetric(
                    insertion: .opacity.combined(with: .offset(y: 10)),
                    removal: .opacity.combined(with: .offset(y: -10))
                ))
                .revealed(hasAppeared, index: 1)

            Text("Tout est finalisé. SharpIt assemble ta première lecture à partir de ce que tu viens de renseigner.")
                .font(SharpitTypography.meta)
                .foregroundStyle(SharpitColor.mutedForeground)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 280)
                .revealed(hasAppeared, index: 2)
        }
        .padding(SharpitSpacing.pageInset)
        .accessibilityElement(children: .combine)
        .task { await cycle() }
    }

    private var step: Double { 1 / Double(Self.lines.count) }

    private func cycle() async {
        hasAppeared = true
        SharpitHaptics.play(.success)
        guard !reduceMotion else {
            progress = 1
            isComplete = true
            try? await Task.sleep(for: .milliseconds(400))
            onDone()
            return
        }
        withAnimation(.easeInOut(duration: 1.2)) { progress = step }
        for next in Self.lines.indices.dropFirst() {
            try? await Task.sleep(for: .milliseconds(1400))
            guard !Task.isCancelled else { return }
            SharpitMotion.run(SharpitMotion.reveal) { index = next }
            withAnimation(.easeInOut(duration: 1.2)) { progress = step * Double(next + 1) }
        }
        try? await Task.sleep(for: .milliseconds(1200))
        guard !Task.isCancelled else { return }
        SharpitMotion.run { isComplete = true }
        SharpitHaptics.play(.soft)
        try? await Task.sleep(for: .milliseconds(700))
        guard !Task.isCancelled else { return }
        onDone()
    }
}
