import Foundation
import SwiftData
import Testing
@testable import Sharpit

@MainActor
private func fixture() throws -> (ModelContext, UserDefaults, ActivityDiskCache) {
    let container = try SharpitPersistence.makeContainer(inMemory: true)
    let defaults = try #require(UserDefaults(suiteName: "LocalAccountData-\(UUID().uuidString)"))
    let disk = ActivityDiskCache(directory: FileManager.default.temporaryDirectory.appending(path: UUID().uuidString))
    return (ModelContext(container), defaults, disk)
}

@MainActor
private func cachedRows(_ context: ModelContext) throws -> Int {
    try context.fetchCount(FetchDescriptor<CachedResponse>())
}

/// Another account signing in on the same iPhone never sees the previous one's data.
@MainActor
@Test func anotherAccountWipesWhatThePreviousOneLeft() throws {
    let (context, defaults, disk) = try fixture()
    LocalAccountData.claim(userId: "user_main", context: context, defaults: defaults, disk: disk)
    context.insert(CachedResponse(key: "plan-week:2026-09-28", payloadJSON: Data("{}".utf8)))
    disk.write(Data("{}".utf8), .detail, id: "a1")

    LocalAccountData.claim(userId: "user_main", context: context, defaults: defaults, disk: disk)
    #expect(try cachedRows(context) == 1)

    LocalAccountData.claim(userId: "user_test", context: context, defaults: defaults, disk: disk)
    #expect(try cachedRows(context) == 0)
    #expect(disk.read(.detail, id: "a1") == nil)
    #expect(defaults.string(forKey: LocalAccountData.ownerKey) == "user_test")
}

/// The first account seen after the update keeps the cache it already had.
@MainActor
@Test func theFirstAccountSeenKeepsItsCache() throws {
    let (context, defaults, disk) = try fixture()
    context.insert(CachedResponse(key: "plan-week:2026-09-28", payloadJSON: nil))

    LocalAccountData.claim(userId: "user_main", context: context, defaults: defaults, disk: disk)

    #expect(try cachedRows(context) == 1)
}
