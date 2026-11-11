import SwiftUI

// MARK: - Zone sheet

/// One zone, one question at a time: each answer slides the next question in, the answers given
/// line up as chips at the top (a tap goes back to one), and the last screen reads them back with
/// « Ajouter ». The side the finger landed on is already answered; a fragile zone skips the pain
/// questions. Nothing is chosen for the athlete.
struct OnboardingZoneSheet: View {
    @State var draft: OnboardingInjuryDraft
    let isDeclared: Bool
    let onSave: (OnboardingInjuryDraft) -> Void
    let onRemove: () -> Void

    @State private var question: ZoneQuestion = .kind
    @State private var isForward = true
    /// The page's own height: the sheet fits each question instead of leaving half a screen empty.
    @State private var contentHeight: CGFloat = 420
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(
        draft: OnboardingInjuryDraft,
        isDeclared: Bool,
        onSave: @escaping (OnboardingInjuryDraft) -> Void,
        onRemove: @escaping () -> Void
    ) {
        _draft = State(initialValue: draft)
        self.isDeclared = isDeclared
        self.onSave = onSave
        self.onRemove = onRemove
        // A declared zone opens on its summary; a new one on its first open question.
        _question = State(initialValue: ZoneQuestion.firstOpen(in: draft))
    }

    private var place: String {
        SensitiveZoneBody.caption(part: draft.bodyPart, side: draft.side?.rawValue ?? "NA") ?? draft.bodyPart
    }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: SharpitSpacing.md) {
                answers
                ZStack(alignment: .top) {
                    page(question)
                        .id(question)
                        .transition(pageTransition)
                }
                .frame(maxWidth: .infinity, alignment: .top)
                .clipped()
            }
            .padding(.horizontal, SharpitSpacing.pageInset)
            .padding(.top, SharpitSpacing.sm)
            .padding(.bottom, SharpitSpacing.md)
            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { height in
                SharpitMotion.run(SharpitMotion.reveal) { contentHeight = height + 64 }
            }
            .frame(maxHeight: .infinity, alignment: .top)
            .navigationTitle(place)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Annuler") { dismiss() }
                }
                if isDeclared {
                    ToolbarItem(placement: .destructiveAction) {
                        Button("Retirer", role: .destructive) {
                            onRemove()
                            dismiss()
                        }
                    }
                }
            }
        }
        .presentationDetents([.height(contentHeight)])
    }

    // MARK: Flow

    /// Forward slides in from the trailing edge, back from the leading one; Reduce Motion fades.
    private var pageTransition: AnyTransition {
        if reduceMotion { return .opacity }
        let insertion: Edge = isForward ? .trailing : .leading
        let removal: Edge = isForward ? .leading : .trailing
        return .asymmetric(
            insertion: .move(edge: insertion).combined(with: .opacity),
            removal: .move(edge: removal).combined(with: .opacity)
        )
    }

    private func go(to next: ZoneQuestion) {
        let path = ZoneQuestion.path(for: draft)
        isForward = (path.firstIndex(of: next) ?? 0) >= (path.firstIndex(of: question) ?? 0)
        SharpitMotion.run(SharpitMotion.reveal) { question = next }
    }

    /// After an answer: the next question still open, or the summary.
    private func advance() {
        go(to: ZoneQuestion.firstOpen(in: draft, after: question))
    }

    // MARK: Answers

    /// The answers given so far, each a way back to its question.
    private var answers: some View {
        ScrollView(.horizontal) {
            HStack(spacing: SharpitSpacing.xs) {
                ForEach(ZoneQuestion.path(for: draft).filter { $0 != .summary }, id: \.self) { step in
                    if let value = step.answer(in: draft) {
                        Button {
                            go(to: step)
                        } label: {
                            Text(value)
                                .font(SharpitTypography.meta.weight(.semibold))
                                .foregroundStyle(step == question ? SharpitColor.primaryForeground : SharpitColor.foreground)
                                .padding(.horizontal, SharpitSpacing.sm)
                                .frame(minHeight: 32)
                                .background(
                                    Capsule().fill(step == question ? SharpitColor.primary : SharpitColor.analysisSurfaceAlt)
                                )
                        }
                        .buttonStyle(.sharpitPressable)
                        .accessibilityLabel("\(step.title) : \(value)")
                        .accessibilityHint(String(localized: "Touchez pour modifier."))
                        .transition(.scale(scale: 0.85).combined(with: .opacity))
                    }
                }
            }
            .animation(SharpitMotion.selection, value: draft)
        }
        .scrollIndicators(.hidden)
        .frame(minHeight: 32)
    }

    // MARK: Pages

    @ViewBuilder
    private func page(_ step: ZoneQuestion) -> some View {
        VStack(alignment: .leading, spacing: SharpitSpacing.md) {
            Text(step.title)
                .font(SharpitTypography.sectionTitle)
                .tracking(SharpitTypography.sectionTitleTracking)
                .foregroundStyle(SharpitColor.foreground)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
            switch step {
            case .kind: kindPage
            case .side: sidePage
            case .onset: onsetPage
            case .pain: painPage
            case .impact: impactPage
            case .summary: summaryPage
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    private var kindPage: some View {
        VStack(spacing: SharpitSpacing.xs) {
            ForEach(OnboardingInjuryDraft.Kind.allCases) { kind in
                MotivationRow(
                    symbol: kind.symbolName,
                    title: kind.label,
                    detail: kind.detail,
                    isSelected: draft.kind == kind
                ) {
                    draft.kind = kind
                    advance()
                }
            }
        }
    }

    private var sidePage: some View {
        HStack(spacing: SharpitSpacing.xs) {
            ForEach(OnboardingInjuryDraft.Side.allCases) { side in
                ZoneChoiceTile(
                    symbol: side.symbolName,
                    title: side.label,
                    isSelected: draft.side == side
                ) {
                    draft.side = side
                    advance()
                }
            }
        }
    }

    private var onsetPage: some View {
        VStack(alignment: .leading, spacing: SharpitSpacing.lg) {
            NotchTrack(
                stops: OnboardingInjuryDraft.Onset.allCases.count,
                value: Binding(
                    get: { draft.onset.flatMap { OnboardingInjuryDraft.Onset.allCases.firstIndex(of: $0) } },
                    set: { draft.onset = $0.map { OnboardingInjuryDraft.Onset.allCases[$0] } }
                ),
                tint: { _ in SharpitColor.highlight },
                stopLabels: OnboardingInjuryDraft.Onset.allCases.map(\.shortLabel),
                accessibilityLabel: String(localized: "Depuis quand"),
                valueLabel: { OnboardingInjuryDraft.Onset.allCases[$0].label },
                onRelease: advance
            )
            Text("Fais glisser ou touche une durée.")
                .font(SharpitTypography.meta)
                .foregroundStyle(SharpitColor.mutedForeground)
        }
        .padding(.top, SharpitSpacing.sm)
    }

    private var painPage: some View {
        VStack(alignment: .leading, spacing: SharpitSpacing.lg) {
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(draft.pain.map(String.init) ?? "—")
                    .font(SharpitTypography.heroScore)
                    .tracking(SharpitTypography.heroScoreTracking)
                    .foregroundStyle(ZoneSeverityTint.color(draft.pain))
                    .contentTransition(.numericText(value: Double(draft.pain ?? 0)))
                Text("/10")
                    .font(SharpitTypography.bodyEmphasis)
                    .foregroundStyle(SharpitColor.mutedForeground)
                Spacer()
                Text(draft.pain.map(ZoneSeverityTint.caption) ?? "")
                    .font(SharpitTypography.bodyEmphasis)
                    .foregroundStyle(SharpitColor.mutedForeground)
                    .contentTransition(.opacity)
            }
            .animation(SharpitMotion.selection, value: draft.pain)

            NotchTrack(
                stops: 11,
                value: $draft.pain,
                marker: OnboardingInjuryDraft.painThreshold,
                tint: { ZoneSeverityTint.color($0) },
                stopLabels: Self.painStopLabels,
                accessibilityLabel: String(localized: "Douleur sur 10"),
                valueLabel: { String(localized: "\($0) sur 10") }
            )

            Text(painCaption)
                .font(SharpitTypography.meta)
                .foregroundStyle(SharpitColor.mutedForeground)
                .fixedSize(horizontal: false, vertical: true)
                .contentTransition(.opacity)

            nextButton(String(localized: "Suivant"), isEnabled: draft.pain != nil, action: advance)
        }
        .padding(.top, SharpitSpacing.sm)
    }

    /// Only the ends and the threshold are written under the pain track.
    private static let painStopLabels: [String] = (0...10).map { (stop: Int) -> String in
        [0, 5, 10].contains(stop) ? String(stop) : ""
    }

    private var painCaption: String {
        guard let pain = draft.pain else { return String(localized: "Fais glisser jusqu'à ton niveau de douleur.") }
        return pain <= OnboardingInjuryDraft.painThreshold
            ? String(localized: "Jusqu'à 5, le coach peut garder de la charge en surveillant.")
            : String(localized: "Au-delà de 5, le coach allège les séances qui sollicitent la zone.")
    }

    private var impactPage: some View {
        VStack(spacing: SharpitSpacing.xs) {
            ForEach(ZoneImpact.all) { impact in
                ZoneLadderRow(
                    impact: impact,
                    isSelected: draft.impact == impact.value
                ) {
                    draft.impact = impact.value
                    advance()
                }
            }
        }
    }

    private var summaryPage: some View {
        VStack(alignment: .leading, spacing: SharpitSpacing.md) {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(ZoneQuestion.path(for: draft).filter { $0 != .summary }.enumerated()), id: \.element) { index, step in
                    if index > 0 {
                        Rectangle().fill(SharpitColor.analysisGrid).frame(height: 1)
                    }
                    Button {
                        go(to: step)
                    } label: {
                        HStack {
                            Text(step.shortTitle)
                                .font(SharpitTypography.meta)
                                .foregroundStyle(SharpitColor.mutedForeground)
                            Spacer(minLength: SharpitSpacing.sm)
                            Text(step.answer(in: draft) ?? "—")
                                .font(SharpitTypography.bodyEmphasis)
                                .foregroundStyle(SharpitColor.foreground)
                                .multilineTextAlignment(.trailing)
                            Image(systemName: "chevron.right")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(SharpitColor.mutedForeground.opacity(0.6))
                                .accessibilityHidden(true)
                        }
                        .padding(.vertical, SharpitSpacing.sm)
                        .contentShape(.rect)
                    }
                    .buttonStyle(.sharpitPressable)
                }
            }
            .padding(.horizontal, SharpitSpacing.cardPadding)
            .padding(.vertical, SharpitSpacing.xs)
            .sharpitSurface(.panel)

            if draft.warrantsCare {
                Label(
                    String(localized: "Si ça ne s'améliore pas en quelques jours, consulte un professionnel de santé."),
                    systemImage: "stethoscope"
                )
                .font(SharpitTypography.meta)
                .foregroundStyle(SharpitColor.signalCaution)
                .fixedSize(horizontal: false, vertical: true)
            }

            nextButton(
                isDeclared ? String(localized: "Enregistrer") : String(localized: "Ajouter"),
                isEnabled: draft.isComplete
            ) {
                onSave(draft)
                dismiss()
            }
        }
    }

    private func nextButton(_ title: String, isEnabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(SharpitTypography.bodyEmphasis)
                .foregroundStyle(SharpitColor.primaryForeground)
                .frame(maxWidth: .infinity)
        }
        .sharpitGlassButton(prominent: true)
        .tint(SharpitColor.primary)
        .disabled(!isEnabled)
        .padding(.bottom, SharpitSpacing.sm)
    }
}

/// The zone sheet's questions, in the order they are asked.
enum ZoneQuestion: Hashable, CaseIterable {
    case kind, side, onset, pain, impact, summary

    /// The questions this zone asks: the side only for a paired part, the pain questions only
    /// for a pain or an injury in progress.
    static func path(for draft: OnboardingInjuryDraft) -> [ZoneQuestion] {
        var path: [ZoneQuestion] = [.kind]
        if draft.asksForSide { path.append(.side) }
        if draft.kind == nil || draft.asksForState { path += [.onset, .pain, .impact] }
        path.append(.summary)
        return path
    }

    /// The first question of the path left unanswered after `current`, else the summary.
    static func firstOpen(in draft: OnboardingInjuryDraft, after current: ZoneQuestion? = nil) -> ZoneQuestion {
        let path = path(for: draft)
        let start = current.flatMap { path.firstIndex(of: $0) }.map { $0 + 1 } ?? 0
        return path[start...].first { $0 != .summary && $0.answer(in: draft) == nil } ?? .summary
    }

    var title: String {
        switch self {
        case .kind: String(localized: "Qu'est-ce que c'est ?")
        case .side: String(localized: "Quel côté ?")
        case .onset: String(localized: "Depuis quand ?")
        case .pain: String(localized: "Combien ça fait mal ?")
        case .impact: String(localized: "Ce que tu peux encore faire")
        case .summary: String(localized: "On récapitule")
        }
    }

    /// The summary's row label.
    var shortTitle: String {
        switch self {
        case .kind: String(localized: "Type")
        case .side: String(localized: "Côté")
        case .onset: String(localized: "Depuis")
        case .pain: String(localized: "Douleur")
        case .impact: String(localized: "Au quotidien")
        case .summary: ""
        }
    }

    func answer(in draft: OnboardingInjuryDraft) -> String? {
        switch self {
        case .kind: draft.kind?.label
        case .side: draft.side?.label
        case .onset: draft.onset?.label
        case .pain: draft.pain.map { String(localized: "\($0)/10") }
        case .impact: draft.impact.flatMap { value in ZoneImpact.all.first { $0.value == value }?.label }
        case .summary: nil
        }
    }
}

/// What the athlete can still do, as a ladder from « all of it » to « nothing ».
struct ZoneImpact: Identifiable, Hashable {
    let value: String
    let label: String
    let detail: String
    let symbol: String

    var id: String { value }

    static let all = [
        ZoneImpact(value: "NONE", label: String(localized: "Aucune gêne"), detail: String(localized: "Tu fais tout comme d'habitude."), symbol: "figure.run"),
        ZoneImpact(value: "MILD", label: String(localized: "Gêne légère"), detail: String(localized: "Tu la sens, sans changer ta séance."), symbol: "figure.walk"),
        ZoneImpact(value: "MODERATE", label: String(localized: "Gêne modérée"), detail: String(localized: "Tu adaptes certaines séances."), symbol: "figure.cooldown"),
        ZoneImpact(value: "LIMITING", label: String(localized: "Limite l'entraînement"), detail: String(localized: "Tu réduis ou coupes des séances."), symbol: "figure.stand"),
        ZoneImpact(value: "STOPPED", label: String(localized: "Empêche de s'entraîner"), detail: String(localized: "Tu ne peux pas t'entraîner."), symbol: "bed.double"),
    ]
}

/// A large square choice: symbol over its word, filled when chosen.
struct ZoneChoiceTile: View {
    let symbol: String
    let title: String
    let isSelected: Bool
    let onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) {
            VStack(spacing: SharpitSpacing.sm) {
                Image(systemName: symbol)
                    .font(.system(size: 26, weight: .semibold))
                Text(title)
                    .font(SharpitTypography.bodyEmphasis)
            }
            .foregroundStyle(isSelected ? SharpitColor.highlightForeground : SharpitColor.foreground)
            .frame(maxWidth: .infinity, minHeight: 112)
            .background(
                RoundedRectangle(cornerRadius: SharpitRadius.panel, style: .continuous)
                    .fill(isSelected ? SharpitColor.highlight : SharpitColor.analysisSurfaceAlt)
            )
            .contentShape(.rect)
        }
        .buttonStyle(.sharpitPressable)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }
}

/// One rung of the impact ladder: its figure, its words, a bar that grows with the limit.
struct ZoneLadderRow: View {
    let impact: ZoneImpact
    let isSelected: Bool
    let onSelect: () -> Void

    private var rung: Int { ZoneImpact.all.firstIndex(of: impact) ?? 0 }

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: SharpitSpacing.sm) {
                SharpitIconTile(symbol: impact.symbol, size: 40)
                VStack(alignment: .leading, spacing: 2) {
                    Text(impact.label)
                        .font(SharpitTypography.bodyEmphasis)
                        .foregroundStyle(SharpitColor.foreground)
                    Text(impact.detail)
                        .font(SharpitTypography.meta)
                        .foregroundStyle(SharpitColor.mutedForeground)
                }
                Spacer(minLength: SharpitSpacing.xs)
                // The rung's weight: one to five bars, the limit read at a glance.
                HStack(alignment: .bottom, spacing: 2) {
                    ForEach(0..<5, id: \.self) { bar in
                        Capsule()
                            .fill(bar <= rung ? SharpitColor.foreground.opacity(0.75) : SharpitColor.analysisGrid)
                            .frame(width: 3, height: 6 + CGFloat(bar) * 3)
                    }
                }
                .accessibilityHidden(true)
            }
            .padding(SharpitSpacing.sm)
            .background(
                RoundedRectangle(cornerRadius: SharpitRadius.panel, style: .continuous)
                    .fill(SharpitColor.analysisSurfaceAlt)
            )
            .overlay(
                RoundedRectangle(cornerRadius: SharpitRadius.panel, style: .continuous)
                    .strokeBorder(SharpitColor.primary, lineWidth: isSelected ? 2 : 0)
            )
            .contentShape(.rect)
        }
        .buttonStyle(.sharpitPressable)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }
}

// MARK: - Notch track

/// A track of stops the finger drags along or taps: the knob settles on each stop with a notch
/// under the finger, the fill takes the stop's tint, an optional marker stands taller at a
/// threshold. Unanswered until touched. VoiceOver adjusts it a stop at a time.
struct NotchTrack: View {
    let stops: Int
    @Binding var value: Int?
    var marker: Int?
    let tint: (Int) -> Color
    var stopLabels: [String] = []
    let accessibilityLabel: String
    let valueLabel: (Int) -> String
    /// Called when the finger lifts on a stop — a question may move on.
    var onRelease: (() -> Void)?

    @State private var isDragging = false

    private let knob: CGFloat = 30
    private let trackHeight: CGFloat = 8

    var body: some View {
        VStack(spacing: SharpitSpacing.xs) {
            GeometryReader { geo in
                let width = geo.size.width - knob
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(SharpitColor.analysisSurfaceAlt)
                        .frame(height: trackHeight)
                        .padding(.horizontal, knob / 2)
                    if let value {
                        Capsule()
                            .fill(tint(value))
                            .frame(width: max(x(value, width), trackHeight), height: trackHeight)
                            .offset(x: knob / 2)
                    }
                    ForEach(0..<stops, id: \.self) { stop in
                        Capsule()
                            .fill(stop == marker ? SharpitColor.foreground.opacity(0.55) : SharpitColor.mutedForeground.opacity(0.35))
                            .frame(width: 2, height: stop == marker ? 22 : 10)
                            .offset(x: knob / 2 + x(stop, width) - 1)
                    }
                    if let value {
                        Circle()
                            .fill(SharpitColor.card)
                            .overlay(Circle().strokeBorder(tint(value), lineWidth: 3))
                            .frame(width: knob, height: knob)
                            .scaleEffect(isDragging ? 1.15 : 1)
                            .sharpitShadow(.panel)
                            .offset(x: x(value, width))
                    }
                }
                .frame(height: 44)
                .contentShape(.rect)
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { drag in
                            if !isDragging {
                                SharpitHaptics.prepare()
                                SharpitMotion.run(SharpitMotion.selection) { isDragging = true }
                            }
                            let stop = Int(((drag.location.x - knob / 2) / max(width, 1) * CGFloat(stops - 1)).rounded())
                            let clamped = min(max(stop, 0), stops - 1)
                            guard clamped != value else { return }
                            SharpitHaptics.play(.notch(major: clamped == marker))
                            SharpitMotion.run(SharpitMotion.selection) { value = clamped }
                        }
                        .onEnded { _ in
                            SharpitMotion.run(SharpitMotion.selection) { isDragging = false }
                            onRelease?()
                        }
                )
            }
            .frame(height: 44)

            if !stopLabels.isEmpty {
                GeometryReader { geo in
                    let width = geo.size.width - knob
                    ZStack(alignment: .topLeading) {
                        ForEach(Array(stopLabels.enumerated()), id: \.offset) { stop, label in
                            Text(label)
                                .font(SharpitTypography.meta)
                                .foregroundStyle(stop == value ? SharpitColor.foreground : SharpitColor.mutedForeground)
                                .fixedSize()
                                .frame(width: 120)
                                .multilineTextAlignment(.center)
                                .offset(x: knob / 2 + x(stop, width) - 60)
                        }
                    }
                }
                .frame(height: 20)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityValue(value.map(valueLabel) ?? String(localized: "Pas encore choisi"))
        .accessibilityAdjustableAction { direction in
            let current = value ?? -1
            switch direction {
            case .increment: value = min(current + 1, stops - 1)
            case .decrement: value = max(current - 1, 0)
            @unknown default: break
            }
        }
    }

    /// The knob's leading offset for a stop.
    private func x(_ stop: Int, _ width: CGFloat) -> CGFloat {
        guard stops > 1 else { return 0 }
        return width * CGFloat(stop) / CGFloat(stops - 1)
    }
}

// MARK: - Health ground sheet

/// One ground's question as an ordered track: its stages from the mildest down, a node each, the
/// line filling to the stage chosen. Stages that owe a medical go-ahead carry the stethoscope
/// before they are picked. « Autre » asks for a few words instead. Sized to its content.
struct HealthGroundSheet: View {
    let entry: HealthGroundCatalog.Entry
    let onSave: (HealthGroundInput) -> Void
    let onRemove: () -> Void
    private let isDeclared: Bool
    @State private var stage: String?
    @State private var details: String
    @State private var contentHeight: CGFloat = 420
    @Environment(\.dismiss) private var dismiss

    init(
        entry: HealthGroundCatalog.Entry,
        declared: HealthGroundInput?,
        onSave: @escaping (HealthGroundInput) -> Void,
        onRemove: @escaping () -> Void
    ) {
        self.entry = entry
        self.onSave = onSave
        self.onRemove = onRemove
        isDeclared = declared != nil
        _stage = State(initialValue: declared?.stage ?? (entry.asksDetails ? entry.stages.first?.id : nil))
        _details = State(initialValue: declared?.details ?? "")
    }

    private var trimmedDetails: String { details.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var canSave: Bool { stage != nil && (!entry.asksDetails || !trimmedDetails.isEmpty) }
    private var draft: HealthGroundInput? {
        stage.map { HealthGroundInput(key: entry.key, stage: $0, details: trimmedDetails.isEmpty ? nil : trimmedDetails) }
    }
    private var selectedIndex: Int? { stage.flatMap { id in entry.stages.firstIndex { $0.id == id } } }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: SharpitSpacing.md) {
                HStack(spacing: SharpitSpacing.sm) {
                    SharpitIconTile(symbol: entry.symbolName, size: 44)
                    Text(entry.question)
                        .font(SharpitTypography.sectionTitle)
                        .tracking(SharpitTypography.sectionTitleTracking)
                        .foregroundStyle(SharpitColor.foreground)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityAddTraits(.isHeader)
                }
                if entry.asksDetails {
                    SharpitFormField(String(localized: "En quelques mots"), placeholder: String(localized: "Asthme d'effort, hernie discale…"), text: $details)
                } else {
                    track
                }
                if let draft, HealthGroundCatalog.needsClearance(draft) {
                    Label(
                        String(localized: "Demande l'avis de ton médecin avant les séances intenses. D'ici là, le coach reste sur une intensité modérée."),
                        systemImage: "stethoscope"
                    )
                    .font(SharpitTypography.meta)
                    .foregroundStyle(SharpitColor.signalCaution)
                    .fixedSize(horizontal: false, vertical: true)
                    .transition(.opacity)
                }
                Button {
                    if let draft { onSave(draft) }
                    dismiss()
                } label: {
                    Text(isDeclared ? String(localized: "Enregistrer") : String(localized: "Ajouter"))
                        .font(SharpitTypography.bodyEmphasis)
                        .foregroundStyle(SharpitColor.primaryForeground)
                        .frame(maxWidth: .infinity)
                }
                .sharpitGlassButton(prominent: true)
                .tint(SharpitColor.primary)
                .disabled(!canSave)
                .padding(.top, SharpitSpacing.xs)
            }
            .padding(SharpitSpacing.pageInset)
            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { height in
                // The bar above the content plus what it needs: no empty half screen.
                contentHeight = height + 72
            }
            .frame(maxHeight: .infinity, alignment: .top)
            .animation(SharpitMotion.selection, value: stage)
            .navigationTitle(entry.label)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Annuler") { dismiss() }
                }
                if isDeclared {
                    ToolbarItem(placement: .destructiveAction) {
                        Button("Retirer", role: .destructive) {
                            onRemove()
                            dismiss()
                        }
                    }
                }
            }
        }
        .presentationDetents([.height(contentHeight)])
    }

    /// The stages as nodes on a line, the line lime down to the chosen one.
    private var track: some View {
        VStack(spacing: 0) {
            ForEach(Array(entry.stages.enumerated()), id: \.element.id) { index, option in
                let isChosen = option.id == stage
                let isReached = selectedIndex.map { index <= $0 } ?? false
                let needsClearance = HealthGroundCatalog.needsClearance(HealthGroundInput(key: entry.key, stage: option.id))
                Button {
                    SharpitMotion.run(SharpitMotion.selection) { stage = option.id }
                } label: {
                    HStack(alignment: .center, spacing: SharpitSpacing.sm) {
                        ZStack {
                            // The segment down to the next node.
                            if index < entry.stages.count - 1 {
                                Rectangle()
                                    .fill(selectedIndex.map { index < $0 } ?? false ? SharpitColor.highlight : SharpitColor.analysisGrid)
                                    .frame(width: 3)
                                    .frame(maxHeight: .infinity)
                                    .offset(y: 28)
                            }
                            Circle()
                                .fill(isReached ? SharpitColor.highlight : SharpitColor.card)
                                .overlay(Circle().strokeBorder(isReached ? SharpitColor.highlight : SharpitColor.analysisGrid, lineWidth: 2))
                                .frame(width: isChosen ? 26 : 20, height: isChosen ? 26 : 20)
                                .overlay {
                                    if isChosen {
                                        Image(systemName: "checkmark")
                                            .font(.system(size: 12, weight: .bold))
                                            .foregroundStyle(SharpitColor.highlightForeground)
                                    }
                                }
                        }
                        .frame(width: 30, height: 56)

                        Text(option.label)
                            .font(isChosen ? SharpitTypography.bodyEmphasis : SharpitTypography.body)
                            .foregroundStyle(SharpitColor.foreground)
                            .multilineTextAlignment(.leading)
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: SharpitSpacing.xs)
                        if needsClearance {
                            Image(systemName: "stethoscope")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(SharpitColor.signalCaution)
                                .accessibilityLabel(String(localized: "Avis médical conseillé"))
                        }
                    }
                    .contentShape(.rect)
                }
                .buttonStyle(.sharpitPressable)
                .accessibilityAddTraits(isChosen ? [.isButton, .isSelected] : .isButton)
            }
        }
    }
}

private extension OnboardingInjuryDraft.Side {
    var symbolName: String {
        switch self {
        case .left: "arrow.left"
        case .right: "arrow.right"
        case .both: "arrow.left.and.right"
        }
    }
}

private extension OnboardingInjuryDraft.Onset {
    /// Under the track's stops.
    var shortLabel: String {
        switch self {
        case .recent: String(localized: "< 2 sem.")
        case .weeks: String(localized: "2 sem. – 3 mois")
        case .persistent: String(localized: "> 3 mois")
        }
    }
}
