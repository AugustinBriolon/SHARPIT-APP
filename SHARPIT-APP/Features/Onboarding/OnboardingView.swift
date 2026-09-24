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
                    .transition(.opacity)
            case .bootstrap:
                OnboardingBootstrapView(onDone: onFinished)
                    .transition(.opacity)
            }
        }
        .task { await store.load() }
    }

    private var steps: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: SharpitSpacing.lg) {
                VStack(alignment: .leading, spacing: SharpitSpacing.xs) {
                    Text(store.step.title)
                        .font(SharpitTypography.pageTitle)
                        .tracking(SharpitTypography.pageTitleTracking)
                        .foregroundStyle(SharpitColor.foreground)
                        .accessibilityAddTraits(.isHeader)
                    Text(store.step.intro)
                        .font(SharpitTypography.body)
                        .foregroundStyle(SharpitColor.mutedForeground)
                        .fixedSize(horizontal: false, vertical: true)
                }

                stepContent
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, SharpitSpacing.pageInset)
            .padding(.top, SharpitSpacing.md)
            .padding(.bottom, SharpitSpacing.xl)
        }
        // A new step opens at its top, not where the previous one was scrolled to.
        .id(store.step)
        .scrollDismissesKeyboard(.interactively)
        .safeAreaInset(edge: .top, spacing: 0) {
            OnboardingProgressHeader(step: store.step, isBusy: store.isBusy) {
                store.goBack()
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
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
/// lines (`use-bootstrap-line-cycle.ts`).
struct OnboardingBootstrapView: View {
    static let lines = [
        "Onboarding terminé…",
        "Ton Twin se met en place…",
        "Première lecture en cours…",
        "Bienvenue sur Résumé…",
    ]

    let onDone: () -> Void

    @State private var index = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: SharpitSpacing.lg) {
            ProgressView()
                .controlSize(.large)
                .tint(SharpitColor.primary)

            Text(Self.lines[index])
                .font(SharpitTypography.sectionTitle)
                .tracking(SharpitTypography.sectionTitleTracking)
                .foregroundStyle(SharpitColor.foreground)
                .multilineTextAlignment(.center)
                .id(index)
                .transition(.opacity)

            Text("Tout est finalisé. SharpIt assemble ta première lecture à partir de ce que tu viens de renseigner.")
                .font(SharpitTypography.meta)
                .foregroundStyle(SharpitColor.mutedForeground)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 280)
        }
        .padding(SharpitSpacing.pageInset)
        .accessibilityElement(children: .combine)
        .task { await cycle() }
    }

    private func cycle() async {
        SharpitHaptics.play(.success)
        guard !reduceMotion else {
            try? await Task.sleep(for: .milliseconds(400))
            onDone()
            return
        }
        for next in Self.lines.indices.dropFirst() {
            try? await Task.sleep(for: .milliseconds(1400))
            guard !Task.isCancelled else { return }
            SharpitMotion.run(SharpitMotion.fade) { index = next }
        }
        try? await Task.sleep(for: .milliseconds(1400))
        guard !Task.isCancelled else { return }
        onDone()
    }
}
