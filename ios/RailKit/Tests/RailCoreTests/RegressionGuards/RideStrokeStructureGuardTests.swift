import Foundation
import Testing

/// Source-structure guards for the off-main ride polyline builder (trip-loading
/// plan, unit U5). They read app sources, so they live in RailKit: the hosted
/// app tests cannot read the repository folder.
@Suite("RegressionGuardRideStrokeStructure")
struct RegressionGuardRideStrokeStructure {
    private static let coordinator: String = {
        let ios = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent() // RegressionGuards
            .deletingLastPathComponent() // RailCoreTests
            .deletingLastPathComponent() // Tests
            .deletingLastPathComponent() // RailKit
            .deletingLastPathComponent() // ios
        return (try? String(
            contentsOf: ios.appendingPathComponent("RailMap/Map/RailMapCoordinator.swift"),
            encoding: .utf8)) ?? ""
    }()

    private static func body(from start: String, to end: String) throws -> Substring {
        let source = coordinator
        let from = try #require(source.range(of: start))
        let to = try #require(source.range(of: end, range: from.upperBound..<source.endIndex))
        return source[from.lowerBound..<to.lowerBound]
    }

    @Test func ridePolylinesDoesNoGeometryWorkOnTheMainActor() throws {
        let body = try Self.body(
            from: "private func ridePolylines(", to: "/// The original main-actor miss path")
        for forbidden in ["douglasPeucker", "parallelLaneCoordinates", "builtStrokeCoordinates",
                          "ContinuousStroke.slice", "MKPolyline(coordinates"] {
            #expect(!body.contains(forbidden), "ridePolylines must not call \(forbidden)")
        }
        // The only geometry on the main actor is the selectable original path,
        // and it is gated on the main-actor mode.
        #expect(body.contains("RideStrokeBuilder.Mode.current == .mainActor"))
        #expect(body.contains("mainActorRidePolyline"))
    }

    /// The worker's requests and `ridePolylines` must key rides against the
    /// same chains: the worker is handed the strokes the rebuild is about to
    /// install, not whatever the previous rebuild left in the cache.
    @Test func theWorkerSlicesFromTheStrokesTheRebuildInstalls() throws {
        let rebuild = try Self.body(
            from: "private func rebuild(on mapView: MKMapView) {",
            to: "// A cold display-network request has no geometry")
        let selected = try #require(rebuild.range(of: "selectFrameStrokes("))
        let prepared = try #require(rebuild.range(of: "prepareRideStrokes("))
        #expect(selected.lowerBound < prepared.lowerBound)
        #expect(rebuild.contains("strokes: frameStrokes.strokes"))

        let full = Self.coordinator
        #expect(full.contains("storeStroke(stroke, for: id)"))
        // Nothing reads the previous frame's strokes to build a request.
        let prepare = try Self.body(
            from: "private func prepareRideStrokes(", to: "/// The non-selected rides' batch overlays")
        #expect(!prepare.contains("networkGeometry.stroke(for:"))
        #expect(!prepare.contains("beginFrame"), "a stale worker must not move the cache's frame")
        #expect(prepare.contains("rebuildDeferredByPlayback"))
    }

    @Test func aSegmentThatDrawsNothingIsRememberedNotRequestedAgain() throws {
        let requests = try Self.body(
            from: "private func rideStrokeRequests(", to: "/// `.offMain` only: builds the missing")
        #expect(requests.contains("rideStrokeEmptyKeys.contains(key)"))
        let prepare = try Self.body(
            from: "private func prepareRideStrokes(", to: "/// The non-selected rides' batch overlays")
        #expect(prepare.contains("rideStrokeEmptyKeys.formUnion(output.empty)"))
    }

    @Test func replacedChainBuildsDropTheStrokeMemo() throws {
        let source = Self.coordinator
        let store = try #require(source.range(of: "networkGeometry.storePrepared(prepared, key: key)"))
        let tail = source[store.upperBound...].prefix(400)
        #expect(tail.contains("resetRideStrokeCaches()"))
        let retain = try #require(source.range(of: "networkGeometry.retainLineBuilds(withIDs: retainedIDs)"))
        #expect(source[retain.upperBound...].prefix(120).contains("resetRideStrokeCaches()"))
    }
}
