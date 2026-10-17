import Foundation

/// Keeps the app's local health-derived files out of iCloud and Finder backups.
///
/// Every file it is used on is a cache of what `/api` already holds, or a throwaway draft, so a
/// restored iPhone loses nothing it cannot fetch again (`docs/adr/0017`).
nonisolated enum BackupExclusion {
    /// Missing files are skipped. An atomic write replaces the file and drops the flag, so a
    /// file (unlike a directory) has to be excluded again after each write.
    static func exclude(_ url: URL) {
        var url = url
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try? url.setResourceValues(values)
    }

    /// The SQLite store and its journal companions, which SQLite creates beside it.
    static func excludeStore(at url: URL) {
        for suffix in ["", "-wal", "-shm"] {
            exclude(URL(filePath: url.path(percentEncoded: false) + suffix))
        }
    }

    static func isExcluded(_ url: URL) -> Bool {
        (try? url.resourceValues(forKeys: [.isExcludedFromBackupKey]).isExcludedFromBackup) == true
    }
}
