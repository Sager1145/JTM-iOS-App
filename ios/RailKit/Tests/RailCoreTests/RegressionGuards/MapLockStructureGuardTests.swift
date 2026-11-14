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

    @Test func cameraMovesNeverCancelAPreparation() throws {
        let handler = try Self.body(
            Self.coordinator, from: "func mapViewDidChangeVisibleRegion(",
            to: "scheduleCameraRebuild(on: mapView)")
        #expect(!handler.contains("cancelGeometryPreparation()"))
        let prepare = try Self.body(
            Self.coordinator, from: "let temporalContext = networkTemporalContext",
            to: "geometryPreparation = Task")
        #expect(!prepare.contains("cancelGeometryPreparation()"))
    }

    @Test func ridesOnlyPublishUpdatesTheOverlayProbe() throws {
        let publish = try Self.body(
            Self.coordinator, from: "private func publishRidesOnlyUpdate(",
            to: "DispatchQueue.main.async { [onRender] in onRender(stats) }")
        #expect(publish.contains("MapRenderProbe.rideOverlays = rideOverlays"))
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
            Self.coordinator, from: "private func refreshLineInputs(",
            to: "var trueGenerations")
        #expect(refresh.contains("cancelNeighbourPrebuild()"))
    }

    @Test func aPrebuildOfTheRequestedFrameIsAdoptedAndInstalledOnLanding() throws {
        // The wanted-set check keeps the level the camera reached.
        let moved = try Self.body(
            Self.coordinator, from: "private func cancelNeighbourPrebuildIfWantedSetMoved(",
            to: "/// While idle, builds ONE neighbour")
        #expect(moved.contains("GeometryZoomLevels.keepsNeighbourPrebuild("))
        // The foreground request adopts instead of cancelling, and returns
        // before the unconditional cancel.
        let prepare = try Self.body(
            Self.coordinator, from: "let gate = GeometryPreparationGate.decide(",
            to: "guard gate.start else { return false }")
        let adopt = try #require(prepare.range(of: "if gate.adoptPrebuild {"))
        let cancel = try #require(prepare.range(of: "cancelNeighbourPrebuild()"))
        #expect(adopt.lowerBound < cancel.lowerBound)
        #expect(prepare.contains("prebuildKey: neighbourPrebuildKey"))
        // The prebuild's landing rebuilds, only behind the adoption check.
        let landing = try Self.body(
            Self.coordinator, from: "_ = self.networkGeometry.storePrepared(prepared, key: key)",
            to: "private func prepareNetworkGeometry(")
        let check = try #require(landing.range(of: "self.adoptedPrebuildKey == key"))
        let rebuild = try #require(landing.range(of: "self.rebuild(on: mapView)"))
        #expect(check.lowerBound < rebuild.lowerBound)
        // Every exit releases an adoption.
        let task = try Self.body(
            Self.coordinator, from: "neighbourPrebuild = Task { @MainActor",
            to: "for level in target.levels {")
        #expect(task.contains("defer {"))
        #expect(task.contains("releaseAdoptedPrebuild()"))
    }

    @Test func matchingSignpostsSeparateWaitingFromWorkAndApply() throws {
        // `map.matching` is waiting time; the work and the main-thread apply have their own.
        #expect(Self.coordinator.contains("RailSignpost.map.begin(\"map.matching\")"))
        let work = try Self.body(
            Self.coordinator, from: "try await limiter.withPermit {\n                        // The matching itself",
            to: "let index: StrokeRide.Index")
        #expect(work.contains("RailSignpost.map.begin(\"map.matching.work\")"))
        #expect(work.contains("RailSignpost.map.end(\"map.matching.work\""))
        #expect(Self.coordinator.contains("RailSignpost.map.begin(\"map.matching.apply\")"))
        #expect(Self.coordinator.contains("RailSignpost.map.end(\"map.matching.apply\""))
    }

    @Test func theIdlePrebuildUsesTheRectTheNextLevelWillUse() throws {
        let prebuild = try Self.body(
            Self.coordinator, from: "private func scheduleNeighbourPrebuild(",
            to: "neighbourPrebuild = Task")
        #expect(prebuild.contains("GeometryZoomLevels.prebuildVisibleRect("))
        #expect(prebuild.contains(".union(networkBuildState.builtRect)"))
    }

    @Test func theLineSetSwapRunsOffTheMainActorAndInstallsInOneTurn() throws {
        // No junction index work on the coordinator any more; the worker does it.
        #expect(!Self.coordinator.contains("junctionIndex.update("))
        #expect(Self.coordinator.contains("\"map.lineSwap.compute\""))
        let compute = try Self.body(
            Self.coordinator, from: "private static func computeLineSwap(",
            to: "private func swapInput(")
        #expect(compute.contains("input.state.advanced(to: junctionLines)"))
        #expect(compute.contains("Task.isCancelled"))
        // Installing is one turn: no suspension point anywhere in it.
        let apply = try Self.body(
            Self.coordinator, from: "private func applyLineSwap(",
            to: "/// Revalidate only the inputs a line build actually reads.")
        #expect(!apply.contains("await "))
        #expect(!apply.contains("Task {"))
        let order = ["lines = result.lines", "junctionState = result.state",
                     "linesGeneration += 1", "retainDisplayChains(", "invalidateNetworkTemporalGeometry(",
                     "refreshLineInputs(newTruth: result.inputs)"]
        var cursor = apply.startIndex
        for needle in order {
            let found = try #require(apply.range(of: needle, range: cursor..<apply.endIndex), "\(needle)")
            cursor = found.upperBound
        }
        // A landed result is held during a gesture and installed when it ends.
        #expect(Self.coordinator.contains("duringGesture: isManipulating"))
        let settle = try Self.body(
            Self.coordinator, from: "private func scheduleCameraRebuild(", to: "var preservesCameraDuringResize")
        #expect(settle.contains("self.applyHeldLineSwap()"))
    }

    @Test func updateStagesLineSetsInsteadOfInstallingThemExceptOnAnEraChange() throws {
        let update = try Self.body(
            Self.coordinator, from: "let swapChanged = linesChanged || stationsChanged",
            to: "let selectedRide = rides.first")
        #expect(update.contains("let appliesSwapNow = swapChanged && networkFilterChanged"))
        #expect(update.contains("lineSwapSchedule.appliedSynchronously()"))
        #expect(update.contains("stageLineSwap(lines: lines, stations: stations)"))
        #expect(!update.contains("self.lines = lines"))
        // The plan reports line changes only when they were installed here.
        #expect(Self.coordinator.contains("linesChanged: linesChanged && appliesSwapNow"))
        // Incoming data is compared against the newest staged set.
        #expect(Self.coordinator.contains("pendingLineSwap?.lines ?? self.lines"))
    }

    @Test func reviewFixesStayInPlace() throws {
        // A running or adopted prebuild is not restarted by the camera moving.
        let prebuild = try Self.body(
            Self.coordinator, from: "private func scheduleNeighbourPrebuild(", to: "neighbourPrebuild = Task")
        #expect(prebuild.contains("guard adoptedPrebuildKey == nil else { return }"))
        #expect(prebuild.contains("GeometryZoomLevels.prebuildStillCovers("))
        // A swap held during a gesture is applied by the settle rebuild.
        let landing = try Self.body(
            Self.coordinator, from: "private func landLineSwap(", to: "private func applyHeldLineSwap(")
        let hold = try #require(landing.range(of: "case .hold:"))
        #expect(landing[hold.upperBound...].contains("rebuildDeferredByGesture = true"))
        // Arriving chains are admitted before the worker joins them.
        let start = try Self.body(
            Self.coordinator, from: "private func startLineSwap(", to: "private func landLineSwap(")
        #expect(start.contains("admitDisplayChains("))
        // Tear-down makes an in-flight result stale.
        let tear = try Self.body(
            Self.coordinator, from: "lineSwapTask?.cancel()\n                lineSwapTask = nil\n                heldLineSwap = nil",
            to: "memoryReliefTask?.cancel()")
        #expect(tear.contains("lineSwapSchedule.appliedSynchronously()"))
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
            Self.coordinator, from: "private func rebuild(",
            to: "/// The trip-line cache key of one segment"))
        #expect(rebuild.components(separatedBy: "buildMarkers(").count == 2)
        #expect(!rebuild.contains("annotationReconciler.apply("))
        let deferred = try Self.body(rebuild, from: "case .deferred:", to: "markerPassDebt.noteDeferred()")
        #expect(!deferred.contains("buildMarkers("))
        let full = try Self.body(rebuild, from: "case .full:", to: "case .deferred:")
        #expect(full.contains("buildMarkers("))
        #expect(rebuild.contains("MarkerPassDebt.pass(deferMarkers: deferMarkers)"))
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

    @Test func tapIndexBuildsDetachedAndFollowsTheInstalledLevel() throws {
        #expect(Self.interaction.contains("Task.detached(priority: .utility)"))
        #expect(Self.interaction.contains("self.indexGeneration == generation"))
        #expect(!Self.interaction.contains("TapGeometrySignature"))
        #expect(!Self.interaction.contains("updateTapGeometry"))
        #expect(!Self.coordinator.contains("updateTapGeometry"))
        // Lane offsets scale with the level: a level change re-snapshots.
        let install = try Self.body(
            Self.coordinator, from: "currentGeometryFrame?.bucket != geometryFrame.bucket",
            to: "currentGeometryFrame = geometryFrame")
        #expect(install.contains("interaction.invalidateRideGeometry()"))
    }

    @Test func arrivalStrokesRecordEmptyResultsAgainstTheirFrame() throws {
        let arrival = try Self.body(
            Self.coordinator, from: "private func prepareArrivalStrokes(",
            to: "private var arrivalStrokePreparation:")
        #expect(arrival.contains("rideStrokeEmptyFrameKey = strokeFrame.key"))
        #expect(arrival.contains("arrivalStrokePreparationID == requestID"))
        let reset = try Self.body(
            Self.coordinator, from: "private func resetRideStrokeCaches()", to: "/// The worker requests")
        #expect(reset.contains("arrivalStrokePreparationID = UUID()"))
    }

    @Test func tripDotsStayAnnotationsWhileVoiceOverRuns() {
        #expect(Self.coordinator.contains("!hasSelection && !UIAccessibility.isVoiceOverRunning"))
        #expect(Self.coordinator.contains("UIAccessibility.voiceOverStatusDidChangeNotification"))
        #expect(!Self.coordinator.contains("drawsInOverlay: !hasSelection"))
    }

    @Test func onlyTheLevelSwapDefersTheMarkerPass() throws {
        let swap = try Self.body(
            Self.coordinator, from: "noteRebuildTrigger(.levelSwapped)", to: "private var lastGestureSwapAttempt")
        #expect(swap.contains("deferMarkers: true"))
        let extend = try Self.body(
            Self.coordinator, from: "noteRebuildTrigger(.movingExtended)", to: "// MARK: neighbour prebuild")
        #expect(!extend.contains("deferMarkers: true"))
    }

    @Test func theDebtPassRestylesBeforeTheFullLabelPass() throws {
        let settle = try Self.body(
            Self.coordinator, from: "if self.markerPassDebt.isOwed {", to: "_ = self.runLabelPass(on: mapView, moving: false)")
        let restyle = try #require(settle.range(of: "self.restyle(on: mapView)"))
        let full = try #require(settle.range(of: "fullPass: true"))
        #expect(restyle.lowerBound < full.lowerBound)
    }

    @Test func stallAttributionSignpostsExist() throws {
        for name in ["map.markers.phase", "map.restyle", "map.lineSwap.apply", "map.geometry.request",
                     "map.regionTick", "map.cameraSettled"] {
            #expect(Self.coordinator.contains("\"\(name)\""), "\(name)")
        }
        let phase = try Self.body(
            Self.coordinator, from: "func finishMarkerPhase(", to: "// Reuse an installed dot's position")
        #expect(phase.contains("RailSignpost.map.mark(\"map.markers.phase\""))
    }
}
