import Foundation
import Testing

/// Source-structure guards for the off-main ride polyline builder (trip-loading
/// plan, unit U5). They read app sources, so they live in RailKit: the hosted
/// app tests cannot read the repository folder.
@Suite("RegressionGuardRideStrokeStructure")
struct RegressionGuardRideStrokeStructure {
    private static let ios: URL = {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent() // RegressionGuards
            .deletingLastPathComponent() // RailCoreTests
            .deletingLastPathComponent() // Tests
            .deletingLastPathComponent() // RailKit
            .deletingLastPathComponent() // ios
    }()

    private static let coordinator: String = {
        (try? String(
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
            from: "private func ridePolylines(", to: "/// What one rebuild installs as this frame")
        for forbidden in ["douglasPeucker", "parallelLaneCoordinates", "builtStrokeCoordinates",
                          "ContinuousStroke.slice", "MKPolyline(coordinates"] {
            #expect(!body.contains(forbidden), "ridePolylines must not call \(forbidden)")
        }
        // No synchronous main-actor path survives.
        #expect(!body.contains("mainActorRidePolyline"))
    }

    @Test func thereIsNoMainThreadStrokePathOrEnvSwitch() throws {
        let builder = try String(
            contentsOf: Self.ios.appendingPathComponent("RailMap/Map/RideStrokeBuilder.swift"),
            encoding: .utf8)
        let full = Self.coordinator
        for source in [builder, full] {
            #expect(!source.contains("RAILMAP_RIDE_STROKES"))
            #expect(!source.contains("RideStrokeBuilder.Mode"))
            #expect(!source.contains("mainActorRidePolyline"))
        }
        #expect(!builder.contains("enum Mode"))
        // Worker results are applied on main only for the current generation.
        let prepare = try Self.body(
            from: "private func prepareRideStrokes(", to: "/// The non-selected rides' batch overlays")
        #expect(prepare.contains("Task.detached"))
        #expect(prepare.contains("self.rideStrokePreparationID == requestID"))
    }

    /// Trips and lines share one area: strokes are prepared and selected with
    /// the trip area, never the smaller build rect.
    @Test func lineStrokesUseTheTripArea() throws {
        let full = Self.coordinator
        #expect(!full.contains("insetBy(dx: -256"))
        let prep = try Self.body(
            from: "private func prepareNetworkGeometry(", to: "let byID = Dictionary(")
        #expect(prep.contains("NetworkLOD.tripArea("))
        let missing = try Self.body(
            from: "let missingStrokes = needed.compactMap", to: "let gate = ")
        #expect(missing.contains("intersects(rideRect)"))
        #expect(!missing.contains("intersects(buildRect)"))
        let select = try Self.body(
            from: "for id in result.neededLineIDs where result.strokes[id] == nil",
            to: "return result")
        #expect(select.contains("intersects(rideBuildRect)"))
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
            from: "private func rideStrokeRequests(", to: "/// Builds the missing")
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
