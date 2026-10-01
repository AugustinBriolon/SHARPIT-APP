#if DEBUG
import SwiftUI

/// The coach on a scripted answer, to check how the thread moves in the simulator without an
/// account: a question rises to the top, the answer unrolls without moving the view, and the
/// arrow down appears once it runs past the screen. Debug builds only: `-SharpitCoachDemo`.
enum CoachDemo {
    static var isRequested: Bool {
        ProcessInfo.processInfo.arguments.contains("-SharpitCoachDemo")
    }
}

struct CoachDemoHost: View {
    @State private var router = ShellRouter()

    var body: some View {
        var view = CoachView(client: DemoCoachClient(), conversations: DemoConversations(), tokenProvider: { "demo" })
        view.demoQuestions = ["Comment était ma nuit ?", "Et pour jeudi, je fais quoi ?"]
        return view.environment(router)
    }
}

/// Writes a long answer word by word, at a reading pace.
private struct DemoCoachClient: CoachChatServing {
    private static let answer = """
    Ta nuit était courte, 6 h 10, et ta VFC est sous ta moyenne de la semaine. \
    Rien d'alarmant, mais c'est un signal à écouter avant une séance intense. \
    Voici ce que je te propose pour aujourd'hui. D'abord, garde la sortie vélo mais en endurance \
    fondamentale : 75 minutes en zone 2, sans chercher la puissance. Ensuite, décale le travail \
    au seuil à jeudi, quand ta fraîcheur sera remontée. Ton TSB est à moins 12 : tu as de la \
    marge, mais pas assez pour enchaîner deux jours durs. Pense à t'hydrater, surtout avec la \
    chaleur annoncée cet après-midi. Si tes jambes répondent bien après 30 minutes, tu peux \
    ajouter trois accélérations de 20 secondes, pas plus. Et ce soir, vise un coucher avant \
    23 h : une bonne nuit fera plus pour ta forme de jeudi que n'importe quelle séance. \
    Pour la suite de la semaine, on garde le plan : seuil jeudi, repos vendredi, sortie longue \
    samedi. Je reverrai tout ça demain matin avec ta nuit.
    """

    func reply(to request: CoachChatRequest, token: String) -> AsyncThrowingStream<JSONValue, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                continuation.yield(chunk(["type": "start", "messageId": "demo-\(UUID().uuidString)"]))
                continuation.yield(chunk(["type": "start-step"]))
                continuation.yield(chunk(["type": "text-start", "id": "t"]))
                for word in Self.answer.split(separator: " ") {
                    try? await Task.sleep(for: .milliseconds(70))
                    continuation.yield(chunk(["type": "text-delta", "id": "t", "delta": "\(word) "]))
                }
                continuation.yield(chunk(["type": "text-end", "id": "t"]))
                continuation.yield(chunk(["type": "finish-step"]))
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    private func chunk(_ fields: [String: String]) -> JSONValue {
        .object(fields.mapValues(JSONValue.string))
    }
}

private struct DemoConversations: CoachConversationServing {
    func conversations(token: String) async throws -> [CoachConversationSummary] { [] }
    func conversation(id: String, token: String) async throws -> CoachConversation {
        CoachConversation(id: id, messages: [])
    }
    func create(messages: [CoachMessage], token: String) async throws -> String { "demo" }
    func delete(id: String, token: String) async throws {}
}
#endif
