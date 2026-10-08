import Foundation

nonisolated struct V1CalendarBusyInterval: Encodable, Sendable, Equatable {
    let start: String
    let end: String
}

nonisolated struct V1AppleCalendarBusyUpload: Encodable, Sendable {
    let provider = "apple-calendar"
    let intervals: [V1CalendarBusyInterval]
}

nonisolated struct V1AppleCalendarBusyResult: Decodable, Sendable {
    let ok: Bool
    let count: Int?
}

nonisolated protocol AppleCalendarBusyServing: Sendable {
    func uploadAppleCalendarBusy(_ intervals: [V1CalendarBusyInterval], token: String) async throws
}

nonisolated protocol AppleCalendarLinking: Sendable {
    func linkAppleCalendar(_ linked: Bool, token: String) async throws
}
