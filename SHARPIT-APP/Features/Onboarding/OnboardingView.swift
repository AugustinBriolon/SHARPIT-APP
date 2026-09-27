import SwiftUI

/// The first-login wizard, shown full screen after sign-up and before the tabs.
///
/// The header's dial fills as the coach is built, the actions stay docked below, and only the
/// step between them moves: it slides in from the side the athlete is heading. The move is
/// driven by the step's value (`.animation(_:value:)`), not by an animation block opened in
/// async code, so the page on screen is always the store's step.
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
                SharpitLaunchMark()
            case .steps:
                steps
                    .transition(.opacity)
            case .bootstrap:
                OnboardingBootstrapView(onDone: onFinished)
                    .transition(.opacity.combined(with: .scale(scale: 1.04)))
            }
        }
        .animation(SharpitMotion.reveal, value: store.phase)
        .task { await store.load() }
    }

    /// One page: the header, its dial and the step's title stay put — the dial sweeps on to
    /// the new step and the title cross-fades — and only what is under them slides.
    private var steps: some View {
        VStack(spacing: 0) {
            OnboardingHeader(store: store)
            OnboardingTitle(step: store.step)
                .animation(SharpitMotion.fade, value: store.step)

            ZStack {
                OnboardingPage { stepContent }
                    .id(store.step)
                    .transition(pageTransition)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .clipped()
            .animation(SharpitMotion.reveal, value: store.step)
            .safeAreaInset(edge: .bottom, spacing: 0) {
                OnboardingActionBar(store: store)
            }
        }
        .sensoryFeedback(.selection, trigger: store.step)
    }

    private var pageTransition: AnyTransition {
        let forward = store.isMovingForward
        return .asymmetric(
            insertion: .move(edge: forward ? .trailing : .leading).combined(with: .opacity),
            removal: .move(edge: forward ? .leading : .trailing).combined(with: .opacity)
        )
    }

    @ViewBuilder
    private var stepContent: some View {
        switch store.step {
        case .identity: OnboardingIdentityStep(draft: $store.identity)
        case .sports: OnboardingSportsStep(store: store)
        case .equipment: OnboardingEquipmentStep(store: store)
        case .week: OnboardingWeekStep(store: store)
        case .goal: OnboardingGoalStep(draft: $store.intention)
        case .injuries: OnboardingInjuriesStep(store: store)
        case .privacy: OnboardingPrivacyStep(consents: $store.consents)
        case .sources:
            OnboardingSourcesStep(
                appleHealth: appleHealth,
                syncClient: syncClient,
                tokenProvider: tokenProvider
            )
        case .firstWeek: OnboardingFirstWeekStep(store: store)
        }
    }
}

/// The step's title and intro, under the dial. They swap in place: the step changes, not the
/// page.
private struct OnboardingTitle: View {
    let step: OnboardingStep

    var body: some View {
        ZStack(alignment: .topLeading) {
            VStack(alignment: .leading, spacing: SharpitSpacing.xs) {
                Text(step.title)
                    .font(SharpitTypography.screenTitle)
                    .tracking(SharpitTypography.screenTitleTracking)
                    .foregroundStyle(SharpitColor.foreground)
                    .accessibilityAddTraits(.isHeader)
                Text(step.intro)
                    .font(SharpitTypography.body)
                    .foregroundStyle(SharpitColor.mutedForeground)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .id(step)
            .transition(.opacity)
        }
        .padding(.horizontal, SharpitSpacing.pageInset)
        .padding(.top, SharpitSpacing.sm)
        .padding(.bottom, SharpitSpacing.md)
    }
}

/// What the step asks, scrolling between the title and the docked actions.
private struct OnboardingPage<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        ScrollView {
            content
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, SharpitSpacing.pageInset)
                .padding(.bottom, SharpitSpacing.xl)
        }
        .scrollDismissesKeyboard(.interactively)
        .scrollIndicators(.hidden)
    }
}

// MARK: - Header

/// Back, the dial that fills as the coach is built, and Passer where a step can be skipped.
private struct OnboardingHeader: View {
    let store: OnboardingStore

    var body: some View {
        HStack(alignment: .center, spacing: SharpitSpacing.sm) {
            Button(action: store.goBack) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(SharpitColor.foreground)
                    .frame(width: 40, height: 40)
                    .sharpitGlassControl(in: Circle(), fallback: SharpitColor.analysisSurfaceAlt)
            }
            .buttonStyle(.plain)
            .opacity(store.canGoBack ? 1 : 0)
            .disabled(!store.canGoBack || store.isBusy)
            .accessibilityLabel("Étape précédente")

            Spacer(minLength: 0)

            VStack(spacing: 2) {
                SharpitTickGauge(score: CGFloat(store.progress * 100))
                    .frame(width: 88, height: 88 / SharpitTickGaugeGeometry.aspectRatio)
                    .animation(SharpitMotion.gaugeFill, value: store.progress)
                Text(store.step.label)
                    .font(SharpitTypography.label)
                    .tracking(SharpitTypography.labelTracking)
                    .textCase(.uppercase)
                    .foregroundStyle(SharpitColor.mutedForeground)
                    .contentTransition(.opacity)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Étape \(store.position) sur \(store.path.count), \(store.step.label)")

            Spacer(minLength: 0)

            Button("Passer") { [step = store.step] in Task { await store.skip(from: step) } }
                .font(SharpitTypography.bodyEmphasis)
                .foregroundStyle(SharpitColor.mutedForeground)
                .frame(width: 64, height: 40)
                .opacity(store.step.allowsSkip ? 1 : 0)
                .disabled(!store.step.allowsSkip || store.isBusy)
                .accessibilityLabel("Passer cette étape")
        }
        .padding(.horizontal, SharpitSpacing.pageInset)
        .padding(.top, SharpitSpacing.xs)
        .padding(.bottom, SharpitSpacing.xxs)
        .animation(SharpitMotion.selection, value: store.step)
    }
}

// MARK: - Actions

/// The step's primary action, docked over a fade, with the reason it is held when it is.
private struct OnboardingActionBar: View {
    let store: OnboardingStore

    var body: some View {
        VStack(alignment: .leading, spacing: SharpitSpacing.xs) {
            if let error = store.error {
                Label(error, systemImage: "exclamationmark.triangle")
                    .font(SharpitTypography.meta)
                    .foregroundStyle(SharpitColor.signalRisk)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, SharpitSpacing.sm)
                    .padding(.vertical, SharpitSpacing.xxs + 2)
                    .sharpitGlassCapsule()
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
            } else if let hint {
                Text(hint)
                    .font(SharpitTypography.meta)
                    .foregroundStyle(SharpitColor.mutedForeground)
                    .padding(.horizontal, SharpitSpacing.sm)
                    .padding(.vertical, SharpitSpacing.xxs + 2)
                    .sharpitGlassCapsule()
                    .transition(.opacity)
            }

            Button { [step = store.step] in
                SharpitHaptics.play(.light)
                Task { await store.advance(from: step) }
            } label: {
                HStack(spacing: SharpitSpacing.xs) {
                    if store.isBusy || store.firstWeek == .generating && store.step == .firstWeek {
                        ProgressView()
                            .tint(SharpitColor.primaryForeground)
                    }
                    Text(primaryLabel)
                        .font(SharpitTypography.bodyEmphasis)
                        .foregroundStyle(SharpitColor.primaryForeground)
                        .contentTransition(.opacity)
                }
                .frame(maxWidth: .infinity)
            }
            .sharpitGlassButton(prominent: true)
            .tint(SharpitColor.primary)
            .disabled(!store.canAdvance || store.isBusy)

            if showsFinishWithout {
                Button("Terminer sans ces séances") { Task { await store.finishWithoutFirstWeek() } }
                    .font(SharpitTypography.bodyEmphasis)
                    .foregroundStyle(SharpitColor.mutedForeground)
                    .frame(maxWidth: .infinity)
                    .disabled(store.isBusy)
            }
        }
        .animation(SharpitMotion.fade, value: store.error)
        .animation(SharpitMotion.selection, value: store.step)
        .padding(.horizontal, SharpitSpacing.pageInset)
        .padding(.top, SharpitSpacing.sm)
        .padding(.bottom, SharpitSpacing.sm)
        .background(
            LinearGradient(
                colors: [SharpitColor.background.opacity(0), SharpitColor.background.opacity(0.85), SharpitColor.background],
                startPoint: .top,
                endPoint: .bottom
            )
        )
    }

    private var hint: String? {
        switch store.step {
        case .sports where !store.canContinueFromSports: "Choisis au moins un sport d'endurance."
        case .privacy where !store.consents.requiredAccepted: "Les deux documents et les données de santé sont nécessaires."
        default: nil
        }
    }

    private var showsFinishWithout: Bool {
        guard store.step == .firstWeek else { return false }
        switch store.firstWeek {
        case .ready, .generating, .failed: return true
        default: return false
        }
    }

    private var primaryLabel: String {
        switch store.step {
        case .identity: store.isBusy ? "Enregistrement…" : "Commencer"
        case .injuries where store.injuries.isEmpty: "Aucune blessure"
        case .privacy: "Accepter et continuer"
        case .firstWeek:
            switch store.firstWeek {
            case .generating: "Le coach prépare ta semaine…"
            case .ready: store.isBusy ? "Ajout au plan…" : "Ajouter à mon plan"
            default: "Terminer"
            }
        default: store.isBusy ? "Enregistrement…" : "Continuer"
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
