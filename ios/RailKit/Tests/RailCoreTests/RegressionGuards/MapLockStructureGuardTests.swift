import Foundation
import Testing

/// Source-structure guards for the map-lock wiring: the pure RailKit rules are
/// tested on their own; these pin that the app still uses them.
@Suite("RegressionGuardMapLock")
struct RegressionGuardMapLock {
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
    private static let rendering = read("RailMap/Map/MapNetworkRendering.swift")

    private static func body(_ source: String, from start: String, to end: String) throws -> Substring {
        let from = try #require(source.range(of: start))
        let to = try #require(source.range(of: end, range: from.upperBound..<source.endIndex))
        return source[from.lowerBound..<to.lowerBound]
    }

    @Test func touchDownCancelsPreparationOnlyThroughTheGate() throws {
        let began = try Self.body(
            Self.coordinator, from: "case .began:", to: "case .ended, .cancelled, .failed:")
        #expect(began.contains("GeometryPreparationGate.cancelsOnTouchDown("))
        let outside = began.replacingOccurrences(
            of: "GeometryPreparationGate.cancelsOnTouchDown(", with: "")
        let gateRange = try #require(began.range(of: "cancelsOnTouchDown("))
        let before = began[began.startIndex..<gateRange.lowerBound]
        #expect(!before.contains("cancelGeometryPreparation()"))
        #expect(!outside.isEmpty)
    }

    @Test func cameraChangeLoadsAndSwapsWhileMoving() throws {
        let handler = try Self.body(
            Self.coordinator, from: "cancelNeighbourPrebuildIfWantedSetMoved(zoom: zoom)",
            to: "scheduleCameraRebuild(on: mapView)")
        #expect(handler.contains("swapGeometryDuringGestureIfReady("))
        #expect(handler.contains("runMovingLoadPass("))
    }

    @Test func heldJointsAreResolvedWhileMovingAndRefreshedOnSettle() throws {
        #expect(Self.coordinator.contains("strokeStability.resolve(current:"))
        #expect(Self.coordinator.contains("moving: isManipulating"))
        let settle = try Self.body(
            Self.coordinator, from: "if !self.heldJointLineIDs.isEmpty {",
            to: "invalidateGeometry()")
        #expect(settle.contains("refreshLineInputs()"))
    }

    @Test func refreshingLineInputsCancelsTheNeighbourPrebuild() throws {
        let refresh = try Self.body(
            Self.coordinator, from: "private func refreshLineInputs() {",
            to: "let byID = Dictionary(")
        #expect(refresh.contains("cancelNeighbourPrebuild()"))
    }

    @Test func overlaysDrawReportAndSwapWaitsForDraw() {
        #expect(Self.coordinator.contains("DrawReportingMultiPolylineRenderer("))
        #expect(Self.rendering.contains("hasDrawn(forKey:"))
        #expect(Self.rendering.contains("AddOnlyBatchLedger<PolylineItem>"))
        #expect(Self.rendering.contains("buildRect: area"))
    }

    @Test func replacedNetworkOverlaysHandOffAsOneGroup() throws {
        let install = try Self.body(
            Self.rendering, from: "let newNetworkKeys =", to: "mapView.removeOverlays(immediateRemovals)")
        #expect(install.contains("replacesNetwork"))
        #expect(install.contains("handoffs[exitKey]"))
        #expect(!Self.rendering.contains("displayFrame()"))
    }

    @Test func neighbourFramesUseTheByteCapResidencyRule() {
        #expect(Self.rendering.contains("GeometryFrameResidency("))
        #expect(!Self.rendering.contains("GeometryFrameRecency"))
        #expect(!Self.rendering.contains("recentKeys"))
        #expect(!Self.rendering.contains("frameCapacity"))
    }

    @Test func idlePrebuildBuildsOneNeighbourUnderTheCapAndMemoryWarningDropsFrames() throws {
        let prebuild = try Self.body(
            Self.coordinator, from: "private func scheduleNeighbourPrebuild(",
            to: "neighbourPrebuild = Task")
        #expect(prebuild.contains("networkGeometry.hasRoomToPrebuild"))
        #expect(prebuild.contains("GeometryZoomLevels.prebuildNeighbour("))
        #expect(!prebuild.contains("neighbourLevels(of: installed)"))
        #expect(Self.coordinator.contains("didReceiveMemoryWarningNotification"))
        #expect(Self.coordinator.contains("networkGeometry.dropNonCurrentFrames()"))
    }

    @Test func aRebuildDuringAGestureDoesNotRunTheFullMarkerPass() throws {
        let rebuild = String(try Self.body(
            Self.coordinator, from: "private func rebuild(on mapView: MKMapView, duringGesture",
            to: "/// The trip-line cache key of one segment"))
        #expect(rebuild.components(separatedBy: "buildMarkers(").count == 2)
        #expect(!rebuild.contains("annotationReconciler.apply("))
        let deferred = try Self.body(rebuild, from: "case .deferred:", to: "markerPassDebt.noteDeferred()")
        #expect(!deferred.contains("buildMarkers("))
        let full = try Self.body(rebuild, from: "case .full:", to: "case .deferred:")
        #expect(full.contains("buildMarkers("))
        #expect(rebuild.contains("MarkerPassDebt.resetsMovingBudget(duringGesture: duringGesture)"))
        #expect(!rebuild.contains("\n                stationLabels.resetMovingBudget()"))
    }

    @Test func theSettledPassPaysTheDeferredMarkerPass() throws {
        let settle = try Self.body(
            Self.coordinator, from: "private func restartLabelSettleTask(",
            to: "func mapView(_ mapView: MKMapView, regionDidChangeAnimated")
        #expect(settle.contains("markerPassDebt.isOwed"))
        #expect(settle.contains("fullPass: true"))
        let build = try Self.body(
            Self.coordinator, from: "private func buildMarkers(",
            to: "private static let allRideStationsID")
        #expect(build.contains("if !isLabelPass { markerPassDebt.noteFullPassRan() }"))
    }

    @Test func markerPassesQueryTheVisibleRectThroughGrids() throws {
        let build = try Self.body(
            Self.coordinator, from: "private func buildMarkers(",
            to: "private static let allRideStationsID")
        #expect(build.contains("deckRecords.grid.indices("))
        #expect(build.contains("setup.stationGrid.indices("))
        #expect(!build.contains("stations.compactMap"))
        #expect(!build.contains("for item in drawn {"))
        let setup = Self.read("RailMap/Map/RideIncrementalUpdate.swift")
        #expect(setup.contains("SpatialGrid("))
    }

    @Test func strokeInstallInvalidatesOnlyTheChangedTripsRecords() {
        #expect(!Self.coordinator.contains("stationLabels.invalidateGeometry()"))
        #expect(Self.coordinator.components(separatedBy: "stationLabels.invalidateGeometry(forRides:").count == 3)
        let labels = Self.read("RailMap/Map/MapStationLabelCoordinator.swift")
        #expect(labels.contains("func invalidateGeometry(forRides"))
    }

    @Test func missingGeometryWorkReusesTheLinesByIDMap() throws {
        let work = try Self.body(
            Self.coordinator, from: "private func missingGeometryWork(",
            to: "private func linesByID()")
        #expect(work.contains("linesByID()"))
        #expect(!work.contains("Dictionary(lines.map"))
    }

    @Test func touchDownCancelOwesARebuild() throws {
        let began = try Self.body(
            Self.coordinator, from: "case .began:", to: "case .ended, .cancelled, .failed:")
        let cancel = try #require(began.range(of: "cancelGeometryPreparation()"))
        let before = began[began.startIndex..<cancel.lowerBound]
        #expect(before.contains("rebuildDeferredByGesture = true"))
    }

    @Test func matchingCompletionNeverRebuildsUnconditionally() throws {
        let completion = try Self.body(
            Self.coordinator, from: "self.pendingStrokeRefs = (revision, results, inputs)",
            to: "self.runOwedStrokeMatching()\n                }\n            }")
        #expect(completion.contains("applyMatchesIncrementally(on:"))
        #expect(!completion.contains("invalidateZoomBucket()"))
        let rebuild = try #require(completion.range(of: "self.rebuild(on: map)"))
        #expect(completion[completion.startIndex..<rebuild.lowerBound]
            .contains("if !self.applyMatchesIncrementally"))
    }

    @Test func newRidesWithMissingLinesNeverFallBackToAFullRebuild() throws {
        let update = try Self.body(
            Self.coordinator, from: "private func updateRides(", to: "private func prepareArrivalStrokes(")
        #expect(update.contains("prepareArrivalStrokes("))
        #expect(!update.contains("Polylines are built on a worker only from a full"))
    }

    private static let interaction = read("RailMap/Map/MapInteractionCoordinator.swift")

    @Test func tapSnapshotNeverDoesGeometryMathsOnMain() throws {
        let strokes = try Self.body(
            Self.coordinator, from: "private func drawnStrokes(", to: "private func retainRidePolylines(")
        #expect(!strokes.contains("parallelLaneCoordinates"))
        #expect(!strokes.contains("builtStrokeCoordinates"))
        #expect(!strokes.contains("drawnCoordinates("))
        #expect(strokes.contains("networkGeometry.ridePolyline(for:"))
        let provider = try Self.body(
            Self.coordinator, from: "interaction.tapSnapshotProvider = {", to: "// The budget is applied")
        #expect(provider.contains("map.tapIndex.snapshot"))
        #expect(!provider.contains("parallelLaneCoordinates"))
        #expect(!provider.contains("builtStrokeCoordinates"))
    }

    @Test func tapIndexBuildsDetachedAndIsNotKeyedToTheFrame() {
        #expect(Self.interaction.contains("Task.detached(priority: .utility)"))
        #expect(Self.interaction.contains("self.indexGeneration == generation"))
        #expect(!Self.interaction.contains("TapGeometrySignature"))
        #expect(!Self.interaction.contains("updateTapGeometry"))
        #expect(!Self.coordinator.contains("updateTapGeometry"))
    }
}
