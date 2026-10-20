import SwiftUI

/// The first-login wizard, shown full screen after sign-up and before the tabs.
///
/// The dial and the docked actions stay put; the title and the step's body push/pop together
/// like a NavigationStack page (forward ← from the trailing edge, back → from the leading).
struct OnboardingView: View {
    @Bindable var store: OnboardingStore
    @State private var scrollProxy: ScrollViewProxy?
    @State private var isShowingProPaywall = false
    @Environment(ProStore.self) private var pro: ProStore?
    let appleHealth: AppleHealthSource
    let appleCalendar: AppleCalendarSource
    let tokenProvider: () async throws -> String
    /// Called once the bootstrap beat is over — the gate then shows Résumé.
    let onFinished: () -> Void

    init(
        store: OnboardingStore,
        appleHealth: AppleHealthSource,
        appleCalendar: AppleCalendarSource = AppleCalendarSource(client: SharpitClient()),
        tokenProvider: @escaping () async throws -> String,
        onFinished: @escaping () -> Void
    ) {
        self.store = store
        self.appleHealth = appleHealth
        self.appleCalendar = appleCalendar
        self.tokenProvider = tokenProvider
        self.onFinished = onFinished
    }

    var body: some View {
        ZStack {
            SharpitCanvasBackground()
            Group {
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
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .sharpitRegularColumn()
            // The week stays behind the paywall, out of reach until Pro.
            .blur(radius: isShowingProPaywall ? 12 : 0)
            .animation(SharpitMotion.reveal, value: isShowingProPaywall)
        }
        .background(SharpitColor.background.ignoresSafeArea())
        .animation(SharpitMotion.reveal, value: store.phase)
        .task { await store.load() }
        .sheet(isPresented: $isShowingProPaywall) {
            if let pro {
                SharpitProPaywallSheet(
                    store: pro,
                    sessions: store.firstWeekSessions,
                    onSubscribed: {
                        isShowingProPaywall = false
                        Task { await store.advance(from: .firstWeek) }
                    }
                )
            }
        }
    }

    private var steps: some View {
        VStack(spacing: 0) {
            OnboardingHeader(store: store)

            ZStack {
                VStack(spacing: 0) {
                    OnboardingTitle(step: store.step)
                    OnboardingPage(onScrollProxyChange: { scrollProxy = $0 }) { stepContent }
                }
                .id(store.step)
                .transition(OnboardingStepSlide(store: store))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .clipped()
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            OnboardingActionBar(
                store: store,
                onOpenProModal: { isShowingProPaywall = true }
            )
        }
    }

    @ViewBuilder
    private var stepContent: some View {
        switch store.step {
        case .identity: OnboardingIdentityStep(draft: $store.identity)
        case .motivation: OnboardingMotivationStep(store: store)
        case .sports: OnboardingSportsStep(store: store)
        case .equipment: OnboardingEquipmentStep(store: store)
        case .week: OnboardingWeekStep(store: store)
        case .goal: OnboardingGoalStep(draft: $store.intention, sports: Set(store.sports), isStrengthOnly: store.isStrengthOnly)
        case .injuries: OnboardingInjuriesStep(store: store)
        case .privacy: OnboardingPrivacyStep(consents: $store.consents)
        case .sources:
            OnboardingSourcesStep(
                appleHealth: appleHealth,
                appleCalendar: appleCalendar,
                tokenProvider: tokenProvider,
                hasAccount: store.hasAccount,
                onAccountNeeded: store.requestAccount
            )
        case .firstWeek: OnboardingFirstWeekStep(store: store)
        }
    }
}

/// Horizontal page push/pop — edge is read for both views at animation time (not baked at insert).
/// Forward: new from the right, old exits left. Back: active exits right, previous from the left.
struct OnboardingStepSlide: Transition {
    var isMovingForward: () -> Bool

    init(forward: Bool) {
        self.isMovingForward = { forward }
    }

    init(store: OnboardingStore) {
        self.isMovingForward = { store.isMovingForward }
    }

    init(direction: @escaping () -> Bool) {
        self.isMovingForward = direction
    }

    func body(content: Content, phase: TransitionPhase) -> some View {
        let forward = isMovingForward()
        let distance: CGFloat = 440
        let offset: CGFloat = switch phase {
        case .willAppear:
            forward ? distance : -distance
        case .didDisappear:
            forward ? -distance : distance
        default:
            0
        }
        return content.offset(x: offset)
    }
}

/// The step's title and intro — slides with the page body.
private struct OnboardingTitle: View {
    let step: OnboardingStep

    var body: some View {
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
        .padding(.horizontal, SharpitSpacing.pageInset)
        .padding(.top, SharpitSpacing.sm)
        .padding(.bottom, SharpitSpacing.md)
    }
}

/// What the step asks, scrolling between the title and the docked actions.
private struct OnboardingPage<Content: View>: View {
    var onScrollProxyChange: ((ScrollViewProxy) -> Void)? = nil
    @ViewBuilder let content: Content

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                content
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, SharpitSpacing.pageInset)
                    .padding(.bottom, SharpitSpacing.xl)
            }
            .scrollDismissesKeyboard(.interactively)
            .scrollIndicators(.hidden)
            .onAppear {
                onScrollProxyChange?(proxy)
            }
        }
    }
}

// MARK: - Header

/// Back, the dial that fills as the coach is built, and Passer where a step can be skipped.
private struct OnboardingHeader: View {
    let store: OnboardingStore
    private static let sideWidth: CGFloat = 64

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
            .accessibilityLabel(String(localized: "Retour"))
            // As wide as « Passer » opposite, so the dial sits on the screen's centre.
            .frame(width: Self.sideWidth, alignment: .leading)

            Spacer(minLength: 0)

            // The position sits inside the arc, and the dial's thumb shows from the first step —
            // at its start, the way still to go.
            ZStack(alignment: .bottom) {
                SharpitTickGauge(score: CGFloat(store.progress * 100), showsThumbAtStart: true)
                    .frame(width: 104, height: 104 / SharpitTickGaugeGeometry.aspectRatio)
                    .animation(SharpitMotion.gaugeFill, value: store.progress)
                Text("\(store.position) / \(store.path.count)")
                    .font(SharpitTypography.label.monospacedDigit())
                    .tracking(SharpitTypography.labelTracking)
                    .foregroundStyle(SharpitColor.mutedForeground)
                    .contentTransition(.numericText(value: Double(store.position)))
                    .padding(.bottom, 8)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Étape \(store.position) sur \(store.path.count), \(store.step.label)")

            Spacer(minLength: 0)

            Button("Passer") { [step = store.step] in Task { await store.skip(from: step) } }
                .font(SharpitTypography.bodyEmphasis)
                .foregroundStyle(SharpitColor.mutedForeground)
                .frame(width: Self.sideWidth, height: 40)
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
    var onOpenProModal: (() -> Void)? = nil
    @Environment(ProStore.self) private var pro: ProStore?

    var body: some View {
        // The generator's dock and button: a fade to the bottom edge, a button a touch taller.
        SharpitActionDock {
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

            SharpitPrimaryButton(
                title: primaryLabel,
                isBusy: store.isBusy || store.firstWeek == .generating && store.step == .firstWeek
            ) { [step = store.step] in
                if step == .firstWeek, case .ready = store.firstWeek, pro?.isPro != true {
                    onOpenProModal?()
                } else {
                    Task { await store.advance(from: step) }
                }
            }
            .disabled(!store.canAdvance || store.isBusy)

            if showsFinishWithout {
                Button(finishWithoutLabel) { Task { await store.finishWithoutFirstWeek() } }
                    .font(SharpitTypography.bodyEmphasis)
                    .foregroundStyle(SharpitColor.mutedForeground)
                    .frame(maxWidth: .infinity)
                    .disabled(store.isBusy)
            }
        }
        .animation(SharpitMotion.fade, value: store.error)
        .animation(SharpitMotion.selection, value: store.step)
    }

    private var finishWithoutLabel: String {
        if store.step == .firstWeek, pro?.isPro != true {
            return String(localized: "Rester sur le plan gratuit")
        }
        return String(localized: "Terminer sans ces séances")
    }

    private var hint: String? {
        switch store.step {
        case .sports where !store.canContinueFromSports: String(localized: "Choisis un sport d'endurance, ou la musculation.")
        case .privacy where !store.consents.requiredAccepted: String(localized: "Les deux documents et les données de santé sont nécessaires.")
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
        case .identity: store.isBusy ? String(localized: "Enregistrement…") : String(localized: "Commencer")
        case .injuries where !store.hasAccount:
            store.isBusy ? String(localized: "Enregistrement…") : String(localized: "Continuer et créer mon compte")
        case .injuries where store.injuries.isEmpty: String(localized: "Aucune blessure")
        case .privacy: String(localized: "Accepter et continuer")
        case .firstWeek:
            switch store.firstWeek {
            case .generating: String(localized: "Le coach prépare ta semaine…")
            case .ready:
                store.isBusy ? String(localized: "Application du plan…") : String(localized: "Appliquer le plan")
            default: String(localized: "Terminer")
            }
        default: store.isBusy ? String(localized: "Enregistrement…") : String(localized: "Continuer")
        }
    }
}

// MARK: - Bootstrap

/// A short beat after Finaliser — no real work, just pacing before Résumé, with the web's
/// lines (`use-bootstrap-line-cycle.ts`). A ring closes as the lines advance and settles into
/// a check, so the wizard ends on something finished rather than on a spinner.
struct OnboardingBootstrapView: View {
    static let lines = [
        String(localized: "Onboarding terminé…"),
        String(localized: "Ton Twin se met en place…"),
        String(localized: "Première lecture en cours…"),
        String(localized: "Bienvenue sur Résumé…"),
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
        try? await Task.sleep(for: .milliseconds(700))
        guard !Task.isCancelled else { return }
        onDone()
    }
}
