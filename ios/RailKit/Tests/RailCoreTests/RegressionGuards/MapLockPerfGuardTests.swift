import Foundation
import Testing

/// Source-structure guards for the map-lock run 3 fixes: the pure rules have
/// their own tests; these pin that the app still uses them.
@Suite("RegressionGuardMapLockPerf")
struct RegressionGuardMapLockPerf {
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
    private static let geometry = read("RailMap/Map/MapLineGeometry.swift")
    private static let stroke = read("RailKit/Sources/RailCore/Rendering/ContinuousStroke.swift")
    private static let builder = read("RailMap/Map/RideStrokeBuilder.swift")
    private static let host = read("RailMap/Diagnostics/AppControl/AppControlHost.swift")
    private static let appControl = read("tools/app-control.py")

    private static func body(_ source: String, from start: String, to end: String) throws -> Substring {
        let from = try #require(source.range(of: start))
        let to = try #require(source.range(of: end, range: from.upperBound..<source.endIndex))
        return source[from.lowerBound..<to.lowerBound]
    }

    // Stroke engine: no per-element linear measure scans.
    @Test func strokeEngineHasNoLinearMeasureScans() {
        let scans = Self.stroke.components(separatedBy: "\n").filter {
            $0.contains("abs($0 - ") && $0.contains("< 1e-9") && $0.contains("contains")
        }
        // Three remain on purpose: MeasureMatcher's doc statement, the per-source-corner
        // check, and classifyCornerMeasures' non-monotonic fallback (its monotone fast
        // path is already a sorted sweep). The per-vertex scans are gone.
        #expect(scans.count <= 3, "linear measure scans came back: \(scans)")
        #expect(Self.stroke.contains("MeasureMatcher(cornerMeasures)"))
        #expect(Self.stroke.contains("MeasureMatcher(anchorMeasures)"))
        #expect(Self.stroke.contains("drawnAnchorIndices"))
    }

    // Junction index: the coordinator's index is passed in, never rebuilt per preparation.
    @Test func preparationReusesTheCoordinatorsJunctionIndex() throws {
        #expect(!Self.geometry.contains("JunctionCandidateIndex(allLines"))
        #expect(Self.geometry.contains("JunctionCandidateIndex(index: junctionIndex, lines: allLines)"))
        #expect(Self.coordinator.components(separatedBy: "junctionIndex: junctionIndex,").count - 1 == 2)
    }

    // Landing rule: decided by the pure policy on the prepared rect.
    @Test func landingInstallsThroughThePolicyOnThePreparedRect() throws {
        let landing = try Self.body(
            Self.coordinator, from: "let landedZoom = MapProjection.zoomLevel(of: mapView)",
            to: "self.noteRebuildTrigger(.geometryPrepared)")
        #expect(landing.contains("GeometryZoomLevels.landingInstall("))
        #expect(landing.contains("buildRect.contains(mapView.visibleMapRect)"))
        #expect(landing.contains("self.pendingInstallRect = buildRect"))
        #expect(Self.coordinator.contains("pendingInstallRect ?? movingBuildRect"))
        #expect(Self.coordinator.contains("noteRebuildTrigger(.wantedLevelFollowUp)"))
    }

    // Matching and ride builds.
    @Test func matchingUsesTheScheduleAndALoadsFinalPublishIsNotDebounced() throws {
        let request = try Self.body(
            Self.coordinator, from: "private func requestStrokeReferences() {",
            to: "private func startStrokeMatching(")
        #expect(request.contains("MatchingSchedule.decide("))
        #expect(request.contains("loadJustFinished: ridesLoadJustFinished"))
        #expect(Self.coordinator.contains("ridesLoadJustFinished = true"))
        #expect(!Self.coordinator.contains("matchingDebounce:"))
    }

    @Test func rideStrokesBuildInPartsAndMergeInRequestOrder() {
        #expect(Self.builder.contains("RideBuildPartition.partition("))
        #expect(Self.builder.contains("sorted { $0.index < $1.index }"))
    }

    // Memory.
    @Test func memoryIsHandedBackOnceAfterALandingWhenIdle() throws {
        #expect(Self.coordinator.contains("self.scheduleMemoryRelief()"))
        let relief = try Self.body(
            Self.coordinator, from: "private func scheduleMemoryRelief() {",
            to: "/// `duringGesture` is the mid-pinch level swap")
        #expect(relief.contains("malloc_zone_pressure_relief(nil, 0)"))
        #expect(relief.contains("self.isManipulating"))
    }

    // Line inputs.
    @Test func lineInputsReuseUnchangedJunctionLines() {
        #expect(Self.coordinator.contains("junctionLineMemo[line.id]"))
    }

    // State field and harness.
    @Test func stateReportsGeometryLevelsAndBuildCommit() {
        #expect(Self.host.contains("\"geometryLevel\": Self.geometryLevel()"))
        #expect(Self.host.contains("\"build\": [\"commit\": optional(Self.buildCommit())]"))
        for key in ["installed", "wanted", "preparing", "pending", "cameraZoom", "sinceInstallMs"] {
            #expect(Self.host.contains("\"\(key)\""), "missing \(key)")
        }
        #expect(Self.coordinator.contains("\"map.geometry.prep.started\", drawCounters.preparations.started, frame.bucket"))
    }

    @Test func eachWorktreeBuildsIntoItsOwnFolderAndLaunchChecksTheCommit() {
        #expect(Self.appControl.contains("hashlib.sha1(str(REPO)"))
        #expect(Self.appControl.contains("JTM_BUILD_COMMIT="))
        #expect(Self.appControl.contains("commit_mismatch(stamped, head_commit())"))
    }
}
