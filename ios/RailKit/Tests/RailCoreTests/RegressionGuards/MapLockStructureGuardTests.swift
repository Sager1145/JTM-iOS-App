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

    @Test func neighbourFramesUseTheRecencyRule() {
        #expect(Self.rendering.contains("GeometryFrameRecency("))
        #expect(!Self.rendering.contains("recentKeys"))
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
}
