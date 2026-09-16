import Foundation
import SwiftData

@Model
final class TodayDaySnapshot {
    #Unique<TodayDaySnapshot>([\.trainingDayId])

    var trainingDayId: String
    var fetchedAt: Date
    @Attribute(.externalStorage) var payloadJSON: Data

    init(trainingDayId: String, fetchedAt: Date = .now, payloadJSON: Data) {
        self.trainingDayId = trainingDayId
        self.fetchedAt = fetchedAt
        self.payloadJSON = payloadJSON
    }
}

enum SharpitPersistence {
    static func makeContainer(inMemory: Bool = false) throws -> ModelContainer {
        let schema = Schema([TodayDaySnapshot.self])
        let configuration = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: inMemory
        )
        return try ModelContainer(for: schema, configurations: [configuration])
    }
}

enum TodaySnapshotRepository {
    static func load(trainingDayId: String, context: ModelContext) throws -> V1TodayResponse? {
        let dayId = trainingDayId
        var descriptor = FetchDescriptor<TodayDaySnapshot>(
            predicate: #Predicate { $0.trainingDayId == dayId }
        )
        descriptor.fetchLimit = 1
        guard let snapshot = try context.fetch(descriptor).first else {
            return nil
        }
        return try JSONDecoder().decode(V1TodayResponse.self, from: snapshot.payloadJSON)
    }

    static func save(_ response: V1TodayResponse, context: ModelContext) throws {
        let data = try JSONEncoder().encode(response)
        let dayId = response.trainingDayId
        var descriptor = FetchDescriptor<TodayDaySnapshot>(
            predicate: #Predicate { $0.trainingDayId == dayId }
        )
        descriptor.fetchLimit = 1
        if let existing = try context.fetch(descriptor).first {
            existing.payloadJSON = data
            existing.fetchedAt = .now
        } else {
            context.insert(
                TodayDaySnapshot(trainingDayId: dayId, payloadJSON: data)
            )
        }
        try context.save()
    }
}
