import Foundation
import RailTestSupport
import Testing

/// Source-structure guards for map-lock round 7. The pure rules are tested in
/// RailPresentation; these pin that the app still uses them.
@Suite("RegressionGuardRound7")
struct RegressionGuardRound7 {
    private static let coordinator = SourceFiles.textRecording("RailMap/Map/RailMapCoordinator.swift")

    private static func body(_ source: String, from start: String, to end: String) throws -> Substring {
        let from = try #require(source.range(of: start))
        let to = try #require(source.range(of: end, range: from.upperBound..<source.endIndex))
        return source[from.lowerBound..<to.lowerBound]
    }

    // MARK: A. continuous zoom

    @Test func travelPreparationIsStartedFromTheRebuildAndTheMovingLoadPass() throws {
        let c = Self.coordinator
        #expect(c.contains("private func startTravelPreparation("))
        #expect(c.contains("startTravelPreparation(zoom: zoom, on: mapView) {\n                    extendTripsAtInstalledLevel(on: mapView)\n                    return\n                }"))
        #expect(c.contains("startTravelPreparation(zoom: zoom, on: mapView)\n                    extendTripsAtInstalledLevel(on: mapView)"))
        let travel = try Self.body(
            c, from: "private func startTravelPreparation(", to: "private func scheduleTravelStopRebuild(")
        #expect(travel.contains("GeometryZoomLevels.travelLevel("))
        #expect(travel.contains("installs: false"))
        #expect(travel.contains("landingDecision("))
        // A cached target never clears a valid pending install.
        #expect(travel.contains("if let decision = landingDecision("))
        #expect(travel.contains("preparedAhead: true"))
        #expect(!travel.contains("pendingInstall = landingDecision("))
        // The stop re-check is armed by the preparation itself, not only by a later camera change.
        #expect(travel.contains("scheduleTravelStopRebuild(on: mapView)"))
    }

    /// Order inside `rebuild`: the landed install is validated and installed
    /// before any travel preparation, travel starts only while the fingers are
    /// down, and a travel start never short-circuits a pending install.
    @Test func travelPreparationNeverPrecedesALandedInstallOrRunsOnASettledRebuild() throws {
        let rebuild = try Self.body(
            Self.coordinator, from: "private func rebuild(\n                on mapView: MKMapView, duringGesture",
            to: "let rebuildTrigger = pendingRebuildTrigger ?? .update")
        let validate = try #require(rebuild.range(of: "if pendingInstall != nil { _ = geometryLevelToBuild(at: zoom, on: mapView) }"))
        let early = try #require(rebuild.range(of: "if pendingInstall == nil, cameraMoving,"))
        let commit = try #require(rebuild.range(of: "networkBuildState.commit("))
        let after = try #require(rebuild.range(of: "if installedPendingThisPass, cameraMoving {"))
        #expect(validate.lowerBound < early.lowerBound)
        #expect(early.lowerBound < commit.lowerBound)
        #expect(commit.lowerBound < after.lowerBound)
        #expect(rebuild.contains("let cameraMoving = cameraTravelling"))
        #expect(rebuild.contains("|| pending.visibilityZoom != nil"))
    }

    @Test func onlyATravelPreparationOverridesTheVisibilityZoomOfALanding() throws {
        let c = Self.coordinator
        let landing = try Self.body(
            c, from: "private func landingDecision(", to: "/// While the camera zooms out fast, prepare the level")
        #expect(landing.contains("preparedAhead: Bool"))
        #expect(!landing.contains("abs(visibilityZoom - cameraVisibilityZoom)"))
        #expect(c.contains("preparedAhead: !installs, on: mapView)"))
    }

    @Test func aNewPickNeverRebatchesWhileAStrokeBuildIsPendingAndCasingsAreNotDuplicated() throws {
        let c = Self.coordinator
        let current = try Self.body(
            c, from: "private func batchCacheIsCurrent(", to: "/// Moves the new selection out of its batch")
        #expect(current.contains("guard rideStrokePreparation == nil,"))
        #expect(current.contains("cache.stamp.frameKey == frame.key"))
        #expect(c.contains("if !casings.contains(where: { $0.title == key }) { casings.append(multi) }"))
    }

    @Test func theMapDiffsTheRideDateThroughTheEraRule() {
        #expect(Self.coordinator.contains("display.networkEra.effectiveRideDate(networkRideDate)"))
    }

    @Test func aTravelRequestNeverBeginsAFrameAndTheGateGetsTheInstallRule() throws {
        let prepare = try Self.body(
            Self.coordinator, from: "if gate.drawNow {", to: "guard gate.start else { return false }")
        #expect(prepare.contains("if installs { networkGeometry.beginFrame(key: key, isOverview: frame.isOverview) }"))
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
        #expect(fallback.contains("rideStrokePreparationRideIDs == [previous]"))
        #expect(fallback.contains("rideStrokePreparation?.cancel()"))
        // The update that SwiftUI queued behind a gesture is replaced by any
        // newer update before it can apply an older id.
        #expect(c.contains("// A newer normal update supersedes any queued gesture update.\n                pendingViewUpdate = nil"))
    }

    @Test func aFocusFitIsStoppedByANewerCameraIntentAndEndsWithTheSettledRegion() throws {
        let controller = SourceFiles.textRecording("RailMap/Map/RailMapController.swift")
        #expect(controller.contains("if olderFitRunning, autoFocusRequest != nil { stopFocusFit() }"))
        #expect(controller.contains("if cameraPolicy.cancelFocus() { stopFocusFit() }"))
        #expect(controller.contains("if cameraPolicy.claimCamera() { stopFocusFit() }"))
        #expect(controller.contains("mapView.setVisibleMapRect(mapView.visibleMapRect, animated: false)"))
        // The mark is raised before the call, only for an animated fit that moves.
        let fit = try Self.body(controller, from: "func fit(_ rect: MKMapRect", to: "func fitIfNeeded(")
        let begin = try #require(fit.range(of: "cameraPolicy.beginFocusFit()"))
        let set = try #require(fit.range(of: "mapView.setVisibleMapRect(\n            rect,"))
        #expect(begin.lowerBound < set.lowerBound)
        #expect(fit.contains("if startedByFocus, isAnimated {"))
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
        let labels = SourceFiles.textRecording("RailMap/Map/MapStationLabelCoordinator.swift")
        #expect(labels.contains("private var labelWidths: [LabelWidthKey: CGFloat]"))
        #expect(labels.contains("func invalidateLabelWidths()"))
        #expect(c.contains("if namingChanged { stationLabels.invalidateLabelWidths() }"))
        for phase in ["networkStations.filter", "networkStations.election", "networkStations.annotations"] {
            #expect(c.contains("finishMarkerPhase(\"\(phase)\")"), "\(phase)")
        }
    }
}
