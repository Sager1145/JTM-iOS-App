import Foundation
import Testing

/// Source-structure guards for the map-lock zoom fixes: the pure rules are
/// tested in RailPresentation; these pin that the app still uses them.
@Suite("RegressionGuardZoomPreparation")
struct RegressionGuardZoomPreparation {
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
    private static let store = read("RailMap/Infrastructure/Network/RailNetworkStore.swift")
    private static let interaction = read("RailMap/Map/MapInteractionCoordinator.swift")
    private static let host = read("RailMap/Diagnostics/AppControl/AppControlHost.swift")

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
        #expect(Self.coordinator.contains("invalidateNetworkTemporalGeometry(cancelsPreparation: networkFilterChanged)"))
        #expect(Self.coordinator.contains("lineDataOnly: lineDataOnly"))
        let landing = try Self.body(
            Self.coordinator, from: "let materializeInterval = RailSignpost.map.begin(\"map.materialize\")",
            to: "self.networkGeometry.storePrepared(prepared, key: key)")
        #expect(landing.contains("self.geometryEraKey == temporalContext.cacheKey"))
        #expect(landing.contains("PreparedGeometryAdmission.admitted("))
        #expect(!landing.contains("self.networkTemporalContext == temporalContext"))
    }

    @Test func aLandedLevelIsInstalledAndClearedAtCommit() throws {
        #expect(Self.coordinator.contains("GeometryZoomLevels.installsLanded("))
        #expect(Self.coordinator.contains("geometryLevelToBuild(at: zoom, on: mapView)"))
        #expect(!Self.coordinator.contains("geometryFrame(level: wantedGeometryLevel(at: zoom), on: mapView)\n                let scale"))
        let commit = try Self.body(
            Self.coordinator, from: "networkBuildState.commit(", to: "A cold display-network request")
        #expect(commit.contains("pendingInstallLevel = nil"))
    }

    @Test func aPreparationNeverMakesItsFrameCurrent() throws {
        let prepare = try Self.body(
            Self.coordinator, from: "private func prepareNetworkGeometry(", to: "let gate = GeometryPreparationGate.decide(")
        #expect(prepare.contains("networkGeometry.ensureFrame(key: key)"))
        #expect(!prepare.contains("beginFrame("))
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
}
