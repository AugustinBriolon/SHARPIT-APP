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

    // MARK: Planned session

    /// The header, the figures between hairlines, the steps as a table.
    @Test(arguments: [UIUserInterfaceStyle.light, .dark])
    func thePlannedSessionLeadsWithItsSteps(style: UIUserInterfaceStyle) async throws {
        let preview = PlannedSessionPreview.demo
        let summary = PlannedSessionSummary(
            preview: preview, steps: preview.steps, stepsAreDerived: false
        ) { EmptyView() }
        // At its ideal height, as its scroll view lays it out.
        try await assertSnapshot(onCanvas(summary.fixedSize(horizontal: false, vertical: true)), named: "planned-session", style: style)
    }

    /// A hot, wet day: « Météo prévue » between the figures and the steps, one line per advisory.
    @Test(arguments: [UIUserInterfaceStyle.light, .dark])
    func thePlannedSessionSaysWhatTheForecastAsks(style: UIUserInterfaceStyle) async throws {
        let preview = PlannedSessionPreview.demo(conditions: [.reduceIntensity, .hydration, .rainRisk])
        let summary = PlannedSessionSummary(
            preview: preview, steps: preview.steps, stepsAreDerived: false
        ) { EmptyView() }
        try await assertSnapshot(onCanvas(summary.fixedSize(horizontal: false, vertical: true)), named: "planned-session-weather", style: style)
    }

    /// The stretches open, answered: both tags, the moves, the choice with « Fait » picked.
    private func answeredStretches() throws -> some View {
        var routine = try #require(PlannedSessionPreview.demo.routines?.cooldown)
        routine.status = V1RoutineStatus.done.rawValue
        return SessionRoutinePanel(title: String(localized: "Étirements ciblés"), routine: routine, onStatus: { _ in }, isExpanded: true)
    }

    @Test(arguments: [UIUserInterfaceStyle.light, .dark])
    func theRoutinePanelAsksWhatTheAthleteDid(style: UIUserInterfaceStyle) async throws {
        try await assertSnapshot(onCanvas(try answeredStretches()), named: "routine-panel", style: style)
    }

    /// At the accessibility sizes the header stacks and the choice goes vertical. The fonts scale
    /// with the app's text size (`UIFontMetrics`), which a test cannot set, so this pins the
    /// layout, not the glyphs' size.
    @Test func theRoutinePanelStacksAtTheAccessibilitySizes() async throws {
        let panel = try answeredStretches().environment(\.dynamicTypeSize, .accessibility3)
        try await assertSnapshot(onCanvas(panel), named: "routine-panel-accessibility")
    }

    /// Musculation in Matériel: where the athlete lifts as two switches, the kit as switch lines.
    @Test func theStrengthKitIsSwitchLines() async throws {
        try await assertSnapshot(
            EquipmentBySport(
                sports: [.strength], venue: .both, owned: ["strength_bench", "strength_bands"],
                onVenue: { _ in }, onToggle: { _ in }
            )
            .padding(24)
            .background(SharpitColor.card),
            named: "equipment-strength"
        )
        try await assertSnapshot(
            EquipmentBySport(sports: [.strength], venue: .bodyweight, owned: [], onVenue: { _ in }, onToggle: { _ in })
                .padding(24)
                .background(SharpitColor.card),
            named: "equipment-strength-bodyweight"
        )
    }
}

extension UIUserInterfaceStyle: @retroactive CustomTestStringConvertible {
    public var testDescription: String { self == .dark ? "dark" : "light" }
}
