import Foundation

/// `/api/v1/integrations/source-prefs` — which sources feed each data class, and which one is
/// the primary (SHARPIT ADR-027, ADR-054). The web decides what a primary means; the app only
/// shows and changes the choice.
nonisolated struct V1SourcePrefs: Decodable, Equatable, Sendable {
    /// Per class: the enabled providers, and the primary among them.
    var classes: [String: V1ClassSources]

    func sources(for classId: String) -> V1ClassSources {
        classes[classId] ?? V1ClassSources(primary: nil, enabled: [])
    }
}

nonisolated struct V1ClassSources: Decodable, Equatable, Sendable {
    var primary: String?
    var enabled: [String]
}

/// A data class and the providers that can feed it, as the web lists them.
nonisolated struct V1SourceClass: Decodable, Equatable, Identifiable, Sendable {
    nonisolated struct Provider: Decodable, Equatable, Identifiable, Sendable {
        let id: String
        let name: String
    }

    let id: String
    let label: String
    let description: String
    let providers: [Provider]
}

nonisolated struct V1SourcePrefsResponse: Decodable, Equatable, Sendable {
    let prefs: V1SourcePrefs
    let connected: [String]
    let classes: [V1SourceClass]
}

nonisolated enum SourcePrefsAction: String, Encodable, Sendable {
    case enable
    case disable
    case setPrimary
}

nonisolated protocol SourcePrefsServing: Sendable {
    func sourcePrefs(token: String) async throws -> V1SourcePrefsResponse
    /// Returns the prefs as the web saved them.
    func updateSourcePrefs(_ action: SourcePrefsAction, dataClass: String, provider: String, token: String) async throws -> V1SourcePrefs
}

/// Apple Health has no account on the web: the app says when its switch is on (ADR-054).
nonisolated protocol AppleHealthLinking: Sendable {
    func linkAppleHealth(_ linked: Bool, token: String) async throws
}
