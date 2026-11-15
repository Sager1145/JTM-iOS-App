import Foundation
import RailTestSupport
import Testing

/// Source guards for the three map-side fixes that let line drawing finish
/// during a trip load. They read app sources, so they live in RailKit.
@Suite("RegressionGuardMapDrawCompletion")
struct RegressionGuardMapDrawCompletion {
    private static func body(of text: String, from start: String, to end: String) throws -> Substring {
        let from = try #require(text.range(of: start))
        let to = try #require(text.range(of: end, range: from.upperBound..<text.endIndex))
        return text[from.lowerBound..<to.lowerBound]
    }

    /// Fix 1: only the policy decides whether a preparation is cancelled, and
    /// the trips-only fallback passes the flag.
    @Test func aTripsOnlyFallbackDoesNotCancelThePreparation() throws {
        let coordinator = SourceFiles.textRecording("RailMap/Map/RailMapCoordinator.swift")
        let owed = try Self.body(
            of: coordinator, from: "private func rebuildOwed(",
            to: "/// Everything about one ride that changes what is DRAWN")
        #expect(owed.contains("MapRebuildOwedPolicy(tripsOnly: tripsOnly, lineDataOnly: lineDataOnly)"))
        #expect(owed.contains("if policy.cancelsGeometryPreparation { cancelGeometryPreparation() }"))
        #expect(!owed.contains("\n                cancelGeometryPreparation()"))
        #expect(coordinator.contains("rebuildOwed(on: mapView, tripsOnly: ridesOnly)"))
    }

    /// Fix 3: a finished trip polyline is named by its line and that line's
    /// stroke generation, and the cache is never emptied wholesale again.
    @Test func theTripLineCacheIsKeyedByLineAndGenerationAndNeverEmptiedWholesale() {
        let cache = SourceFiles.textRecording("RailMap/Map/MapNetworkRendering.swift")
        let coordinator = SourceFiles.textRecording("RailMap/Map/RailMapCoordinator.swift")
        #expect(!cache.contains("clearRidePolylines"))
        #expect(!coordinator.contains("clearRidePolylines"))
        #expect(cache.contains("[RideLineCacheKey: MKPolyline]"))
        #expect(coordinator.contains("residentStrokeGeneration(for: $0.chainID)"))
        #expect(!coordinator.contains("ridePolylineKey("))
    }

    /// Fix 4: no tap-index prebuild while loading, and the detached build is
    /// reached by cancellation.
    @Test func theTapIndexIsNotPrebuiltWhileLoadingAndTheBuildIsCancellable() {
        let interaction = SourceFiles.textRecording("RailMap/Map/MapInteractionCoordinator.swift")
        #expect(interaction.contains("TapIndexPrebuildPolicy.mayPrebuild("))
        #expect(interaction.contains("withTaskCancellationHandler"))
        #expect(interaction.contains("worker.cancel()"))
        let view = SourceFiles.textRecording("RailMap/Map/RailMapView.swift")
        #expect(view.contains("ridesLoadingChanged(ridesAreLoading)"))
    }
}
