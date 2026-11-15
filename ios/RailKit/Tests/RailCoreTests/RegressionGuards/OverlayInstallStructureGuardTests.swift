import Foundation
import Testing

/// The overlay install must put new overlays at their final index (rules in
/// `OverlayInsertionPlanTests`) instead of appending and exchanging them back
/// down, which cost 20 to 30 ms per camera settle.
@Suite("RegressionGuardOverlayInstall")
struct RegressionGuardOverlayInstall {
    private static let source: String = {
        let ios = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent()
        return (try? String(contentsOf: ios.appendingPathComponent("RailMap/Map/MapNetworkRendering.swift"),
                            encoding: .utf8)) ?? ""
    }()

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
