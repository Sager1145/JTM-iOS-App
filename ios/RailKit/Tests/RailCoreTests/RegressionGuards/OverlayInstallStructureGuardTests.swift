import Foundation
import RailTestSupport
import Testing

/// The overlay install must put new overlays at their final index (rules in
/// `OverlayInsertionPlanTests`) instead of appending and exchanging them back
/// down, which cost 20 to 30 ms per camera settle.
@Suite("RegressionGuardOverlayInstall")
struct RegressionGuardOverlayInstall {
    private static var source: String { SourceFiles.textRecording("RailMap/Map/MapNetworkRendering.swift") }

    @Test func installInsertsAtFinalPositionAndNeverBulkAppends() throws {
        let s = Self.source
        let from = try #require(s.range(of: "    func install("))
        let to = try #require(s.range(of: "private func beginSwap("))
        let body = String(s[from.lowerBound..<to.lowerBound])
        #expect(body.contains("OverlayInsertionPlan.steps("))
        #expect(body.contains("mapView.insertOverlay(overlay, at: step.index, level: .aboveLabels)"))
        #expect(!body.contains("mapView.addOverlays("))
    }
}
