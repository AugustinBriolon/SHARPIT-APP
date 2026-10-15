import Foundation
import Testing
@testable import Sharpit

/// Every limiter code the server glossary ships must carry both density labels in-app,
/// matching `verdict-copy.snapshot.json` byte-for-byte on the essential / expert strings.
@Test func everyLimiterCodeHasBothLabelsMatchingTheSnapshot() throws {
    let data = try fixtureData("verdict-copy.snapshot.json")
    let snapshot = try JSONDecoder().decode(VerdictCopySnapshot.self, from: data)

    #expect(snapshot.limiterSignals.count == LimiterSignalCode.knownOrdered.count)

    for code in LimiterSignalCode.knownOrdered {
        let wire = try #require(code.wireValue)
        let pair = try #require(snapshot.limiterSignals[wire])
        let labels = try #require(code.labels())
        #expect(labels.essential == pair.essential)
        #expect(labels.expert == pair.expert)
    }
}

@Test func limiterChipFormatsByDensity() {
    #expect(LimiterChipCopy.text(codes: [], isExpert: false) == nil)
    #expect(LimiterChipCopy.text(codes: [.unknown("x")], isExpert: false) == nil)

    #expect(
        LimiterChipCopy.text(codes: [.hrvLow], isExpert: false)
            == "Frein · Corps pas encore récupéré"
    )
    #expect(
        LimiterChipCopy.text(codes: [.hrvLow], isExpert: true)
            == "Frein · VFC basse"
    )

    #expect(
        LimiterChipCopy.text(codes: [.hrvLow, .sleepShort], isExpert: false)
            == "Frein · 2 signaux"
    )
    #expect(
        LimiterChipCopy.text(codes: [.hrvLow, .sleepShort], isExpert: true)
            == "Frein · VFC basse, Sommeil court"
    )
}

@Test func unresolvedPlaceholderFallsBackWithoutEchoingText() {
    let tainted = "Repos car {limiter} est bas"
    #expect(VerdictCopySanitizer.containsUnresolvedPlaceholder(tainted))
    #expect(
        VerdictCopySanitizer.display(tainted, fallback: VerdictCopySanitizer.fallbackExplanation)
            == VerdictCopySanitizer.fallbackExplanation
    )
    #expect(
        VerdictCopySanitizer.display("Privilégie le repos.", fallback: "x")
            == "Privilégie le repos."
    )
}

/// Minimal decode of the snapshot keys the client asserts against.
private struct VerdictCopySnapshot: Decodable {
    struct DensityPair: Decodable {
        var essential: String
        var expert: String
    }

    var limiterSignals: [String: DensityPair]
}
