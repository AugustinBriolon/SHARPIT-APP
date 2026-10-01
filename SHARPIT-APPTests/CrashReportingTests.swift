import Foundation
import Sentry
import Testing
@testable import Sharpit

/// A crash report must never carry what the athlete measured or wrote.
@Test func crashReportsCarryNoPersonalDataOrTracing() {
    let options = Options()
    CrashReporting.configure(options, environment: "test")

    #expect(options.dsn == CrashReporting.dsn)
    #expect(options.sendDefaultPii == false)
    #expect(options.tracesSampleRate == 0)
    #expect(options.attachScreenshot == false)
    #expect(options.attachViewHierarchy == false)
    #expect(options.enableCaptureFailedRequests == false)
}

@Test func crashReportsGoToTheEURegion() throws {
    let host = try #require(URL(string: CrashReporting.dsn)?.host())
    #expect(host.hasSuffix(".ingest.de.sentry.io"))
}

@Test func networkBreadcrumbsLoseTheirQuery() {
    let crumb = Breadcrumb(level: .info, category: "http")
    crumb.data = ["url": "https://api.sharpit.app/api/v1/planned-sessions/brick/evaluation?groupId=brick-1", "status_code": 200]

    let scrubbed = CrashReporting.scrub(crumb)

    #expect(scrubbed?.data?["url"] as? String == "https://api.sharpit.app/api/v1/planned-sessions/brick/evaluation")
    #expect(scrubbed?.data?["status_code"] as? Int == 200)
}
