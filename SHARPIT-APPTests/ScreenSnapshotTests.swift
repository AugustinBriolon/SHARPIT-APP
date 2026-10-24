import Foundation
import SwiftUI
import Testing
@testable import Sharpit

/// The surfaces fixed again and again by hand, pinned as pictures (`Snapshot.swift`).
@MainActor
@Suite(.serialized)
struct ScreenSnapshotTests {
    private func onCanvas(_ view: some View) -> some View {
        view
            .padding(16)
            .background(SharpitCanvasBackground())
    }

    // MARK: Zones

    @Test(arguments: [UIUserInterfaceStyle.light, .dark])
    func theZoneSilhouetteDrawsEveryPart(style: UIUserInterfaceStyle) async throws {
        let picker = SensitiveZoneBodyPicker(
            offered: Array(SensitiveZoneBody.mappedParts),
            part: .constant(nil),
            side: .constant("NA")
        )
        try await assertSnapshot(onCanvas(picker), named: "zone-picker-empty", style: style)
    }

    @Test func aWomanSeesAWomansFigure() async throws {
        let picker = SensitiveZoneBodyPicker(
            offered: Array(SensitiveZoneBody.mappedParts),
            figure: .female,
            part: .constant("Hanche"),
            side: .constant("LEFT")
        )
        try await assertSnapshot(onCanvas(picker), named: "zone-picker-female")
    }

    @Test func aChosenZoneFillsBothSidesAndIsNamed() async throws {
        let picker = SensitiveZoneBodyPicker(
            offered: Array(SensitiveZoneBody.mappedParts),
            part: .constant("Genou"),
            side: .constant("BILATERAL")
        )
        try await assertSnapshot(onCanvas(picker), named: "zone-picker-knees")
    }

    // MARK: Activity curves

    private static let samples: [V1ActivityStreamSample] = (0..<240).map { index in
        let t = Double(index) * 15
        let wave = sin(Double(index) / 12)
        return V1ActivityStreamSample(
            t: t,
            d: t * 3,
            alt: 40 + 12 * wave,
            hr: 138 + 14 * wave,
            watts: 210 + 40 * wave,
            cadence: 86 + 4 * wave,
            speed: 3.1 + 0.3 * wave
        )
    }

    /// Five toggles overflow a phone's width: they must stop at the card's edge.
    @Test(arguments: [UIUserInterfaceStyle.light, .dark])
    func theCurveTogglesStayInsideTheirCard(style: UIUserInterfaceStyle) async throws {
        let section = ActivityChartsSection(
            samples: Self.samples,
            metrics: ActivityChartMetric.allCases,
            selection: .constant([.heartRate, .pace])
        )
        try await assertSnapshot(onCanvas(section), named: "activity-curves", style: style)
    }
}

extension UIUserInterfaceStyle: @retroactive CustomTestStringConvertible {
    public var testDescription: String { self == .dark ? "dark" : "light" }
}
