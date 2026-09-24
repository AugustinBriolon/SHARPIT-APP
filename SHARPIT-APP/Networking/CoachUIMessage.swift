import Foundation

/// Builds a coach turn's UI-message parts from the chat route's stream, the way the AI SDK's
/// `processUIMessageStream` does on the web.
///
/// The parts are kept as JSON, not as a Swift model: they go back to the server whole — on the
/// next question, on an approval, and in the saved thread — and `convertToModelMessages` reads
/// fields the app has no use for (provider metadata carrying the model's thought signatures, a
/// tool approval's `signature`). Anything dropped here would break the next turn server-side.
nonisolated struct CoachUIMessageAssembler {
    private(set) var parts: [JSONValue]
    private var activeText: [String: Int] = [:]
    private var activeReasoning: [String: Int] = [:]

    /// Starts from a turn's existing parts: a continuation after an approval extends the same
    /// assistant message, as `useChat` does.
    init(parts: [JSONValue] = []) {
        self.parts = parts
    }

    var text: String { CoachUIParts.text(in: parts) }

    mutating func apply(_ chunk: JSONValue) {
        guard case .object(let chunk) = chunk, let type = chunk["type"]?.string else { return }
        let id = chunk["id"]?.string ?? ""

        switch type {
        case "start-step":
            parts.append(.object(["type": .string("step-start")]))
        case "finish-step":
            activeText = [:]
            activeReasoning = [:]

        case "text-start", "reasoning-start":
            let kind = type == "text-start" ? "text" : "reasoning"
            var part: [String: JSONValue] = ["type": .string(kind), "text": .string(""), "state": .string("streaming")]
            part["providerMetadata"] = chunk["providerMetadata"]
            parts.append(.object(part))
            if kind == "text" { activeText[id] = parts.count - 1 } else { activeReasoning[id] = parts.count - 1 }
        case "text-delta", "reasoning-delta":
            guard let index = type == "text-delta" ? activeText[id] : activeReasoning[id] else { return }
            mutate(index) { part in
                part["text"] = .string((part["text"]?.string ?? "") + (chunk["delta"]?.string ?? ""))
                if let metadata = chunk["providerMetadata"] { part["providerMetadata"] = metadata }
            }
        case "text-end", "reasoning-end":
            let isText = type == "text-end"
            guard let index = isText ? activeText[id] : activeReasoning[id] else { return }
            mutate(index) { part in
                part["state"] = .string("done")
                if let metadata = chunk["providerMetadata"] { part["providerMetadata"] = metadata }
            }
            if isText { activeText[id] = nil } else { activeReasoning[id] = nil }

        case "tool-input-start":
            updateTool(chunk, state: "input-streaming", input: nil)
        case "tool-input-delta":
            // The input arrives whole with `tool-input-available`; a card is never drawn from
            // half a JSON object.
            break
        case "tool-input-available":
            updateTool(chunk, state: "input-available", input: chunk["input"])
        case "tool-input-error":
            updateTool(chunk, state: "output-error", input: nil, rawInput: chunk["input"], errorText: chunk["errorText"])
        case "tool-approval-request":
            guard let index = toolIndex(callId: chunk["toolCallId"]?.string) else { return }
            mutate(index) { part in
                part["state"] = .string("approval-requested")
                var approval: [String: JSONValue] = ["id": chunk["approvalId"] ?? .null]
                if chunk["isAutomatic"] == .bool(true) { approval["isAutomatic"] = .bool(true) }
                if let signature = chunk["signature"], signature != .null { approval["signature"] = signature }
                part["approval"] = .object(approval)
            }
        case "tool-approval-response":
            guard let approvalId = chunk["approvalId"]?.string,
                  let index = parts.firstIndex(where: { $0["approval"]?["id"]?.string == approvalId })
            else { return }
            mutate(index) { part in
                let previous = part["approval"]
                part["state"] = .string("approval-responded")
                var approval: [String: JSONValue] = ["id": .string(approvalId), "approved": chunk["approved"] ?? .bool(false)]
                if let reason = chunk["reason"], reason != .null { approval["reason"] = reason }
                if previous?["isAutomatic"] == .bool(true) { approval["isAutomatic"] = .bool(true) }
                if let signature = previous?["signature"] { approval["signature"] = signature }
                part["approval"] = .object(approval)
                if let executed = chunk["providerExecuted"] { part["providerExecuted"] = executed }
                if let metadata = chunk["providerMetadata"] { part["callProviderMetadata"] = metadata }
            }
        case "tool-output-denied":
            guard let index = toolIndex(callId: chunk["toolCallId"]?.string) else { return }
            mutate(index) { $0["state"] = .string("output-denied") }
        case "tool-output-available", "tool-output-error":
            guard let index = toolIndex(callId: chunk["toolCallId"]?.string),
                  case .object(let existing) = parts[index]
            else { return }
            var update = chunk
            update["toolName"] = .string(String((existing["type"]?.string ?? "tool-").dropFirst("tool-".count)))
            update["title"] = existing["title"]
            update["toolMetadata"] = existing["toolMetadata"]
            if type == "tool-output-available" {
                updateTool(update, state: "output-available", input: existing["input"], output: chunk["output"], preliminary: chunk["preliminary"])
            } else {
                updateTool(update, state: "output-error", input: existing["input"], rawInput: existing["rawInput"], errorText: chunk["errorText"])
            }

        case "file", "reasoning-file", "source-url", "source-document", "custom":
            parts.append(.object(chunk))
        default:
            guard type.hasPrefix("data-"), chunk["transient"] != .bool(true) else { return }
            if let dataId = chunk["id"]?.string,
               let index = parts.firstIndex(where: { $0["type"]?.string == type && $0["id"]?.string == dataId }) {
                mutate(index) { $0["data"] = chunk["data"] }
            } else {
                parts.append(.object(chunk))
            }
        }
    }

    private func toolIndex(callId: String?) -> Int? {
        guard let callId else { return nil }
        return parts.firstIndex { ($0["type"]?.string?.hasPrefix("tool-") ?? false) && $0["toolCallId"]?.string == callId }
    }

    private mutating func mutate(_ index: Int, _ body: (inout [String: JSONValue]) -> Void) {
        guard case .object(var part) = parts[index] else { return }
        body(&part)
        parts[index] = .object(part)
    }

    /// `updateToolPart`: fields the SDK passes as `undefined` are removed, as JSON drops them.
    private mutating func updateTool(
        _ chunk: [String: JSONValue],
        state: String,
        input: JSONValue?,
        output: JSONValue? = nil,
        rawInput: JSONValue? = nil,
        errorText: JSONValue? = nil,
        preliminary: JSONValue? = nil
    ) {
        guard let callId = chunk["toolCallId"]?.string, let name = chunk["toolName"]?.string else { return }
        let isResult = state == "output-available" || state == "output-error"
        let metadataKey = isResult ? "resultProviderMetadata" : "callProviderMetadata"

        if let index = toolIndex(callId: callId) {
            mutate(index) { part in
                part["state"] = .string(state)
                part["input"] = input
                part["output"] = output
                part["errorText"] = errorText
                part["rawInput"] = rawInput
                part["preliminary"] = preliminary
                if let title = chunk["title"] { part["title"] = title }
                if let metadata = chunk["toolMetadata"] { part["toolMetadata"] = metadata }
                if let executed = chunk["providerExecuted"] { part["providerExecuted"] = executed }
                if let metadata = chunk["providerMetadata"] { part[metadataKey] = metadata }
            }
        } else {
            var part: [String: JSONValue] = [
                "type": .string("tool-\(name)"),
                "toolCallId": .string(callId),
                "state": .string(state),
            ]
            part["title"] = chunk["title"]
            part["toolMetadata"] = chunk["toolMetadata"]
            part["input"] = input
            part["output"] = output
            part["rawInput"] = rawInput
            part["errorText"] = errorText
            part["providerExecuted"] = chunk["providerExecuted"]
            part["preliminary"] = preliminary
            part[metadataKey] = chunk["providerMetadata"]
            parts.append(.object(part))
        }
    }
}

/// Reading and answering a turn's parts: the web's `coach-tool-parts.ts` and the SDK's
/// `lastAssistantMessageIsCompleteWithApprovalResponses`.
nonisolated enum CoachUIParts {
    /// The tools that change the athlete's calendar or context, and so wait for their approval.
    static let calendarToolTypes: Set<String> = [
        "tool-createPlannedSession",
        "tool-createBrickSession",
        "tool-updatePlannedSession",
        "tool-deletePlannedSession",
        "tool-setTravelContext",
        "tool-setTrainingConstraint",
    ]

    /// The reasons the web attaches to an answer (`coach-approval-reason.ts`) — the model reads them.
    static let approvedReason = "Validé par l’athlète"
    static let deniedReason = "Refusé par l’athlète — ne pas appliquer cette action ; proposer une alternative ou demander une précision"
    static let dismissedReason = "Proposition ignorée — nouvelle demande envoyée"

    static func isTerminal(_ state: String?) -> Bool {
        state == "output-available" || state == "output-error" || state == "output-denied"
    }

    static func text(in parts: [JSONValue]) -> String {
        parts
            .filter { $0["type"]?.string == "text" }
            .compactMap { $0["text"]?.string }
            .filter { !$0.isEmpty }
            .joined(separator: "\n\n")
    }

    /// Whether a turn has anything to show: words, or a proposal.
    static func hasContent(_ parts: [JSONValue]) -> Bool {
        !text(in: parts).isEmpty || parts.contains { calendarToolTypes.contains($0["type"]?.string ?? "") }
    }

    /// Records the athlete's answer on the part awaiting it.
    static func responding(
        _ parts: [JSONValue],
        approvalId: String,
        approved: Bool
    ) -> [JSONValue] {
        parts.map { part in
            guard case .object(var object) = part,
                  object["state"]?.string == "approval-requested",
                  case .object(var approval) = object["approval"],
                  approval["id"]?.string == approvalId
            else { return part }
            object["state"] = .string("approval-responded")
            approval["approved"] = .bool(approved)
            approval["reason"] = .string(approved ? approvedReason : deniedReason)
            object["approval"] = .object(approval)
            return .object(object)
        }
    }

    /// A new question refuses the proposals left open, as on the web: a tool call without a
    /// result would otherwise reach the model, which rejects the whole history.
    static func dismissingUnresolved(_ parts: [JSONValue]) -> [JSONValue] {
        parts.map { part in
            guard case .object(var object) = part,
                  let type = object["type"]?.string, calendarToolTypes.contains(type),
                  !isTerminal(object["state"]?.string)
            else { return part }
            var approval: [String: JSONValue] = ["id": object["approval"]?["id"] ?? .string("dismissed-\(type)")]
            if let signature = object["approval"]?["signature"] { approval["signature"] = signature }
            approval["approved"] = .bool(false)
            approval["reason"] = .string(dismissedReason)
            object["state"] = .string("output-denied")
            object["approval"] = .object(approval)
            return .object(object)
        }
    }

    private static func lastStepTools(_ parts: [JSONValue]) -> [JSONValue] {
        let lastStep = parts.lastIndex { $0["type"]?.string == "step-start" } ?? -1
        return parts[(lastStep + 1)...].filter {
            let type = $0["type"]?.string ?? ""
            return type.hasPrefix("tool-") || type == "dynamic-tool"
        }
    }

    /// Every proposal of the last step answered, at least one of them just now: the turn can
    /// go back to the server to be carried out.
    static func isCompleteWithApprovalResponses(_ parts: [JSONValue]) -> Bool {
        let tools = lastStepTools(parts)
        let states = tools.map { $0["state"]?.string ?? "" }
        return states.contains("approval-responded")
            && states.allSatisfy { ["output-available", "output-error", "approval-responded"].contains($0) }
    }

    /// Which answers a continuation carries, so the same ones are never sent twice.
    static func approvalFingerprint(_ parts: [JSONValue]) -> String? {
        let ids = lastStepTools(parts)
            .filter { $0["state"]?.string == "approval-responded" }
            .map { $0["approval"]?["id"]?.string ?? $0["toolCallId"]?.string ?? "" }
            .sorted()
        return ids.isEmpty ? nil : ids.joined(separator: "|")
    }

    /// How many calendar changes the server carried out in this turn.
    static func appliedChanges(_ parts: [JSONValue]) -> Int {
        parts.filter { part in
            calendarToolTypes.contains(part["type"]?.string ?? "")
                && part["state"]?.string == "output-available"
                && part["output"]?["ok"] != .bool(false)
        }.count
    }
}
