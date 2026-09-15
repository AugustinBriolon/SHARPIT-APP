nonisolated enum TodayScreenState: Equatable, Sendable {
    case loading
    case loaded(V1TodayResponse)
    case empty(V1TodayEmpty)
    case failed(String)
    case unauthorized
}

enum TodayModel {
    static func state(from response: V1TodayResponse) -> TodayScreenState {
        if let empty = response.empty {
            return .empty(empty)
        }
        return .loaded(response)
    }
}
