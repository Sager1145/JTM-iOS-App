import Foundation
import RailTestSupport
import Testing

/// Source-structure guards for map-lock round 8 (continuous zoom-out). The
/// pure rules are tested in RailPresentation; these pin that the app uses them.
@Suite("RegressionGuardRound8")
struct RegressionGuardRound8 {
    private static var coordinator: String { SourceFiles.textRecording("RailMap/Map/RailMapCoordinator.swift") }

    private static func body(_ source: String, from start: String, to end: String) throws -> Substring {
        let from = try #require(source.range(of: start))
        let to = try #require(source.range(of: end, range: from.upperBound..<source.endIndex))
        return source[from.lowerBound..<to.lowerBound]
    }

    @Test func travelIsGatedOnZoomMotionNotRecognisers() {
        let c = Self.coordinator
        #expect(!c.contains("if isManipulating { startTravelPreparation"))
        #expect(c.contains("private var cameraTravelling: Bool"))
        #expect(c.contains("zoomTravel.isTravelling(at:"))
        #expect(c.contains("let cameraMoving = cameraTravelling"))
        #expect(c.contains("stopped: !cameraTravelling"))
        #expect(!c.contains("installedCoversView"))
        #expect(!c.contains("let installedCovers"))
        #expect(c.contains("guard cameraTravelling, playbackLayer.lastSnapshot == nil, showsNetwork,"))
    }

    @Test func aLandedLevelInstallsWhileTheCameraTravels() {
        let c = Self.coordinator
        #expect(c.contains("let installNow = self.pendingInstall != nil && self.cameraTravelling"))
        #expect(c.contains("self.rebuild(on: mapView, duringGesture: installNow, deferMarkers: installNow)"))
    }

    @Test func tripExtensionIsCalledFromTheMovingPassAndBothEarlyReturns() throws {
        let c = Self.coordinator
        let pass = try Self.body(
            c, from: "private func runMovingLoadPass(", to: "private func extendBuiltAreaWhileMoving(")
        #expect(pass.contains("if cameraTravelling {"))
        #expect(pass.contains("extendTripsAtInstalledLevel(on: mapView)"))
        let travelReturn = try Self.body(
            c, from: "if pendingInstall == nil, cameraMoving,", to: "let visibilityZoom = pendingInstall?.visibilityZoom")
        #expect(travelReturn.contains("extendTripsAtInstalledLevel(on: mapView)"))
        let prepareReturn = try Self.body(
            c, from: "visibilityBucket: visibilityBucket\n                ) else {", to: "// What is eligible")
        #expect(prepareReturn.contains("extendTripsAtInstalledLevel(on: mapView)"))
    }

    /// The extension is independent of the network level: no preparation, no
    /// permit, no frame change, no build-state commit.
    @Test func tripExtensionTouchesNoLevelMachinery() throws {
        let body = try Self.body(
            Self.coordinator, from: "private func extendTripsAtInstalledLevel(",
            to: "private func noteTripsDrawn(")
        for forbidden in ["prepareNetworkGeometry", "geometryWorkLimiter", "beginFrame", "networkBuildState.commit"] {
            #expect(!body.contains(forbidden), "extension must not use \(forbidden)")
        }
        #expect(body.contains("TripAreaExtension.area("))
        #expect(body.contains("TripAreaExtension.isDue("))
        #expect(body.contains("storeStroke("))
        #expect(body.contains("installedTripRect = area"))
    }

    @Test func rideBatchPathReadsTheInstalledTripRect() throws {
        let c = Self.coordinator
        #expect(c.contains("private var installedTripRect"))
        #expect(c.contains("installedTripRect = rideBuildRect"))
        #expect(c.contains("buildRect: installedTripRect, linesGeneration"))
        let update = try Self.body(
            c, from: "private func updateRides(", to: "private func applyRideChange(")
        #expect(update.contains("let rideBuildRect = installedTripRect"))
        #expect(!update.contains("NetworkLOD.tripArea("))
        #expect(update.contains("return applyRideChange("))
    }

    @Test func tripsDrawnSignpostExists() {
        #expect(Self.coordinator.contains("\"map.trips.drawn\""))
    }

    /// Both travel-time trip paths must act only on the installed frame: the
    /// cache can already read the next level's entry after a rebuild stopped.
    @Test func travelTripPathsRequireTheInstalledCacheFrame() throws {
        let c = Self.coordinator
        for (from, to) in [
            ("private func extendTripsAtInstalledLevel(", "private func noteTripsDrawn("),
            ("private func reapplyTripsDuringTravel(", "private var arrivalStrokePreparation"),
        ] {
            let body = try Self.body(c, from: from, to: to)
            #expect(body.contains("networkGeometry.currentFrameKey == frame.key"), "\(from) needs the frame key check")
            #expect(body.contains("!rebuildDeferredByGesture"), "\(from) needs the deferred-rebuild check")
        }
        let reapply = try Self.body(
            c, from: "private func reapplyTripsDuringTravel(", to: "private var arrivalStrokePreparation")
        #expect(reapply.contains("cache.stamp == expected"))
        let extend = try Self.body(
            c, from: "private func extendTripsAtInstalledLevel(", to: "private func noteTripsDrawn(")
        #expect(extend.contains("<= 1"))
    }
}
