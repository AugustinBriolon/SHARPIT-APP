import Foundation
import SentrySwift
import Testing
@testable import Sharpit

/// A crash report must never carry what the athlete measured or wrote.
/// Replay buffers only on error; text, images, and request bodies stay masked.
@Test func crashReportsCarryNoPersonalDataOrTracing() {
    let options = Options()
    CrashReporting.configure(options, environment: "test")

    #expect(options.dsn == CrashReporting.dsn)
    #expect(options.sendDefaultPii == false)
    #expect(options.tracesSampleRate == 0)
    #expect(options.attachScreenshot == false)
    #expect(options.attachViewHierarchy == false)
    #expect(options.enableCaptureFailedRequests == false)
    #expect(options.enableLogs)
    #expect(options.enableMetricKit)
    #expect(options.swiftAsyncStacktraces)
    #expect(options.enableWatchdogTerminationTracking)
    #expect(options.sessionReplay.maskAllText)
    #expect(options.sessionReplay.maskAllImages)
    #expect(options.sessionReplay.networkDetailAllowUrls.isEmpty)
    #expect(options.sessionReplay.onErrorSampleRate == 1)
    #expect(options.sessionReplay.sessionSampleRate == 0)
    #if DEBUG
    #expect(options.enableAppHangTracking == false)
    #else
    #expect(options.enableAppHangTracking == true)
    #expect(options.appHangTimeoutInterval == 5.0)
    #endif
}

@Test func crashReportsGoToTheEURegion() throws {
    let host = try #require(URL(string: CrashReporting.dsn)?.host())
    #expect(host.hasSuffix(".ingest.de.sentry.io"))
}

@Test func networkBreadcrumbsLoseTheirQuery() {
    let crumb = Breadcrumb(level: .info, category: "http")
    crumb.setData(
        value: "https://api.sharpit.app/api/v1/planned-sessions/brick/evaluation?groupId=brick-1",
        key: "url"
    )
    crumb.setData(value: 200, key: "status_code")

    let scrubbed = CrashReporting.scrub(crumb)

    #expect(scrubbed?.data?["url"] as? String == "https://api.sharpit.app/api/v1/planned-sessions/brick/evaluation")
    #expect(scrubbed?.data?["status_code"] as? Int == 200)
}

/// Sentry builds network breadcrumbs on URLSession's queue: the hooks must run off the main
/// actor, or the isolation check traps the app on a cancelled request at launch.
@Test func sentryHooksRunOffTheMainThread() async {
    let options = Options()
    CrashReporting.configure(options, environment: "test")
    nonisolated(unsafe) let hooks = options
    let survived = await withCheckedContinuation { continuation in
        DispatchQueue.global().async {
            let crumb = Breadcrumb(level: .info, category: "http")
            crumb.setData(value: "https://api.sharpit.app/api/v1/today?day=1", key: "url")
            _ = hooks.beforeBreadcrumb?(crumb)
            _ = hooks.beforeSend?(Event(level: .error))
            continuation.resume(returning: !Thread.isMainThread)
        }
    }
    #expect(survived)
}
