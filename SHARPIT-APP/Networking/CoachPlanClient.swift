import Foundation

protocol CoachPlanServing: Sendable {
    /// Streams the week as the coach writes it: `onDraft` receives the sessions written so far,
    /// each time the list grows or a session fills in. The model's reasoning is not sent
    /// (the server hides it), so the drafts are the only sign of progress.
    func generateWeek(
        days: Int,
        goalId: String?,
        focus: String?,
        startDate: Date?,
        token: String,
        onDraft: @escaping @Sendable ([V1GeneratedSession]) -> Void
    ) async throws -> V1GeneratedPlan


    /// Puts generated sessions in the plan through the web generator's own mapping
    /// (`/api/v1/coach/plan/insert`): the coach's prescriptions travel as the coach wrote them.
    /// All or nothing — a refused week leaves the plan untouched.
    func insertWeek(_ sessions: [V1GeneratedSession], goalId: String?, token: String) async throws
}

/// « Ajuster le planning »: the coach reads what was done and proposes changes to the sessions
/// ahead; the ones kept are applied through the web adapter's own mapping.
protocol PlanAdjustmentServing: Sendable {
    func adaptPlan(
        days: Int,
        focus: String?,
        token: String,
        onReasoning: @escaping @Sendable (String) -> Void
    ) async throws -> V1AdaptPlanResult

    /// All the changes checked before the first is written (`/api/v1/coach/adapt/apply`).
    func applyAdjustments(_ changes: [V1AdaptChange], token: String) async throws
}

/// A week generated on the server in the background (`/api/v1/coach/plan/jobs`): the drafts
/// while the coach writes, then the week — or why it failed.
nonisolated struct V1PlanJob: Decodable, Sendable {
    let id: String
    /// `running`, `ready` or `failed`.
    let status: String
    var drafts: [V1GeneratedSession] = []
    var plan: V1GeneratedPlan?
    var error: String?

    enum CodingKeys: String, CodingKey { case id, status, drafts, plan, error }

    init(id: String, status: String, drafts: [V1GeneratedSession] = [], plan: V1GeneratedPlan? = nil, error: String? = nil) {
        self.id = id
        self.status = status
        self.drafts = drafts
        self.plan = plan
        self.error = error
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        status = try container.decode(String.self, forKey: .status)
        drafts = ((try? container.decode([V1GeneratedSession].self, forKey: .drafts)) ?? []).filter(\.isDrafted)
        plan = try? container.decodeIfPresent(V1GeneratedPlan.self, forKey: .plan)
        error = try? container.decodeIfPresent(String.self, forKey: .error)
    }
}

/// Plan's generator: the week runs on the server, so leaving the app loses nothing and a push
/// says when it is ready.
nonisolated protocol PlanJobServing: Sendable {
    func startWeekJob(days: Int, goalId: String?, focus: String?, startDate: Date?, token: String) async throws -> V1PlanJob
    func planJob(id: String, token: String) async throws -> V1PlanJob?
    /// The latest generation, to pick up after the app was closed.
    func latestPlanJob(token: String) async throws -> V1PlanJob?
}

actor CoachPlanClient: CoachPlanServing, PlanJobServing, PlanAdjustmentServing {
    private let session: URLSession
    private let baseURL: URL

    init(session: URLSession = .shared, baseURL: URL = APIConfiguration.baseURL) {
        self.session = session
        self.baseURL = baseURL
    }

    func generateWeek(
        days: Int,
        goalId: String?,
        focus: String?,
        startDate: Date? = nil,
        token: String,
        onDraft: @escaping @Sendable ([V1GeneratedSession]) -> Void
    ) async throws -> V1GeneratedPlan {
        var payload: [String: Any] = [
            "days": days
        ]
        if let goalId, !goalId.isEmpty, goalId != "none" {
            payload["goalId"] = goalId
        }
        if let focus, !focus.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            payload["focus"] = focus.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        if let startDate {
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyy-MM-dd"
            payload["startDate"] = formatter.string(from: startDate)
        }

        return try await streamCoach(
            path: "/api/v1/coach/plan",
            payload: payload,
            token: token,
            onReasoning: { _ in },
            onPartial: { data in
                guard let draft = try? JSONDecoder().decode(V1GeneratedPlan.self, from: data) else { return }
                onDraft(draft.sessions.filter(\.isDrafted))
            }
        )
    }

    private nonisolated struct JobEnvelope: Decodable { let job: V1PlanJob? }

    func startWeekJob(days: Int, goalId: String?, focus: String?, startDate: Date?, token: String) async throws -> V1PlanJob {
        var payload: [String: Any] = ["days": days]
        if let goalId, !goalId.isEmpty { payload["goalId"] = goalId }
        if let focus, !focus.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            payload["focus"] = focus.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        if let startDate { payload["startDate"] = TrainingDayId.today(now: startDate) }
        var request = URLRequest(url: baseURL.appending(path: "/api/v1/coach/plan/jobs"))
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: payload)
        guard let job = try await sendJob(request) else { throw SharpitAPIError.server }
        return job
    }

    func planJob(id: String, token: String) async throws -> V1PlanJob? {
        var request = URLRequest(url: baseURL.appending(path: "/api/v1/coach/plan/jobs/\(id)"))
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        return try await sendJob(request)
    }

    func latestPlanJob(token: String) async throws -> V1PlanJob? {
        var request = URLRequest(url: baseURL.appending(path: "/api/v1/coach/plan/jobs"))
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        return try await sendJob(request)
    }

    private func sendJob(_ request: URLRequest) async throws -> V1PlanJob? {
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw SharpitAPIError.transport
        }
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        switch status {
        case 200..<300: return try JSONDecoder().decode(JobEnvelope.self, from: data).job
        case 401: throw SharpitAPIError.unauthorized
        case 404: return nil
        case 402: throw CoachPlanError.custom("Tu as atteint ton quota de coach pour le moment. Réessaie plus tard, ou passe à SharpIt Pro.")
        case 429: throw SharpitAPIError.rateLimited
        default:
            let message = (try? JSONSerialization.jsonObject(with: data) as? [String: Any])?["error"] as? String
            throw message.map(CoachPlanError.custom) ?? SharpitAPIError.server
        }
    }

    func insertWeek(_ sessions: [V1GeneratedSession], goalId: String?, token: String) async throws {
        var request = URLRequest(url: baseURL.appending(path: "/api/v1/coach/plan/insert"))
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let goal: JSONValue = goalId.map(JSONValue.string) ?? .null
        request.httpBody = try JSONEncoder().encode(JSONValue.object([
            "goalId": goal,
            "sessions": .array(sessions.map(\.insertBody)),
        ]))

        let (_, response) = try await session.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        if status == 401 { throw SharpitAPIError.unauthorized }
        if status == 422 {
            throw CoachPlanError.custom("Une séance a été écartée par le contrôle de sécurité. Décoche-la puis réessaie.")
        }
        guard (200...299).contains(status) else { throw SharpitAPIError.server }
    }

    func applyAdjustments(_ changes: [V1AdaptChange], token: String) async throws {
        var request = URLRequest(url: baseURL.appending(path: "/api/v1/coach/adapt/apply"))
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.httpBody = try JSONEncoder().encode(JSONValue.object(["changes": .array(changes.map(\.applyBody))]))

        let (_, response) = try await session.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        if status == 401 { throw SharpitAPIError.unauthorized }
        if status == 409 {
            throw CoachPlanError.custom("Une séance à ajuster a changé entre-temps. Relance l'ajustement.")
        }
        guard (200...299).contains(status) else { throw SharpitAPIError.server }
    }

    func adaptPlan(
        days: Int,
        focus: String?,
        token: String,
        onReasoning: @escaping @Sendable (String) -> Void
    ) async throws -> V1AdaptPlanResult {
        var payload: [String: Any] = [
            "days": days
        ]
        if let focus, !focus.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            payload["focus"] = focus.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        return try await streamCoach(
            path: "/api/v1/coach/adapt",
            payload: payload,
            token: token,
            onReasoning: onReasoning
        )
    }

    private func streamCoach<T: Decodable>(
        path: String,
        payload: [String: Any],
        token: String,
        onReasoning: @escaping @Sendable (String) -> Void,
        onPartial: (@Sendable (Data) -> Void)? = nil
    ) async throws -> T {
        var request = URLRequest(url: baseURL.appending(path: path))
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("text/event-stream, application/json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 300 // Generation can take 30-60s
        request.httpBody = try JSONSerialization.data(withJSONObject: payload)

        let (bytes, response) = try await session.bytes(for: request)
        if let http = response as? HTTPURLResponse {
            if http.statusCode == 401 { throw SharpitAPIError.unauthorized }
            guard (200..<300).contains(http.statusCode) else {
                throw SharpitAPIError.server
            }
        }

        var reasoning = ""
        var finalResult: T?

        for try await line in bytes.lines {
            guard line.hasPrefix("data:") else { continue }
            let jsonString = line.dropFirst(5).trimmingCharacters(in: .whitespaces)
            guard !jsonString.isEmpty, jsonString != "[DONE]",
                  let jsonData = jsonString.data(using: .utf8),
                  let event = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any]
            else { continue }

            if let type = event["type"] as? String {
                switch type {
                case "reasoning":
                    if let delta = event["delta"] as? String {
                        reasoning += delta
                        onReasoning(reasoning)
                    }
                case "partial":
                    if let onPartial, let value = event["value"],
                       let data = try? JSONSerialization.data(withJSONObject: value) {
                        onPartial(data)
                    }
                case "result":
                    if let value = event["value"] {
                        let valueData = try JSONSerialization.data(withJSONObject: value)
                        finalResult = try JSONDecoder().decode(T.self, from: valueData)
                    }
                case "error":
                    let message = event["message"] as? String ?? "La génération a échoué."
                    throw CoachPlanError.custom(message)
                default:
                    break
                }
            }
        }

        if let finalResult {
            return finalResult
        }
        throw CoachPlanError.custom("Aucun résultat renvoyé par le coach.")
    }
}

enum CoachPlanError: Error, LocalizedError {
    case custom(String)

    var errorDescription: String? {
        switch self {
        case .custom(let message): message
        }
    }
}
