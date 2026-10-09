import OSLog
import SwiftUI

/// A food-log write the coach proposed (`tool-logFoods`), as the thread shows it.
nonisolated struct CoachFoodLogProposal: Equatable, Identifiable {
    struct Item: Equatable, Identifiable {
        let id: String
        var name: String
        var grams: Double
        var kcalPer100g: Double
        var proteinPer100g: Double
        var carbsPer100g: Double
        var fatPer100g: Double
    }

    let id: String
    /// The approval id the store answers with — kept across failed states for « Réessayer ».
    let approvalId: String
    let status: CoachProposal.Status
    let date: String?
    let meal: FoodLogMeal
    let items: [Item]
    /// Original tool input — kept so macros survive when the athlete edits grams/meal.
    let baseInput: [String: JSONValue]

    /// Nil for a part that is not a food-log proposal.
    init?(part: JSONValue) {
        guard part["type"]?.string == "tool-logFoods" else { return nil }
        let input = part["input"] ?? .object([:])
        let output = part["output"]

        id = part["toolCallId"]?.string ?? part["approval"]?["id"]?.string ?? "logFoods"
        approvalId = part["approval"]?["id"]?.string ?? id
        if case .object(let object) = input {
            baseInput = object
        } else {
            baseInput = [:]
        }

        let state = part["state"]?.string ?? ""
        let approval = part["approval"]
        switch state {
        case "approval-requested" where approval?["isAutomatic"] != .bool(true):
            status = .awaiting(approvalId: approvalId)
        case "approval-responded":
            status = approval?["approved"] == .bool(false) ? .refused : .accepted
        case "output-denied":
            status = .refused
        case "output-available" where output?["ok"] != .bool(false):
            status = .applied
        case "output-available", "output-error":
            let raw = (output?["error"]?.string ?? part["errorText"]?.string)?
                .trimmingCharacters(in: .whitespaces)
            status = .failed(raw?.nilIfEmpty ?? "Ces aliments n'ont pas pu être ajoutés au journal")
        default:
            status = .drafting
        }

        date = (input["date"]?.string ?? output?["date"]?.string).map(Self.formattedDate)
        if let mealRaw = input["meal"]?.string, let meal = FoodLogMeal(rawValue: mealRaw) {
            self.meal = meal
        } else {
            meal = .lunch
        }

        let rawItems = input["items"]?.array ?? []
        items = rawItems.enumerated().compactMap { index, value in
            guard let name = value["name"]?.string?.trimmingCharacters(in: .whitespaces), !name.isEmpty
            else { return nil }
            let grams = value["grams"]?.number ?? 100
            return Item(
                id: "\(index)-\(name)",
                name: name,
                grams: grams,
                kcalPer100g: value["kcalPer100g"]?.number ?? 0,
                proteinPer100g: value["proteinPer100g"]?.number ?? 0,
                carbsPer100g: value["carbsPer100g"]?.number ?? 0,
                fatPer100g: value["fatPer100g"]?.number ?? 0
            )
        }
        // Drafting may arrive before items stream in; awaiting needs at least one line.
        if items.isEmpty, case .awaiting = status { return nil }
    }

    /// Tool input after the athlete adjusted meal and grams.
    func patchedInput(meal: FoodLogMeal, items: [Item]) -> JSONValue {
        var next = baseInput
        next["meal"] = .string(meal.rawValue)
        next["items"] = .array(items.map { item in
            .object([
                "name": .string(item.name),
                "grams": .number(item.grams),
                "kcalPer100g": .number(item.kcalPer100g),
                "proteinPer100g": .number(item.proteinPer100g),
                "carbsPer100g": .number(item.carbsPer100g),
                "fatPer100g": .number(item.fatPer100g),
            ])
        })
        return .object(next)
    }

    /// Parses edited grams back into proposal items. Nil when any line is empty or out of range.
    static func readyItems(from lines: [(gramsText: String, source: Item)]) -> [Item]? {
        var items: [Item] = []
        for line in lines {
            guard let grams = FoodLogForm.grams(line.gramsText), grams > 0 else { return nil }
            var item = line.source
            item.grams = grams
            items.append(item)
        }
        return items.isEmpty ? nil : items
    }

    /// Quick picks for a proposed weight: the coach's portion when distinct, then 100 g and 200 g.
    static func gramPresets(proposedGrams: Double) -> [FoodPortion.Preset] {
        var presets: [FoodPortion.Preset] = []
        let rounded = proposedGrams.rounded()
        if proposedGrams > 0, rounded != 100, rounded != 200 {
            presets.append(FoodPortion.Preset(label: "Portion · \(FoodPortion.gramsLabel(proposedGrams))", grams: proposedGrams))
        }
        presets.append(FoodPortion.Preset(label: "100 g", grams: 100))
        presets.append(FoodPortion.Preset(label: "200 g", grams: 200))
        return presets
    }

    private static func formattedDate(_ raw: String) -> String {
        let parts = raw.split(separator: "-")
        guard parts.count == 3, let month = Int(parts[1]), let day = Int(parts[2]) else { return raw }
        return "\(day)/\(month)"
    }
}

/// Editable food-log proposal: meal picker + grams, then Ajouter / Refuser.
struct CoachFoodLogCard: View {
    let proposal: CoachFoodLogProposal
    /// Nil while an answer is on its way. Passes optional patched tool input on approve.
    let onAnswer: ((Bool, JSONValue?) -> Void)?
    /// Re-sends after a failed application (clears the store's fingerprint).
    var onRetry: ((JSONValue?) -> Void)?
    var onOpenNutrition: (() -> Void)?
    /// True while the coach stream owns the thread — for the disabled reason and DEBUG log.
    var isReplying: Bool = false

    @State private var meal: FoodLogMeal
    @State private var lines: [EditableLine]
    @State private var isSending = false
    @FocusState private var focusedLineId: String?

    init(
        proposal: CoachFoodLogProposal,
        onAnswer: ((Bool, JSONValue?) -> Void)?,
        onRetry: ((JSONValue?) -> Void)? = nil,
        onOpenNutrition: (() -> Void)? = nil,
        isReplying: Bool = false
    ) {
        self.proposal = proposal
        self.onAnswer = onAnswer
        self.onRetry = onRetry
        self.onOpenNutrition = onOpenNutrition
        self.isReplying = isReplying
        _meal = State(initialValue: proposal.meal)
        _lines = State(initialValue: Self.editableLines(proposal.items))
    }

    private static func editableLines(_ items: [CoachFoodLogProposal.Item]) -> [EditableLine] {
        items.map {
            EditableLine(
                id: $0.id,
                name: $0.name,
                gramsText: FoodPortion.editableFigure($0.grams),
                source: $0
            )
        }
    }

    private struct EditableLine: Identifiable, Equatable {
        let id: String
        let name: String
        var gramsText: String
        let source: CoachFoodLogProposal.Item
    }

    private enum Phase: Equatable {
        case proposed
        case sending
        case applied
        case failed(String)
        case refused
        case drafting
    }

    private var phase: Phase {
        switch proposal.status {
        case .awaiting:
            return isSending ? .sending : .proposed
        case .accepted:
            return .sending
        case .drafting:
            return isSending ? .sending : .drafting
        case .applied:
            return .applied
        case .refused:
            return .refused
        case .failed(let hint):
            return .failed(hint)
        }
    }

    var body: some View {
        Group {
            switch phase {
            case .proposed:
                card
            case .sending, .drafting:
                receipt(status: "Envoi…", symbol: "fork.knife", tone: SharpitColor.mutedForeground, inProgress: true)
            case .applied:
                appliedReceipt
            case .refused:
                receipt(status: "Refusé", symbol: "xmark.circle", tone: SharpitColor.mutedForeground, struck: true)
            case .failed(let hint):
                failedReceipt(hint)
            }
        }
        .animation(SharpitMotion.reveal, value: phase)
        // The card is born while the coach still streams the tool input: the foods and the meal
        // arrive after it, and @State would keep the empty draft. The athlete edits only once
        // the input is final, so following it never overwrites their changes.
        .onChange(of: proposal.items) { _, items in lines = Self.editableLines(items) }
        .onChange(of: proposal.meal) { _, new in meal = new }
        .onChange(of: proposal.status) { _, new in
            if case .awaiting = new {
                isSending = false
            } else if case .failed = new {
                isSending = false
            } else if case .applied = new {
                isSending = false
            } else if case .refused = new {
                isSending = false
            }
        }
    }

    private var readyItems: [CoachFoodLogProposal.Item]? {
        CoachFoodLogProposal.readyItems(from: lines.map { ($0.gramsText, $0.source) })
    }

    private var canSubmit: Bool { readyItems != nil && onAnswer != nil && !isSending }

    private var disabledReason: String? {
        guard phase == .proposed else { return nil }
        if isReplying || onAnswer == nil { return "Le coach répond encore" }
        if readyItems == nil { return "Grammage invalide" }
        return nil
    }

    private var card: some View {
        VStack(alignment: .leading, spacing: SharpitSpacing.md) {
            SharpitCardHeader(
                title: "Proposé",
                symbol: "fork.knife",
                tint: SharpitColor.primary,
                showsChevron: false
            ) {
                if let date = proposal.date {
                    Text(date)
                        .font(SharpitTypography.meta)
                        .foregroundStyle(SharpitColor.mutedForeground)
                        .lineLimit(1)
                }
            }

            FoodMealPicker(meal: $meal)

            VStack(alignment: .leading, spacing: SharpitSpacing.sm) {
                ForEach($lines) { $line in
                    foodLine(line: $line)
                }
            }

            if let disabledReason {
                Text(disabledReason)
                    .font(SharpitTypography.meta)
                    .foregroundStyle(SharpitColor.mutedForeground)
            }

            HStack(spacing: SharpitSpacing.sm) {
                answerButton("Refuser", prominent: false, enabled: onAnswer != nil && !isSending) {
                    logTap()
                    isSending = true
                    onAnswer?(false, nil)
                }
                answerButton(addTitle, prominent: true, enabled: canSubmit) {
                    logTap()
                    guard let items = readyItems else { return }
                    isSending = true
                    onAnswer?(true, proposal.patchedInput(meal: meal, items: items))
                }
                .accessibilityLabel(addAccessibilityLabel)
            }
        }
        .padding(SharpitSpacing.cardPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .sharpitSurface(.panel)
        .sharpitCardSpecularBorder()
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("OK") { focusedLineId = nil }
                    .font(SharpitTypography.bodyEmphasis)
                    .foregroundStyle(SharpitColor.foreground)
            }
        }
    }

    private func foodLine(line: Binding<EditableLine>) -> some View {
        let gramsValid = FoodLogForm.grams(line.wrappedValue.gramsText) != nil
        let grams = FoodLogForm.grams(line.wrappedValue.gramsText) ?? line.wrappedValue.source.grams
        let nutrients = Self.nutrients(for: line.wrappedValue.source, grams: grams)
        return VStack(alignment: .leading, spacing: SharpitSpacing.xs) {
            Text(line.wrappedValue.name)
                .font(SharpitTypography.body.weight(.semibold))
                .foregroundStyle(SharpitColor.foreground)
                .fixedSize(horizontal: false, vertical: true)

            let presets = CoachFoodLogProposal.gramPresets(proposedGrams: line.wrappedValue.source.grams)
            if !presets.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: SharpitSpacing.xs) {
                        ForEach(presets) { preset in
                            Button {
                                line.wrappedValue.gramsText = FoodPortion.editableFigure(preset.grams)
                            } label: {
                                Text(preset.label)
                                    .font(SharpitTypography.meta.weight(.medium))
                                    .foregroundStyle(
                                        isPresetSelected(preset, text: line.wrappedValue.gramsText)
                                            ? SharpitColor.primaryForeground
                                            : SharpitColor.foreground
                                    )
                                    .padding(.horizontal, SharpitSpacing.sm)
                                    .frame(minHeight: 32)
                                    .background(
                                        isPresetSelected(preset, text: line.wrappedValue.gramsText)
                                            ? SharpitColor.primary
                                            : SharpitColor.analysisSurfaceAlt,
                                        in: Capsule()
                                    )
                                    .contentShape(Capsule())
                            }
                            .buttonStyle(.plain)
                            .accessibilityAddTraits(
                                isPresetSelected(preset, text: line.wrappedValue.gramsText)
                                    ? [.isButton, .isSelected]
                                    : .isButton
                            )
                        }
                    }
                    .padding(.vertical, 2)
                }
            }

            HStack(spacing: SharpitSpacing.xxs) {
                TextField("100", text: line.gramsText)
                    .keyboardType(.decimalPad)
                    .font(SharpitTypography.data)
                    .foregroundStyle(SharpitColor.foreground)
                    .focused($focusedLineId, equals: line.wrappedValue.id)
                    .accessibilityLabel("Grammes, \(line.wrappedValue.name)")
                Text("g")
                    .font(SharpitTypography.meta)
                    .foregroundStyle(SharpitColor.mutedForeground)
            }
            .padding(.horizontal, SharpitSpacing.sm)
            .frame(maxWidth: .infinity, minHeight: SharpitSpacing.minimumTouchTarget, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: SharpitSpacing.chipRadius, style: .continuous)
                    .fill(SharpitColor.analysisSurfaceAlt)
            )
            .overlay(
                RoundedRectangle(cornerRadius: SharpitSpacing.chipRadius, style: .continuous)
                    .strokeBorder(
                        gramsValid ? (focusedLineId == line.wrappedValue.id ? SharpitColor.primary : Color.clear)
                            : SharpitColor.signalRisk,
                        lineWidth: gramsValid ? 1.5 : 1.5
                    )
            )
            .contentShape(RoundedRectangle(cornerRadius: SharpitSpacing.chipRadius, style: .continuous))
            .onTapGesture { focusedLineId = line.wrappedValue.id }

            FoodPortionPreview(nutrients: nutrients)
        }
    }

    private var addTitle: String {
        let count = lines.count
        return count <= 1 ? "Ajouter" : "Ajouter les \(count)"
    }

    private var addAccessibilityLabel: String {
        let parts = lines.map { line in
            let grams = FoodLogForm.grams(line.gramsText).map(FoodPortion.gramsLabel) ?? line.gramsText
            return "\(line.name), \(grams)"
        }
        return "Ajouter \(parts.joined(separator: ", "))"
    }

    private func answerButton(
        _ title: String,
        prominent: Bool,
        enabled: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Text(title)
                .font(SharpitTypography.body.weight(.semibold))
                .foregroundStyle(
                    enabled
                        ? (prominent ? SharpitColor.primaryForeground : SharpitColor.foreground)
                        : SharpitColor.mutedForeground
                )
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .frame(maxWidth: .infinity)
                .frame(minHeight: SharpitSpacing.minimumTouchTarget)
                .background(
                    enabled
                        ? (prominent ? SharpitColor.primary : SharpitColor.analysisSurfaceAlt)
                        : SharpitColor.analysisSurfaceAlt,
                    in: RoundedRectangle(cornerRadius: 12, style: .continuous)
                )
                .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .accessibilityAddTraits(.isButton)
    }

    private var appliedReceipt: some View {
        VStack(alignment: .leading, spacing: SharpitSpacing.sm) {
            receipt(status: appliedLabel, symbol: "checkmark.circle.fill", tone: SharpitColor.signalRecovery)
            if let onOpenNutrition {
                Button(action: onOpenNutrition) {
                    Text("Voir dans Nutrition")
                        .font(SharpitTypography.meta.weight(.semibold))
                        .foregroundStyle(SharpitColor.primary)
                        .frame(minHeight: SharpitSpacing.minimumTouchTarget, alignment: .leading)
                        .contentShape(.rect)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func failedReceipt(_ hint: String) -> some View {
        VStack(alignment: .leading, spacing: SharpitSpacing.sm) {
            receipt(status: hint, symbol: "exclamationmark.triangle.fill", tone: SharpitColor.signalRisk)
            if let onRetry {
                Button {
                    let items = readyItems ?? proposal.items
                    isSending = true
                    onRetry(proposal.patchedInput(meal: meal, items: items))
                } label: {
                    Text("Réessayer")
                        .font(SharpitTypography.body.weight(.semibold))
                        .foregroundStyle(SharpitColor.primaryForeground)
                        .frame(maxWidth: .infinity)
                        .frame(minHeight: SharpitSpacing.minimumTouchTarget)
                        .background(SharpitColor.primary, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
                .buttonStyle(.plain)
                .disabled(isSending || isReplying)
            }
        }
    }

    private var appliedLabel: String {
        let count = proposal.items.count
        return count <= 1 ? "Ajouté ✓" : "\(count) aliments ajoutés ✓"
    }

    private func receipt(
        status: String,
        symbol: String,
        tone: Color,
        inProgress: Bool = false,
        struck: Bool = false
    ) -> some View {
        HStack(spacing: SharpitSpacing.sm) {
            Image(systemName: symbol)
                .foregroundStyle(tone)
            VStack(alignment: .leading, spacing: 2) {
                Text(status)
                    .font(SharpitTypography.meta.weight(.semibold))
                    .foregroundStyle(tone)
                    .strikethrough(struck)
                Text(proposal.meal.label)
                    .font(SharpitTypography.meta)
                    .foregroundStyle(SharpitColor.mutedForeground)
                    .strikethrough(struck)
            }
            Spacer(minLength: 0)
            if inProgress { ProgressView().controlSize(.small) }
        }
        .padding(SharpitSpacing.sm)
        .frame(maxWidth: .infinity, alignment: .leading)
        .sharpitSurface(.panel)
    }

    private func isPresetSelected(_ preset: FoodPortion.Preset, text: String) -> Bool {
        FoodLogForm.grams(text) == preset.grams
    }

    private func logTap() {
        #if DEBUG
        Self.log.debug(
            "foodLog tap ready=\(self.readyItems != nil) onAnswer=\(self.onAnswer != nil) isReplying=\(self.isReplying)"
        )
        #endif
    }

    private static func nutrients(for item: CoachFoodLogProposal.Item, grams: Double) -> FoodPortion.Nutrients {
        FoodPortion.Nutrients(
            kcal: round1(item.kcalPer100g * grams / 100),
            protein: round1(item.proteinPer100g * grams / 100),
            carbs: round1(item.carbsPer100g * grams / 100),
            fat: round1(item.fatPer100g * grams / 100)
        )
    }

    private static func round1(_ value: Double) -> Double {
        (value * 10).rounded() / 10
    }

    #if DEBUG
    private static let log = Logger(subsystem: "app.sharpit.ios", category: "coach")
    #endif
}

private extension String {
    nonisolated var nilIfEmpty: String? { isEmpty ? nil : self }
}
