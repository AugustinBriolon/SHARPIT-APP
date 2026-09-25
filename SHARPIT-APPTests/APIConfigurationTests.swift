import Foundation
import Testing
@testable import Sharpit

struct APIConfigurationTests {
    private let scheme = "SHARPIT_API_ORIGIN"

    @Test func schemeOverrideWinsOverTheBuildOrigin() {
        let url = APIConfiguration.resolve(
            environment: [scheme: "https://preview.example.app"],
            bundleValue: "https://sharpit.app"
        )
        #expect(url?.absoluteString == "https://preview.example.app")
    }

    @Test func buildOriginIsUsedWhenNothingOverridesIt() {
        let url = APIConfiguration.resolve(environment: [:], bundleValue: "https://sharpit.app")
        #expect(url?.absoluteString == "https://sharpit.app")
    }

    @Test func overrideIsTrimmed() {
        let url = APIConfiguration.resolve(
            environment: [scheme: "  https://preview.example.app\n"],
            bundleValue: nil
        )
        #expect(url?.absoluteString == "https://preview.example.app")
    }

    @Test(arguments: ["", "   ", "not a url", "preview.example.app", "https://"])
    func unusableOverrideFallsBackToTheBuild(raw: String) {
        let url = APIConfiguration.resolve(
            environment: [scheme: raw],
            bundleValue: "https://sharpit.app"
        )
        #expect(url?.absoluteString == "https://sharpit.app")
    }

    @Test func noOriginAnywhereIsNil() {
        #expect(APIConfiguration.resolve(environment: [:], bundleValue: nil) == nil)
        #expect(APIConfiguration.resolve(environment: [:], bundleValue: "$(SHARPIT_API_ORIGIN)") == nil)
    }

    /// The xcconfig → Info.plist wiring, which the pure cases above cannot see: a build
    /// that forgot to substitute the setting would ship with no origin at all.
    @Test func thisBuildCarriesAUsableOrigin() {
        let bundleValue = Bundle.main.object(forInfoDictionaryKey: "SharpitAPIOrigin") as? String
        let url = APIConfiguration.resolve(environment: [:], bundleValue: bundleValue)
        #expect(url != nil)
    }

    @Test func clerkPublishableKeyIsProduction() {
        #expect(ClerkConfiguration.publishableKey.starts(with: "pk_live_"))
    }

    @Test func webOriginIsTheBuildsOwnValue() {
        #expect(APIConfiguration.webOrigin(bundleValue: "https://sharpit.app")?.absoluteString == "https://sharpit.app")
        #expect(APIConfiguration.webOrigin(bundleValue: "$(SHARPIT_WEB_ORIGIN)") == nil)
        #expect(APIConfiguration.webOrigin(bundleValue: nil) == nil)
    }

    @Test func legalDocumentsOpenOnTheWebOriginNeverTheAPI() {
        for document in LegalDocument.allCases {
            #expect(document.url == APIConfiguration.webOrigin.appending(path: "/\(document.rawValue)"))
        }
    }
}
