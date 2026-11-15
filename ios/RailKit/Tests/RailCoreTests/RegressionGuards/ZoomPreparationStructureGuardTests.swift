import Foundation
import RailTestSupport
import Testing

/// Source-structure guards for the map-lock zoom fixes: the pure rules are
/// tested in RailPresentation; these pin that the app still uses them.
@Suite("RegressionGuardZoomPreparation")
struct RegressionGuardZoomPreparation {
    private static var coordinator: String { SourceFiles.textRecording("RailMap/Map/RailMapCoordinator.swift") }
    private static var store: String { SourceFiles.textRecording("RailMap/Infrastructure/Network/RailNetworkStore.swift") }
    private static var interaction: String { SourceFiles.textRecording("RailMap/Map/MapInteractionCoordinator.swift") }
    private static var host: String { SourceFiles.textRecording("RailMap/Diagnostics/AppControl/AppControlHost.swift") }

    private static func body(_ source: String, from start: String, to end: String) throws -> Substring {
        let from = try #require(source.range(of: start))
        let to = try #require(source.range(of: end, range: from.upperBound..<source.endIndex))
        return source[from.lowerBound..<to.lowerBound]
    }

    @Test func rideFallbacksWaitForMatchingThroughThePolicy() throws {
        #expect(Self.coordinator.contains("RideStrokeBuildPolicy.defersFallback("))
        let prepare = try Self.body(
            Self.coordinator, from: "private func prepareRideStrokes(", to: "guard !requests.isEmpty")
        #expect(prepare.contains("defersUnmatchedFallbacks: true"))
        let refs = try Self.body(
            Self.coordinator, from: "if playback?.isActive != true, let pending = pendingStrokeRefs",
            to: "networkBuildState.invalidateZoomBucket()")
        #expect(refs.contains("rideStrokePreparation?.cancel()"))
    }

    @Test func linesChangingAloneNeverCancelsAPreparation() throws {
        // A staged line set installs without cancelling; only the era path
        // (`networkFilterChanged`) installs with cancellation.
        #expect(Self.coordinator.contains("installLineSwap(result, cancelsPreparation: true)"))
        #expect(Self.coordinator.contains("installLineSwap(result, cancelsPreparation: false)"))
        #expect(Self.coordinator.contains("invalidateNetworkTemporalGeometry(cancelsPreparation: cancelsPreparation)"))
        #expect(Self.coordinator.contains("rebuildOwed(on: mapView, lineDataOnly: true)"))
        let landing = try Self.body(
            Self.coordinator, from: "let materializeInterval = RailSignpost.map.begin(\"map.materialize\")",
            to: "self.networkGeometry.storePrepared(prepared, key: key)")
        #expect(landing.contains("self.geometryEraKey == temporalContext.cacheKey"))
        #expect(landing.contains("PreparedGeometryAdmission.admitted("))
        #expect(!landing.contains("self.networkTemporalContext == temporalContext"))
    }

    @Test func aLandedLevelIsInstalledAndClearedAtCommit() throws {
        #expect(Self.coordinator.contains("GeometryZoomLevels.landingInstall("))
        #expect(Self.coordinator.contains("geometryLevelToBuild(at: zoom, on: mapView)"))
        #expect(!Self.coordinator.contains("geometryFrame(level: wantedGeometryLevel(at: zoom), on: mapView)\n                let scale"))
        let commit = try Self.body(
            Self.coordinator, from: "networkBuildState.commit(", to: "A cold display-network request")
        #expect(commit.contains("pendingInstall = nil"))
    }

    @Test func aPreparationNeverMakesItsFrameCurrent() throws {
        let beforeGate = try Self.body(
            Self.coordinator, from: "private func prepareNetworkGeometry(", to: "let gate = GeometryPreparationGate.decide(")
        #expect(!beforeGate.contains("ensureFrame("), "a waiting request must not pin its frame")
        #expect(!beforeGate.contains("beginFrame("))
        let start = try Self.body(
            Self.coordinator, from: "guard gate.start else { return false }", to: "let anchors = lineInputs")
        #expect(start.contains("networkGeometry.ensureFrame(key: key)"))
    }

    @Test func aLandingRecreatesAnEvictedFrameBeforeStoring() throws {
        let landing = try Self.body(
            Self.coordinator, from: "PreparedGeometryAdmission.admitted(",
            to: "self.networkGeometry.storePrepared(prepared, key: key)")
        #expect(landing.contains("self.networkGeometry.ensureFrame(key: key)"))
    }

    @Test func aReadyWantedLevelInstallsThroughTheOrdinaryRebuildWithNoPendingInstall() {
        #expect(Self.coordinator.contains("wantedReady: isGeometryLevelReady(wanted, zoom: zoom, on: mapView)"))
    }

    @Test func aMatchWithNewGeometryButEqualRefsStillCountsAsChanged() {
        #expect(Self.coordinator.contains("private func strokeMatchUnchanged("))
        #expect(!Self.coordinator.contains("strokeRefCache[ride.id]?.refs == pending.refs[ride.id]?.refs"))
        #expect(Self.coordinator.contains("if !self.strokeMatchingPending, let map = self.mapView"))
    }

    @Test func aChangedMatchCancelsOnlyABuildThatRequestedThatRide() {
        #expect(Self.coordinator.contains("!changedStrokeRideIDs.isDisjoint(with: rideStrokePreparationRideIDs)"))
        #expect(Self.coordinator.contains("rideStrokePreparationRideIDs = requestedRideIDs"))
    }

    @Test func memoryWarningRelievesTheMallocZone() {
        #expect(Self.coordinator.contains("malloc_zone_pressure_relief(nil, 0)"))
    }

    @Test func displayStoreSkipsIdenticalRequestsAndSignpostsItsHotPaths() {
        #expect(Self.store.contains("displayRequestMemo.shouldSkip("))
        for name in ["store.activateDisplayLines", "store.publishDisplayNetwork"] {
            #expect(Self.store.contains("\"\(name)\""), "\(name)")
        }
        for name in ["map.update", "map.refreshLineInputs"] {
            #expect(Self.coordinator.contains("\"\(name)\""), "\(name)")
        }
    }

    @Test func stationLookupMapsAreBuiltLazily() throws {
        let replace = try Self.body(
            Self.interaction, from: "func replaceStations(", to: "private func buildStationIndexesIfNeeded()")
        #expect(!replace.contains("stationsByCode[station"))
        #expect(Self.interaction.contains("buildStationIndexesIfNeeded()"))
    }

    @Test func diagnosticsWalkNeverTouchesTheUserLibraryOnCatalyst() {
        #expect(Self.host.contains("targetEnvironment(macCatalyst)"))
        #expect(Self.host.contains("routeSolveAttemptsThisLaunch"))
        #expect(!Self.host.contains("routesSolvedThisLaunch"))
    }

    @Test func strokePreparationRunsInWeightedParallelPartsInsideOnePermit() throws {
        let geometry = SourceFiles.textRecording("RailMap/Map/MapLineGeometry.swift")
        let prepare = try Self.body(geometry, from: "static func prepare(", to: "StrokeBake.prepareLines(")
        #expect(prepare.contains("async throws -> PreparedGeometry"))
        #expect(prepare.contains("RideBuildPartition.partition("))
        #expect(prepare.contains("weights:"))
        #expect(prepare.contains("min(4, ProcessInfo.processInfo.activeProcessorCount - 1)"))
        // The lines pass (`StrokeBake.prepareLines`, serial) runs after the group.
        let group = try Self.body(String(prepare), from: "RideBuildPartition.buildParts(", to: "for (index, build) in builtParts")
        #expect(!group.contains("for line in lines"))
        #expect(!group.contains("result."), "no child task may read the result")
        // The strokes interval closes on every exit, a throw from cancellation included.
        #expect(prepare.contains("defer { RailSignpost.map.end(\"map.geometry.prepare.strokes\", strokeInterval) }"))
        for name in ["map.geometry.prepare.strokes", "map.geometry.prepare.lines"] {
            #expect(geometry.contains("\"\(name)\""), "\(name)")
        }
        // The junction candidates are the engine's, in RailCore since the stroke engine moved there.
        #expect(SourceFiles.textRecording("RailKit/Sources/RailCore/Rendering/StrokeBake.swift")
            .contains("public struct JunctionCandidateIndex: Sendable"))
        // Each call sits inside the single-permit limiter.
        let coordinator = Self.coordinator
        #expect(coordinator.components(separatedBy: "try await MapLineGeometry.prepare(").count == 3)
        #expect(!coordinator.contains("try MapLineGeometry.prepare("))
        var search = coordinator.startIndex..<coordinator.endIndex
        while let call = coordinator.range(of: "try await MapLineGeometry.prepare(", range: search) {
            let lower = coordinator.index(call.lowerBound, offsetBy: -400, limitedBy: coordinator.startIndex)
                ?? coordinator.startIndex
            let before: String = String(coordinator[lower..<call.lowerBound])
            #expect(before.contains("limiter.withPermit {"), "prepare must sit inside the permit")
            search = call.upperBound..<coordinator.endIndex
        }
    }

    /// Only the idle prebuild passes `prebuild: true`; it reports as
    /// `map.geometry.prebuild`, so `map.geometry.prepare` counts foreground work.
    @Test func idlePrebuildReportsUnderItsOwnSignpost() {
        let coordinator = Self.coordinator
        #expect(coordinator.components(separatedBy: "prebuild: true").count == 2)
        let call = coordinator.range(of: "prebuild: true")
        let prebuildCall = call.map { coordinator[coordinator.startIndex..<$0.lowerBound] }
        #expect(prebuildCall?.contains("priority: .utility") == true)
        let geometry = SourceFiles.textRecording("RailMap/Map/MapLineGeometry.swift")
        #expect(geometry.contains("prebuild: Bool = false"))
        #expect(geometry.contains("\"map.geometry.prebuild\""))
    }
}
