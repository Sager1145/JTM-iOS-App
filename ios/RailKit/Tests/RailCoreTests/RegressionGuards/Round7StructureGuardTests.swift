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

    // MARK: C. selection

    @Test func theSelectionPathDecidesThroughThePlanAndNeverRebuilds() throws {
        let c = Self.coordinator
        let update = try Self.body(
            c, from: "private func updateSelection(on mapView: MKMapView) -> Bool {",
            to: "private var detailDuration: TimeInterval")
        #expect(update.contains("SelectionApplyPlan.decide("))
        #expect(!update.contains("rebuild("), "updateSelection answers in place or reports false")
        #expect(!update.contains("rebuildOwed("))
        // It reads the map's own selection, never an id handed in.
        #expect(c.contains("private func updateSelection(on mapView: MKMapView) -> Bool {"))
        #expect(!update.contains("[selectedTrainID"))
        // One construction of the selected ride's overlays, shared with rebuild.
        #expect(c.components(separatedBy: "appendSelectedRideOverlays(").count - 1 == 3)
        let rebatch = try Self.body(
            c, from: "private func rebatchForNewSelection(", to: "private func updateSelection(")
        #expect(rebatch.contains("RideOverlayBatching.entry("))
        #expect(rebatch.contains("RideOverlayBatching.replan("))
        #expect(rebatch.contains("cache.stamp = rideBatchStamp("))
        #expect(rebatch.contains("fullyBuiltSelectedRideID = selectedID"))
    }

    @Test func theMapAppliesOnlyItsOwnSelectionAndTheFallbackCancelsStaleStrokeBuilds() throws {
        let c = Self.coordinator
        let fallback = try Self.body(
            c, from: "} else if !updateSelection(on: mapView) {", to: "case .rebuild:")
        #expect(fallback.contains("rideStrokePreparationRideIDs.contains(previous)"))
        #expect(fallback.contains("rideStrokePreparation?.cancel()"))
        // The update that SwiftUI queued behind a gesture is replaced by any
        // newer update before it can apply an older id.
        #expect(c.contains("// A newer normal update supersedes any queued gesture update.\n                pendingViewUpdate = nil"))
    }

    @Test func aFocusFitIsStoppedByANewerCameraIntentAndEndsWithTheSettledRegion() throws {
        let controller = Self.read("RailMap/Map/RailMapController.swift")
        #expect(controller.contains("if olderFitRunning { stopFocusFit() }"))
        #expect(controller.contains("if cameraPolicy.cancelFocus() { stopFocusFit() }"))
        #expect(controller.contains("if cameraPolicy.claimCamera() { stopFocusFit() }"))
        #expect(controller.contains("mapView.setVisibleMapRect(mapView.visibleMapRect, animated: false)"))
        #expect(controller.contains("if startedByFocus { cameraPolicy.beginFocusFit() }"))
        let settled = try Self.body(
            Self.coordinator, from: "func mapView(_ mapView: MKMapView, regionDidChangeAnimated animated: Bool) {",
            to: "if controller?.tripNotePickTrainID")
        #expect(settled.contains("controller?.endFocusFit()"))
    }

    // MARK: B. station election

    @Test func theStationElectionChecksTheOwnBeadFirstMemoisesWidthsAndNamesItsPhases() throws {
        let c = Self.coordinator
        let suppressed = try Self.body(
            c, from: "func isSuppressedTenantBead(", to: "let era = display.networkEra")
        let own = try #require(suppressed.range(of: "let own = beadPolicyStation(station)"))
        let guardRange = try #require(suppressed.range(of: "guard own.tenantGroup != nil else { return false }"))
        let siblings = try #require(suppressed.range(of: "map(beadPolicyStation)"))
        #expect(own.lowerBound < guardRange.lowerBound)
        #expect(guardRange.lowerBound < siblings.lowerBound)
        // Widths come from the memo, never a fresh NSString measurement.
        let election = try Self.body(
            c, from: "var acceptedStationNames: Set<String> = []", to: "finishMarkerPhase(\"networkStations.election\")")
        #expect(election.contains("stationLabels.labelWidth("))
        #expect(!election.contains("NSString).size("))
        let labels = Self.read("RailMap/Map/MapStationLabelCoordinator.swift")
        #expect(labels.contains("private var labelWidths: [LabelWidthKey: CGFloat]"))
        #expect(labels.contains("func invalidateLabelWidths()"))
        #expect(c.contains("if namingChanged { stationLabels.invalidateLabelWidths() }"))
        for phase in ["networkStations.filter", "networkStations.election", "networkStations.annotations"] {
            #expect(c.contains("finishMarkerPhase(\"\(phase)\")"), "\(phase)")
        }
    }
}
