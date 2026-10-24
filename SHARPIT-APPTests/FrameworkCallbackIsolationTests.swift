import Foundation
import Testing

/// The project's rule, enforced (root `CLAUDE.md`, « Framework callbacks »): a callback a system
/// framework calls on its own queue is built in a nonisolated function. Under main-actor default
/// isolation a closure or delegate method built elsewhere traps in `_dispatch_assert_queue_fail`
/// when the framework calls it — the launch crash APPLE-IOS-4 was one.
private let callbackSites: [String] = [
    #"HK[A-Za-z]*Query\("#,
    #"\.recognitionTask\(with"#,
    #"\.installTap\(onBus"#,
    #"SFSpeechRecognizer\.requestAuthorization"#,
]

/// Delegate methods UserNotifications calls off the main thread.
private let offMainDelegateMethods = #"func userNotificationCenter\("#

private func appSources() throws -> [(path: String, lines: [String])] {
    let root = URL(filePath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
    let folders = ["SHARPIT-APP", "SharpItShared", "SharpItWidgets"].map { root.appending(path: $0) }
    return try folders.flatMap { folder -> [(String, [String])] in
        let files = FileManager.default.enumerator(at: folder, includingPropertiesForKeys: nil)?
            .compactMap { $0 as? URL }
            .filter { $0.pathExtension == "swift" } ?? []
        return try files.map { url in
            (url.lastPathComponent, try String(contentsOf: url, encoding: .utf8).components(separatedBy: "\n"))
        }
    }
}

private func matches(_ line: String, _ pattern: String) -> Bool {
    line.range(of: pattern, options: .regularExpression) != nil
}

@Test func frameworkCallbacksAreBuiltOutsideTheMainActor() throws {
    var offenders: [String] = []
    for (path, lines) in try appSources() {
        for (index, line) in lines.enumerated() where !line.trimmingCharacters(in: .whitespaces).hasPrefix("//") {
            if callbackSites.contains(where: { matches(line, $0) }) {
                // The function the callback is built in: the nearest declaration above it.
                let enclosing = lines[..<index].last { matches($0, #"\bfunc [A-Za-z_]"#) } ?? ""
                if !enclosing.contains("nonisolated") { offenders.append("\(path):\(index + 1)") }
            }
            if matches(line, offMainDelegateMethods), !line.contains("nonisolated") {
                offenders.append("\(path):\(index + 1)")
            }
        }
    }
    #expect(offenders.isEmpty, "Build these callbacks in a nonisolated function: \(offenders)")
}
