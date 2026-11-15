import SwiftUI

/// Declares or edits a zone, one question per page — same flow as the onboarding zone sheet
/// (ADR-0032): chips to go back, NotchTrack for pain, impact ladder, summary with optional extras.
struct SensitiveZoneFormSheet: View {
    @State var draft: SensitiveZoneDraft
    let bodyParts: [String]
    var figure: SensitiveZoneFigure = .male
    let isNew: Bool
    let onSave: (SensitiveZoneDraft) async -> Bool

    @State private var question: ZoneFormQuestion = .where
    @State private var isForward = true
    @State private var contentHeight: CGFloat = 420
    @State private var writesOwnPart = false
    @State private var isSaving = false
    @State private var failed = false
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let grid = Array(repeating: GridItem(.flexible(), spacing: SharpitSpacing.xs), count: 3)

    init(
        draft: SensitiveZoneDraft,
        bodyParts: [String],
        figure: SensitiveZoneFigure = .male,
        isNew: Bool,
        onSave: @escaping (SensitiveZoneDraft) async -> Bool
    ) {
        _draft = State(initialValue: draft)
        self.bodyParts = bodyParts
        self.figure = figure
        self.isNew = isNew
        self.onSave = onSave
        _writesOwnPart = State(initialValue: draft.bodyPart == nil && !draft.customBodyPart.isEmpty)
        // Editing opens on the summary; a new zone on its first open question.
        _question = State(initialValue: isNew ? ZoneFormQuestion.firstOpen(in: draft) : .summary)
    }

    private var place: String {
        SensitiveZoneBody.caption(part: draft.region, side: draft.side)
            ?? draft.region
            ?? (isNew ? String(localized: "Nouvelle zone") : String(localized: "Modifier la zone"))
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
            }
        }
        .presentationDetents(question == .where ? [.large] : [.height(max(contentHeight, 320)), .large])
        .presentationDragIndicator(.visible)
        .sharpitSheet()
    }

    // MARK: Flow

    private var pageTransition: AnyTransition {
        if reduceMotion { return .opacity }
        let insertion: Edge = isForward ? .trailing : .leading
        let removal: Edge = isForward ? .leading : .trailing
        return .asymmetric(
            insertion: .move(edge: insertion).combined(with: .opacity),
            removal: .move(edge: removal).combined(with: .opacity)
        )
    }

    private func go(to next: ZoneFormQuestion) {
        let path = ZoneFormQuestion.path(for: draft)
        isForward = (path.firstIndex(of: next) ?? 0) >= (path.firstIndex(of: question) ?? 0)
        SharpitMotion.run(SharpitMotion.reveal) { question = next }
    }

    private func advance() {
        go(to: ZoneFormQuestion.firstOpen(in: draft, after: question))
    }

    private func save() {
        guard !isSaving else { return }
        isSaving = true
        failed = false
        Task {
            let saved = await onSave(draft)
            isSaving = false
            if saved { dismiss() } else { failed = true }
        }
    }

    // MARK: Answers

    private var answers: some View {
        ScrollView(.horizontal) {
            HStack(spacing: SharpitSpacing.xs) {
                ForEach(ZoneFormQuestion.path(for: draft).filter { $0 != .summary }, id: \.self) { step in
                    if let value = step.answer(in: draft) {
                        Button { go(to: step) } label: {
                            Text(value)
                                .font(SharpitTypography.meta.weight(.semibold))
                                .foregroundStyle(step == question ? SharpitColor.primaryForeground : SharpitColor.foreground)
                                .padding(.horizontal, SharpitSpacing.sm)
                                .frame(minHeight: 32)
                                .background(
                                    Capsule().fill(step == question ? SharpitColor.primary : SharpitColor.tile)
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
    private func page(_ step: ZoneFormQuestion) -> some View {
        VStack(alignment: .leading, spacing: SharpitSpacing.md) {
            Text(step.title)
                .font(SharpitTypography.sectionTitle)
                .tracking(SharpitTypography.sectionTitleTracking)
                .foregroundStyle(SharpitColor.foreground)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
            switch step {
            case .where: wherePage
            case .category: categoryPage
            case .side: sidePage
            case .severity: severityPage
            case .impact: impactPage
            case .summary: summaryPage
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    private var offListParts: [String] {
        bodyParts.filter { !SensitiveZoneBody.mappedParts.contains($0) }
    }

    private var wherePage: some View {
        VStack(alignment: .leading, spacing: SharpitSpacing.sm) {
            if bodyParts.contains(where: SensitiveZoneBody.mappedParts.contains) {
                SensitiveZoneBodyPicker(
                    offered: bodyParts,
                    figure: figure,
                    part: Binding(
                        get: { writesOwnPart ? nil : draft.bodyPart },
                        set: { draft.bodyPart = $0 }
                    ),
                    side: $draft.side,
                    onPick: { writesOwnPart = false }
                )
            }
            LazyVGrid(columns: grid, spacing: SharpitSpacing.xs) {
                ForEach(offListParts, id: \.self) { part in
                    OnboardingChoiceChip(title: part, isSelected: draft.bodyPart == part && !writesOwnPart) {
                        writesOwnPart = false
                        draft.bodyPart = part
                        draft.side = "NA"
                    }
                }
                OnboardingChoiceChip(title: String(localized: "Autre…"), isSelected: writesOwnPart) {
                    writesOwnPart = true
                    draft.bodyPart = nil
                }
            }
            if writesOwnPart {
                TextField("Ex. : plexus", text: $draft.customBodyPart)
                    .font(SharpitTypography.body)
                    .sharpitFieldWell()
                Text("Une zone hors liste reste suivie, mais le plan ne peut pas vérifier qu'il l'épargne.")
                    .font(SharpitTypography.meta)
                    .foregroundStyle(SharpitColor.slate)
                    .fixedSize(horizontal: false, vertical: true)
            }
            nextButton(String(localized: "Suivant"), isEnabled: draft.region != nil, action: advance)
        }
    }

    private var categoryPage: some View {
        VStack(spacing: SharpitSpacing.xs) {
            ForEach(SensitiveZoneOptions.categories) { choice in
                MotivationRow(
                    symbol: SensitiveZoneOptions.categorySymbol(choice.value),
                    title: choice.label,
                    detail: SensitiveZoneOptions.categoryDetail(choice.value),
                    isSelected: draft.category == choice.value
                ) {
                    draft.category = choice.value
                    advance()
                }
            }
        }
    }

    private var sidePage: some View {
        HStack(spacing: SharpitSpacing.xs) {
            ForEach(SensitiveZoneOptions.sides.filter { $0.value != "NA" }) { choice in
                ZoneChoiceTile(
                    symbol: sideSymbol(choice.value),
                    title: choice.label,
                    isSelected: draft.side == choice.value
                ) {
                    draft.side = choice.value
                    advance()
                }
            }
        }
    }

    private func sideSymbol(_ value: String) -> String {
        switch value {
        case "LEFT": "arrow.left"
        case "RIGHT": "arrow.right"
        case "BILATERAL": "arrow.left.arrow.right"
        default: "minus"
        }
    }

    private var severityPage: some View {
        let corrective = SensitiveZoneOptions.isCorrective(draft.category ?? "")
        return VStack(alignment: .leading, spacing: SharpitSpacing.lg) {
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(draft.severity.map(String.init) ?? "—")
                    .font(SharpitTypography.heroScore)
                    .tracking(SharpitTypography.heroScoreTracking)
                    .foregroundStyle(ZoneSeverityTint.color(draft.severity))
                    .contentTransition(.numericText(value: Double(draft.severity ?? 0)))
                Text("/10")
                    .font(SharpitTypography.bodyEmphasis)
                    .foregroundStyle(SharpitColor.slate)
                Spacer()
                Text(draft.severity.map(ZoneSeverityTint.caption) ?? "")
                    .font(SharpitTypography.bodyEmphasis)
                    .foregroundStyle(SharpitColor.slate)
                    .contentTransition(.opacity)
            }
            .animation(SharpitMotion.selection, value: draft.severity)

            NotchTrack(
                stops: 11,
                value: $draft.severity,
                marker: SensitiveZoneOptions.painThreshold,
                tint: { ZoneSeverityTint.color($0) },
                stopLabels: Self.painStopLabels,
                accessibilityLabel: corrective
                    ? String(localized: "Gêne sur 10")
                    : String(localized: "Douleur sur 10"),
                valueLabel: { String(localized: "\($0) sur 10") }
            )

            Text(severityCaption(corrective: corrective))
                .font(SharpitTypography.meta)
                .foregroundStyle(SharpitColor.slate)
                .fixedSize(horizontal: false, vertical: true)

            nextButton(String(localized: "Suivant"), isEnabled: draft.severity != nil, action: advance)
        }
        .padding(.top, SharpitSpacing.sm)
    }

    private static let painStopLabels: [String] = (0...10).map { [0, 5, 10].contains($0) ? String($0) : "" }

    private func severityCaption(corrective: Bool) -> String {
        guard let severity = draft.severity else {
            return corrective
                ? String(localized: "Fais glisser jusqu'à ton niveau de gêne.")
                : String(localized: "Fais glisser jusqu'à ton niveau de douleur.")
        }
        return severity <= SensitiveZoneOptions.painThreshold
            ? String(localized: "Jusqu'à 5, le coach peut garder de la charge en surveillant.")
            : String(localized: "Au-delà de 5, le coach allège les séances qui sollicitent la zone.")
    }

    private var impactPage: some View {
        VStack(spacing: SharpitSpacing.xs) {
            ForEach(ZoneImpact.all) { impact in
                ZoneLadderRow(
                    impact: impact,
                    isSelected: draft.functionalImpact == impact.value
                ) {
                    draft.functionalImpact = impact.value
                    advance()
                }
            }
        }
    }

    private var summaryPage: some View {
        VStack(alignment: .leading, spacing: SharpitSpacing.md) {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(
                    Array(ZoneFormQuestion.path(for: draft).filter { $0 != .summary }.enumerated()),
                    id: \.element
                ) { index, step in
                    if index > 0 {
                        Rectangle().fill(SharpitColor.divider).frame(height: 1)
                    }
                    Button { go(to: step) } label: {
                        HStack {
                            Text(step.shortTitle)
                                .font(SharpitTypography.meta)
                                .foregroundStyle(SharpitColor.slate)
                            Spacer(minLength: SharpitSpacing.sm)
                            Text(step.answer(in: draft) ?? "—")
                                .font(SharpitTypography.bodyEmphasis)
                                .foregroundStyle(SharpitColor.foreground)
                                .multilineTextAlignment(.trailing)
                            Image(systemName: "chevron.right")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(SharpitColor.slate.opacity(0.6))
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

            SharpitFormField(
                String(localized: "Nom (facultatif)"),
                placeholder: draft.resolvedTitle,
                text: $draft.title
            )
            VStack(alignment: .leading, spacing: SharpitSpacing.xs) {
                SharpitFieldLabel(String(localized: "Notes (facultatif)"))
                TextField("Quand ça apparaît, ce qui soulage…", text: $draft.description, axis: .vertical)
                    .font(SharpitTypography.body)
                    .lineLimit(2...4)
                    .sharpitFieldWell()
            }
            Toggle(isOn: $draft.affectsTraining) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Prise en compte dans le plan")
                        .font(SharpitTypography.bodyEmphasis)
                    Text("Le coach adapte les séances à cette zone.")
                        .font(SharpitTypography.meta)
                        .foregroundStyle(SharpitColor.slate)
                }
            }
            .tint(SharpitColor.primary)

            if failed {
                Text("L'enregistrement a échoué. Réessaie.")
                    .font(SharpitTypography.meta)
                    .foregroundStyle(SharpitColor.signalRisk)
            }

            nextButton(
                isNew ? String(localized: "Ajouter") : String(localized: "Enregistrer"),
                isEnabled: draft.isComplete && !isSaving,
                action: save
            )
        }
    }

    private func nextButton(_ title: String, isEnabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                if isSaving { ProgressView().tint(SharpitColor.primaryForeground) }
                Text(title)
                    .font(SharpitTypography.bodyEmphasis)
                    .foregroundStyle(SharpitColor.primaryForeground)
            }
            .frame(maxWidth: .infinity)
        }
        .sharpitGlassButton(prominent: true)
        .tint(SharpitColor.primary)
        .disabled(!isEnabled)
        .padding(.bottom, SharpitSpacing.sm)
    }
}

/// Questions of the Santé declare / edit sheet, in order.
enum ZoneFormQuestion: Hashable, CaseIterable {
    case `where`, category, side, severity, impact, summary

    static func path(for draft: SensitiveZoneDraft) -> [ZoneFormQuestion] {
        var path: [ZoneFormQuestion] = [.where, .category]
        if draft.asksForSide { path.append(.side) }
        path += [.severity, .impact, .summary]
        return path
    }

    static func firstOpen(in draft: SensitiveZoneDraft, after current: ZoneFormQuestion? = nil) -> ZoneFormQuestion {
        let path = path(for: draft)
        let start = current.flatMap { path.firstIndex(of: $0) }.map { $0 + 1 } ?? 0
        return path[start...].first { $0 != .summary && $0.answer(in: draft) == nil } ?? .summary
    }

    var title: String {
        switch self {
        case .where: String(localized: "Où ?")
        case .category: String(localized: "Qu'est-ce que c'est ?")
        case .side: String(localized: "Quel côté ?")
        case .severity: String(localized: "Combien ça fait mal ?")
        case .impact: String(localized: "Ce que tu peux encore faire")
        case .summary: String(localized: "On récapitule")
        }
    }

    var shortTitle: String {
        switch self {
        case .where: String(localized: "Où")
        case .category: String(localized: "Type")
        case .side: String(localized: "Côté")
        case .severity: String(localized: "Douleur")
        case .impact: String(localized: "Au quotidien")
        case .summary: ""
        }
    }

    func answer(in draft: SensitiveZoneDraft) -> String? {
        switch self {
        case .where:
            return SensitiveZoneBody.caption(part: draft.region, side: draft.side) ?? draft.region
        case .category:
            return draft.category.map { SensitiveZoneOptions.label($0, in: SensitiveZoneOptions.categories) }
        case .side:
            // « NA » means not chosen yet for an off-map part (the silhouette sets LEFT/RIGHT itself).
            guard draft.asksForSide, draft.side != "NA" else { return nil }
            return SensitiveZoneOptions.label(draft.side, in: SensitiveZoneOptions.sides)
        case .severity:
            return draft.severity.map { String(localized: "\($0)/10") }
        case .impact:
            return draft.functionalImpact.flatMap { value in ZoneImpact.all.first { $0.value == value }?.label }
        case .summary:
            return nil
        }
    }
}

/// A follow-up after a session (or from Santé): how much it hurts, what still works, a word.
/// Opens as a medium drawer — one question, one reading — not a full-page form.
struct ZoneCheckinSheet: View {
    let zone: V1SensitiveZone
    /// Asked above the scales when the check-in follows a session.
    var prompt: String? = nil
    let onSave: (ZoneCheckinDraft) async -> Bool

    @State private var draft = ZoneCheckinDraft()
    @State private var isSaving = false
    @State private var failed = false
    @Environment(\.dismiss) private var dismiss

    private var isCorrective: Bool { SensitiveZoneOptions.isCorrective(zone.category) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                header
                    .padding(.bottom, 24)
                CliniqueScale(
                    title: isCorrective ? String(localized: "Gêne") : String(localized: "Douleur"),
                    values: Array(0...10),
                    selection: draft.severity,
                    word: ZoneSeverityTint.caption,
                    ends: (String(localized: "Aucune"), String(localized: "Insupportable"))
                ) { draft.severity = $0 }
                CliniqueDivider().padding(.vertical, 18)
                impactBlock
                CliniqueDivider().padding(.vertical, 18)
                commentBlock
                if failed {
                    Text("L'enregistrement a échoué. Réessaie.")
                        .font(SharpitTypography.meta)
                        .foregroundStyle(SharpitColor.statusAlertForeground)
                        .padding(.top, 12)
                }
            }
            .padding(.horizontal, 24)
            .padding(.top, 30)
            .padding(.bottom, SharpitSpacing.lg)
        }
        .scrollDismissesKeyboard(.interactively)
        .background(SharpitColor.card)
        .cliniqueSheetCross { dismiss() }
        .safeAreaInset(edge: .bottom, spacing: 0) { saveBar }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .sharpitSheet()
    }

    /// The question first — what the sheet is for — then which zone it is about.
    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            CliniqueSheetTitle(prompt ?? (isCorrective ? String(localized: "Comment ça va aujourd'hui ?") : String(localized: "Comment va la douleur ?")))
                .fixedSize(horizontal: false, vertical: true)
            Text(prompt == nil ? "\(zone.title) · \(zone.place)" : zone.place)
                .font(SharpitTypography.system(size: 15, weight: .regular, relativeTo: .subheadline))
                .foregroundStyle(SharpitColor.slate)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// What the athlete could do, one answer of a short list: lines, the chosen one checked.
    private var impactBlock: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Ce que tu as pu faire")
                .font(SharpitTypography.system(size: 16, weight: .semibold, relativeTo: .body))
                .foregroundStyle(SharpitColor.foreground)
                .accessibilityAddTraits(.isHeader)
            ForEach(Array(SensitiveZoneOptions.impacts.enumerated()), id: \.element.id) { index, option in
                let isSelected = draft.functionalImpact == option.value
                if index > 0 { CliniqueDivider() }
                Button {
                    SharpitMotion.run(SharpitMotion.selection) {
                        draft.functionalImpact = isSelected ? nil : option.value
                    }
                } label: {
                    HStack(spacing: SharpitSpacing.sm) {
                        Text(option.label)
                            .font(SharpitTypography.system(size: 16, weight: isSelected ? .semibold : .regular, relativeTo: .callout))
                            .foregroundStyle(SharpitColor.foreground)
                            .multilineTextAlignment(.leading)
                        Spacer(minLength: 0)
                        Image(systemName: "checkmark")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(SharpitColor.foreground)
                            .opacity(isSelected ? 1 : 0)
                            .accessibilityHidden(true)
                    }
                    .frame(maxWidth: .infinity, minHeight: 48, alignment: .leading)
                    .contentShape(.rect)
                }
                .buttonStyle(.sharpitPressable)
                .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
            }
        }
    }

    private var commentBlock: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Un mot pour le coach")
                .font(SharpitTypography.system(size: 14, weight: .regular, relativeTo: .footnote))
                .foregroundStyle(SharpitColor.slate)
            TextField("Après la séance, au réveil…", text: $draft.comment, axis: .vertical)
                .lineLimit(2...4)
                .font(SharpitTypography.system(size: 16, weight: .regular, relativeTo: .callout))
                .padding(16)
                .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(SharpitColor.divider, lineWidth: 1))
        }
    }

    private var saveBar: some View {
        Group {
            Button {
                guard !isSaving else { return }
                isSaving = true
                Task {
                    let saved = await onSave(draft)
                    isSaving = false
                    if saved { dismiss() } else { failed = true }
                }
            } label: {
                HStack {
                    if isSaving { ProgressView().tint(SharpitColor.primaryForeground) }
                    Text(isSaving ? String(localized: "Enregistrement…") : String(localized: "Enregistrer"))
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(CliniqueButtonStyle(kind: .primary, isLarge: true))
            .disabled(!draft.isComplete || isSaving)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, SharpitSpacing.xs)
        .background(SharpitColor.card)
    }
}

/// 0 to 10 in two comfortable rows — a pain is reported, not measured. Unanswered until touched.
/// Also the onboarding's pain question.
struct ZoneSeverityScale: View {
    @Binding var severity: Int?

    var body: some View {
        VStack(alignment: .leading, spacing: SharpitSpacing.xs) {
            severityRow(0...5)
            severityRow(6...10)
            HStack {
                Text("Aucune")
                Spacer()
                Text("Insupportable")
            }
            .font(SharpitTypography.meta)
            .foregroundStyle(SharpitColor.slate)
        }
    }

    private func severityRow(_ values: ClosedRange<Int>) -> some View {
        HStack(spacing: SharpitSpacing.xs) {
            ForEach(Array(values), id: \.self) { value in
                let isSelected = severity == value
                Button {
                    SharpitMotion.run(SharpitMotion.selection) { severity = value }
                } label: {
                    Text("\(value)")
                        .font(SharpitTypography.data)
                        .monospacedDigit()
                        .foregroundStyle(SharpitColor.foreground)
                        .frame(maxWidth: .infinity)
                        .frame(height: 48)
                        // A hairline tile, lined in ink once chosen; the level's hue stays a mark under the figure.
                        .overlay(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .strokeBorder(isSelected ? SharpitColor.foreground : SharpitColor.outline, lineWidth: isSelected ? 2 : 1)
                        )
                        .overlay(alignment: .bottom) {
                            if isSelected {
                                Capsule().fill(ZoneSeverityTint.color(value)).frame(width: 16, height: 3).padding(.bottom, 6)
                            }
                        }
                        .contentShape(.rect)
                }
                .buttonStyle(.sharpitPressable)
                .accessibilityLabel("\(value) sur 10")
                .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
            }
        }
    }
}

