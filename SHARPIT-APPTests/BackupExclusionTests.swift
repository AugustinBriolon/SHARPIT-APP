import Foundation
import SwiftData
import Testing
@testable import Sharpit

/// Health-derived local files never reach an iCloud or Finder backup (`docs/adr/0017`).
struct BackupExclusionTests {
    private func temporaryDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    @Test func activityCacheDirectoryIsExcluded() throws {
        let directory = try temporaryDirectory().appending(path: "ActivityCache")
        let cache = ActivityDiskCache(directory: directory)
        cache.write(Data("{}".utf8), .detail, id: "a1")
        cache.write(Data("{\"v\":2}".utf8), .detail, id: "a1")

        #expect(BackupExclusion.isExcluded(directory))
    }

    @Test func wellnessDraftFileStaysExcludedAcrossAtomicRewrites() throws {
        let url = try temporaryDirectory().appending(path: "WellnessCheckInLocal.json")
        let store = WellnessCheckInLocalStore(fileURL: url)
        store.saveDraft(.init(feeling: 3), athleteId: "a", localDate: "2026-10-17")
        store.dismiss(athleteId: "a", localDate: "2026-10-16")

        #expect(BackupExclusion.isExcluded(url))
    }

    @Test func storeAndItsJournalFilesAreExcluded() throws {
        let store = try temporaryDirectory().appending(path: "default.store")
        let files = ["", "-wal", "-shm"].map { URL(filePath: store.path(percentEncoded: false) + $0) }
        for file in files { try Data().write(to: file) }

        BackupExclusion.excludeStore(at: store)

        for file in files { #expect(BackupExclusion.isExcluded(file)) }
    }

    /// The real on-disk store, where `makeContainer()` puts it (the App Group container).
    @Test func theAppsSwiftDataStoreIsExcluded() throws {
        _ = try SharpitPersistence.makeContainer()
        let url = SharpitPersistence.configuration(inMemory: false).url
        #expect(FileManager.default.fileExists(atPath: url.path(percentEncoded: false)))
        #expect(BackupExclusion.isExcluded(url))
    }
}
