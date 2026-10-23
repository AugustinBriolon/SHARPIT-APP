import Foundation
import SentrySwift

/// Crash reports, structured logs, and masked error-only session replays to Sentry (EU).
///
/// No performance tracing, no crash screenshots, no view hierarchy, no default PII.
/// Replay stays masked and only uploads the ~30s buffer when an error/crash happens.
/// A report must never carry what the athlete measured or wrote. Breadcrumbs keep network
/// URLs only by path, and every event is stripped of request bodies before it leaves.
/// Nonisolated: Sentry runs `beforeSend` / `beforeBreadcrumb` on its own queues, and a
/// main-actor closure there traps at launch (libdispatch "expected main-thread").
enum CrashReporting {
    /// A DSN is a public client key — safe in the binary, it can only send events.
    static let dsn = "https://82d4a00ff393d0fa14999292cb2cf454@o4512180262535168.ingest.de.sentry.io/4512180266860624"

    static func start(environment: String = defaultEnvironment) {
        SentrySDK.start { options in
            configure(options, environment: environment)
        }
    }

    static func configure(_ options: Options, environment: String) {
        options.dsn = dsn
        options.environment = environment
        options.sendDefaultPii = false
        options.tracesSampleRate = 0
        options.attachScreenshot = false
        options.attachViewHierarchy = false

        // Structured logs: searchable in Sentry even when nothing is raised as an error.
        // They flush on a timer and on the next launch after a hard kill — not mid-SIGKILL.
        options.enableLogs = true

        // MetricKit: hangs, CPU spikes, disk-write exceptions that are not NSExceptions.
        options.enableMetricKit = true

        // Concurrency frames in crash stacks (HealthKit / MainActor traps).
        options.swiftAsyncStacktraces = true

        // Jetsam / force-quit after memory pressure — reported on the next cold start.
        options.enableWatchdogTerminationTracking = true

        // Replay: buffer only; upload the last ~30s when an error or crash is sampled.
        // Never film every session (memory). Text and images stay masked.
        options.sessionReplay.maskAllText = true
        options.sessionReplay.maskAllImages = true
        options.sessionReplay.onErrorSampleRate = 1
        options.sessionReplay.sessionSampleRate = 0

        options.enableAutoBreadcrumbTracking = true
        options.enableNetworkBreadcrumbs = true
        options.enableCaptureFailedRequests = false
        options.beforeBreadcrumb = { scrub($0) }
        options.beforeSend = { event in
            // `AppDistribution.prepare()` may finish after `start()`; stamp the current env on each event.
            event.environment = defaultEnvironment
            event.request = nil
            event.user = event.user.map { user in
                let anonymous = User()
                anonymous.userId = user.userId
                return anonymous
            }
            return event
        }
    }

    /// Network breadcrumbs keep their path, never a query: `?groupId=…&date=…` says too much.
    static func scrub(_ crumb: Breadcrumb) -> Breadcrumb? {
        guard let data = crumb.data, let raw = data["url"] as? String,
              var components = URLComponents(string: raw) else { return crumb }
        components.query = nil
        crumb.setData(value: components.string, key: "url")
        return crumb
    }

    /// Breadcrumb + structured log for a privacy-safe checkpoint (screen, gate, HK wake…).
    /// Never pass health values, notes, tokens, or free text the athlete typed.
    static func note(_ message: String, category: String = "app") {
        let crumb = Breadcrumb(level: .info, category: category)
        crumb.message = message
        SentrySDK.addBreadcrumb(crumb)
        SentrySDK.logger.info(message, attributes: ["category": category])
    }

    /// Ties reports to the Clerk user id only, so a crash can be matched to a support request.
    static func identify(userId: String?) {
        SentrySDK.setUser(userId.map { id in
            let user = User()
            user.userId = id
            return user
        })
    }

    static var defaultEnvironment: String {
        if AppDistribution.isDebug { return "debug" }
        return AppDistribution.isTestFlight ? "testflight" : "production"
    }
}
