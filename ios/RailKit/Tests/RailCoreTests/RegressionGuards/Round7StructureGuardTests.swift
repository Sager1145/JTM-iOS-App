import Foundation
import Testing

/// Source-structure guards for map-lock round 7. The pure rules are tested in
/// RailPresentation; these pin that the app still uses them.
@Suite("RegressionGuardRound7")
struct RegressionGuardRound7 {
    private static let ios: URL = {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent() // RegressionGuards
            .deletingLastPathComponent() // RailCoreTests
            .deletingLastPathComponent() // Tests
            .deletingLastPathComponent() // RailKit
            .deletingLastPathComponent() // ios
    }()

    private static func read(_ path: String) -> String {
        (try? String(contentsOf: ios.appendingPathComponent(path), encoding: .utf8)) ?? ""
    }

    private static let coordinator = read("RailMap/Map/RailMapCoordinator.swift")

    private static func body(_ source: String, from start: String, to end: String) throws -> Substring {
        let from = try #require(source.range(of: start))
        let to = try #require(source.range(of: end, range: from.upperBound..<source.endIndex))
        return source[from.lowerBound..<to.lowerBound]
    }

    // MARK: A. continuous zoom

    @Test func travelPreparationIsStartedFromTheRebuildAndTheMovingLoadPass() throws {
        let c = Self.coordinator
        #expect(c.contains("private func startTravelPreparation("))
        #expect(c.contains("if startTravelPreparation(zoom: zoom, on: mapView) { return }"))
        #expect(c.contains("if isManipulating { startTravelPreparation(zoom: zoom, on: mapView) }"))
        let travel = try Self.body(
            c, from: "private func startTravelPreparation(", to: "private func scheduleTravelStopRebuild(")
        #expect(travel.contains("GeometryZoomLevels.travelLevel("))
        #expect(travel.contains("installs: false"))
        #expect(travel.contains("landingDecision("))
    }

    @Test func aTravelRequestNeverBeginsAFrameAndTheGateGetsTheInstallRule() throws {
        let prepare = try Self.body(
            Self.coordinator, from: "if gate.drawNow {", to: "guard gate.start else { return false }")
        #expect(prepare.contains("if installs { networkGeometry.beginFrame(key: key) }"))
        #expect(prepare.contains("if gate.cancelInFlight { cancelGeometryPreparation() }"))
        let gate = try Self.body(
            Self.coordinator, from: "let gate = GeometryPreparationGate.decide(", to: "if gate.adoptPrebuild {")
        #expect(gate.contains("inFlightCanInstall: canInstall"))
        #expect(Self.coordinator.contains("GeometryPreparationGate.inFlightCanInstall("))
    }

    @Test func theLevelProbeReadsTheLevelJustInstalledAndOldStateIsGone() throws {
        let c = Self.coordinator
        let commit = try Self.body(c, from: "networkBuildState.commit(", to: "A cold display-network request")
        #expect(commit.contains(
            "MapRenderProbe.geometryLevels.wanted = GeometryZoomLevels.wantedLevel(\n                    zoom: zoom, installed: strokeFrame.bucket)"))
        for gone in ["pendingInstallLevel", "pendingInstallRect", "lastObservedZoom", "var lastZoomDirection"] {
            #expect(!c.contains(gone), "\(gone) was replaced by PendingInstall / ZoomTravel")
        }
        #expect(c.contains("private struct PendingInstall {"))
        #expect(c.contains("travelStopTimer"))
    }
}
