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
            OnboardingProgressHeader(
                step: store.step,
                isBusy: store.isBusy,
                onBack: { store.goBack() },
                onSkip: store.step.allowsSkip ? { Task { await store.skip() } } : nil
            )

            ZStack {
                OnboardingStepPage(step: store.step) {
                    stepContent
                }
                .id(store.step)
                .transition(.push(from: store.isMovingForward ? .trailing : .leading))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            // The page scrolls under the actions, which float over it with a gradient fade.
            .safeAreaInset(edge: .bottom, spacing: 0) {
                OnboardingActionBar(store: store)
            }
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
            VStack(alignment: .leading, spacing: SharpitSpacing.md) {
                VStack(alignment: .leading, spacing: SharpitSpacing.xxs) {
                    Text(step.title)
                        .font(SharpitTypography.screenTitle)
                        .tracking(SharpitTypography.screenTitleTracking)
                        .foregroundStyle(SharpitColor.foreground)
                        .accessibilityAddTraits(.isHeader)
                        .revealed(hasAppeared, index: 1)
                    Text(step.intro)
                        .font(SharpitTypography.body)
                        .foregroundStyle(SharpitColor.mutedForeground)
                        .fixedSize(horizontal: false, vertical: true)
                        .revealed(hasAppeared, index: 2)
                }
                .padding(.bottom, SharpitSpacing.xs)

                content
                    .revealed(hasAppeared, index: 3)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, SharpitSpacing.pageInset)
            .padding(.top, SharpitSpacing.sm)
            .padding(.bottom, SharpitSpacing.xl)
        }
        .scrollDismissesKeyboard(.interactively)
        .scrollIndicators(.hidden)
        .onAppear { hasAppeared = true }
    }
}

// MARK: - Wayfinding

/// Segmented story-style progress header with back button, step title and skip action.
private struct OnboardingProgressHeader: View {
    let step: OnboardingStep
    let isBusy: Bool
    let onBack: () -> Void
    var onSkip: (() -> Void)?

    var body: some View {
        VStack(spacing: SharpitSpacing.sm) {
            // Segmented story-style capsules
            HStack(spacing: 5) {
                ForEach(0..<OnboardingStep.count, id: \.self) { index in
                    Capsule()
                        .fill(index < step.position ? SharpitColor.primary : SharpitColor.border.opacity(0.35))
                        .frame(height: 3.5)
                        .animation(SharpitMotion.reveal, value: step.position)
                }
            }
            .accessibilityElement()
            .accessibilityLabel("Progression")
            .accessibilityValue("Étape \(step.position) sur \(OnboardingStep.count)")

            // Navigation bar row
            HStack(spacing: SharpitSpacing.sm) {
                if step.previous != nil {
                    Button(action: onBack) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(SharpitColor.foreground)
                            .frame(width: 36, height: 36)
                            .background(SharpitColor.card.opacity(0.7), in: Circle())
                    }
                    .buttonStyle(.plain)
                    .disabled(isBusy)
                    .accessibilityLabel("Étape précédente")
                    .transition(.opacity)
                } else {
                    Color.clear.frame(width: 36, height: 36)
                }

                Spacer()

                Text(step.label)
                    .font(SharpitTypography.cardTitle)
                    .foregroundStyle(SharpitColor.foreground)

                Spacer()

                if let onSkip {
                    Button(action: onSkip) {
                        Text("Passer")
                            .font(SharpitTypography.bodyEmphasis)
                            .foregroundStyle(SharpitColor.mutedForeground)
                            .frame(height: 36)
                            .padding(.horizontal, 4)
                    }
                    .buttonStyle(.plain)
                    .disabled(isBusy)
                    .accessibilityLabel("Passer cette étape")
                    .transition(.opacity)
                } else {
                    Color.clear.frame(width: 36, height: 36)
                }
            }
        }
        .padding(.horizontal, SharpitSpacing.pageInset)
        .padding(.top, SharpitSpacing.xs)
        .padding(.bottom, SharpitSpacing.xs)
        .background(SharpitCanvasBackground())
    }
}

// MARK: - Actions

/// The step's primary action docked at the bottom with a smooth gradient fade.
private struct OnboardingActionBar: View {
    let store: OnboardingStore

    var body: some View {
        VStack(alignment: .leading, spacing: SharpitSpacing.xs) {
            // Over scrolled content, so the line sits on its own glass to stay legible.
            if let error = store.error {
                Label(error, systemImage: "exclamationmark.triangle")
                    .font(SharpitTypography.meta)
                    .foregroundStyle(SharpitColor.signalRisk)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, SharpitSpacing.sm)
                    .padding(.vertical, SharpitSpacing.xxs + 2)
                    .sharpitGlassCapsule()
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
            } else if store.step == .sports, !store.canContinueFromSports {
                Text("Choisis au moins un sport d'endurance pour continuer.")
                    .font(SharpitTypography.meta)
                    .foregroundStyle(SharpitColor.mutedForeground)
                    .padding(.horizontal, SharpitSpacing.sm)
                    .padding(.vertical, SharpitSpacing.xxs + 2)
                    .sharpitGlassCapsule()
                    .transition(.opacity)
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
                        .font(SharpitTypography.bodyEmphasis)
                        .contentTransition(.opacity)
                }
                .frame(maxWidth: .infinity)
                .frame(minHeight: SharpitSpacing.minimumTouchTarget)
            }
            .sharpitGlassButton(prominent: true)
            .tint(SharpitColor.primary)
            .disabled(!canAdvance || store.isBusy)
            .controlSize(.large)
        }
        .animation(SharpitMotion.fade, value: store.error)
        .animation(SharpitMotion.selection, value: store.step)
        .padding(.horizontal, SharpitSpacing.pageInset)
        .padding(.top, SharpitSpacing.sm)
        .padding(.bottom, SharpitSpacing.sm)
        .background(
            LinearGradient(
                colors: [
                    SharpitColor.background.opacity(0),
                    SharpitColor.background.opacity(0.85),
                    SharpitColor.background
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        )
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
