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
        if case .object(let object) = input {
            baseInput = object
        } else {
            baseInput = [:]
        }

        let state = part["state"]?.string ?? ""
        let approval = part["approval"]
        switch state {
        case "approval-requested" where approval?["isAutomatic"] != .bool(true):
            status = .awaiting(approvalId: approval?["id"]?.string ?? "")
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

    private static func formattedDate(_ raw: String) -> String {
        let parts = raw.split(separator: "-")
        guard parts.count == 3, let month = Int(parts[1]), let day = Int(parts[2]) else { return raw }
        return "\(day)/\(month)"
    }
}

/// Editable food-log proposal: meal picker + grams, then Valider / Refuser.
struct CoachFoodLogCard: View {
    let proposal: CoachFoodLogProposal
    /// Nil while an answer is on its way. Passes optional patched tool input on approve.
    let onAnswer: ((Bool, JSONValue?) -> Void)?

    @State private var meal: FoodLogMeal
    @State private var lines: [EditableLine]

    init(proposal: CoachFoodLogProposal, onAnswer: ((Bool, JSONValue?) -> Void)?) {
        self.proposal = proposal
        self.onAnswer = onAnswer
        _meal = State(initialValue: proposal.meal)
        _lines = State(initialValue: proposal.items.map {
            EditableLine(id: $0.id, name: $0.name, gramsText: String(Int($0.grams.rounded())), source: $0)
        })
    }

    private struct EditableLine: Identifiable, Equatable {
        let id: String
        let name: String
        var gramsText: String
        let source: CoachFoodLogProposal.Item
    }

    var body: some View {
        Group {
            switch proposal.status {
            case .awaiting:
                card
            case .drafting:
                receipt(status: "Ajouter au journal…", symbol: "fork.knife", tone: SharpitColor.mutedForeground, inProgress: true)
            case .accepted:
                receipt(status: "Validé, en cours d'application", symbol: "checkmark", tone: SharpitColor.primary, inProgress: true)
            case .applied:
                receipt(status: appliedLabel, symbol: "checkmark.circle.fill", tone: SharpitColor.signalRecovery)
            case .refused:
                receipt(status: "Refusé", symbol: "xmark.circle", tone: SharpitColor.mutedForeground, struck: true)
            case .failed(let hint):
                receipt(status: hint, symbol: "exclamationmark.triangle.fill", tone: SharpitColor.signalRisk)
            }
        }
        .animation(SharpitMotion.reveal, value: proposal.status)
    }

    private var appliedLabel: String {
        let count = proposal.items.count
        return count <= 1 ? "Aliment ajouté" : "\(count) aliments ajoutés"
    }

    private var readyItems: [CoachFoodLogProposal.Item]? {
        var items: [CoachFoodLogProposal.Item] = []
        for line in lines {
            guard let grams = FoodLogForm.grams(line.gramsText), grams > 0 else { return nil }
            var item = line.source
            item.grams = grams
            items.append(item)
        }
        return items.isEmpty ? nil : items
    }

    private var card: some View {
        VStack(alignment: .leading, spacing: SharpitSpacing.md) {
            SharpitCardHeader(
                title: "Ajouter au journal",
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
                    VStack(alignment: .leading, spacing: SharpitSpacing.xs) {
                        Text(line.name)
                            .font(SharpitTypography.body.weight(.semibold))
                        FoodNumberRow(title: "Portion", unit: "g", text: $line.gramsText)
                    }
                }
            }

            HStack(spacing: SharpitSpacing.sm) {
                answerButton("Refuser", prominent: false) {
                    onAnswer?(false, nil)
                }
                answerButton(addTitle, prominent: true) {
                    guard let items = readyItems else { return }
                    onAnswer?(true, proposal.patchedInput(meal: meal, items: items))
                }
                .disabled(readyItems == nil)
            }
            .disabled(onAnswer == nil)
            .opacity(onAnswer == nil ? 0.5 : 1)
        }
        .padding(SharpitSpacing.cardPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .sharpitSurface(.panel)
        .sharpitCardSpecularBorder()
    }

    private var addTitle: String {
        let count = lines.count
        return count <= 1 ? "Ajouter" : "Ajouter les \(count)"
    }

    private func answerButton(_ title: String, prominent: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(SharpitTypography.body.weight(.semibold))
                .frame(maxWidth: .infinity)
                .padding(.vertical, SharpitSpacing.sm)
        }
        .buttonStyle(.plain)
        .foregroundStyle(prominent ? Color.white : SharpitColor.foreground)
        .background(prominent ? SharpitColor.primary : SharpitColor.analysisSurfaceAlt, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
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
}

private extension String {
    nonisolated var nilIfEmpty: String? { isEmpty ? nil : self }
}
