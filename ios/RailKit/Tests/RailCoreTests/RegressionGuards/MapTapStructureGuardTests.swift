import Foundation
import Testing

/// Source-structure guards for the map tap. The rules are tested in
/// RailPresentation (`MapTapPolicyTests`); these pin that the app still uses
/// them and still wires the recognisers the way the rules assume.
@Suite("RegressionGuardMapTap")
struct RegressionGuardMapTap {
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

    private static let view = read("RailMap/Map/RailMapView.swift")
    private static let coordinator = read("RailMap/Map/RailMapCoordinator.swift")
    private static let workspace = read("RailMap/Workspace/RailWorkspaceView.swift")
    private static let host = read("RailMap/Diagnostics/AppControl/AppControlHost.swift")

    /// A tap that hits something answers on the lift, so `tap` must not wait for
    /// the double-tap recogniser; only the banked empty-map clear does.
    @Test func tapDoesNotWaitForDoubleTapButSettledTapDoes() {
        #expect(!Self.view.isEmpty)
        #expect(!Self.view.contains("tap.require(toFail: doubleTap)"))
        #expect(Self.view.contains("settledTap.require(toFail: doubleTap)"))
        #expect(Self.view.contains("settledTap.require(toFail: sensor)"))
        #expect(Self.view.contains("tap.require(toFail: sensor)"))
    }

    /// The tap reads the touch and consumes nothing, so an annotation view under
    /// the finger keeps its own touches and MapKit's selection.
    @Test func tapConsumesNoTouches() {
        #expect(Self.view.contains("tap.cancelsTouchesInView = false"))
        #expect(Self.view.contains("tap.delaysTouchesEnded = false"))
    }

    @Test func coordinatorAnswersThroughThePolicy() {
        let c = Self.coordinator
        #expect(c.contains("MapTapPolicy.answer("))
        #expect(c.contains("MapTapPolicy.doubleTapAnswer("))
        #expect(c.contains("MapTapPolicy.receives(tapCount:"))
        #expect(c.contains("func answerTap("))
        // Reaches come from the policy, not from numbers of the app's own.
        #expect(c.contains("MapTapPolicy.stationReach"))
        #expect(c.contains("MapTapPolicy.networkLineReach"))
        #expect(c.contains("RailSignpost.map.begin(\"map.tap.lines\")"))
    }

    @Test func policyReachConstantsAreNotRedefinedInTheApp() throws {
        let files = try FileManager.default.subpathsOfDirectory(
            atPath: Self.ios.appendingPathComponent("RailMap").path
        ).filter { $0.hasSuffix(".swift") }
        for file in files {
            let source = Self.read("RailMap/" + file)
            #expect(!source.contains("networkLineReach ="), "\(file) redefines networkLineReach")
            #expect(!source.contains("networkLineReach:"), "\(file) redefines networkLineReach")
            #expect(!source.contains("static let tripReach"), "\(file) redefines tripReach")
            #expect(!source.contains("static let stationReach"), "\(file) redefines stationReach")
        }
    }

    @Test func lineHitTestReusesTheDrawnBuildsAndTheSharedDistance() {
        let hit = Self.read("RailMap/Map/NetworkLineHitTest.swift")
        #expect(hit.contains("RideTapResolver.distance("))
        #expect(hit.contains("boundingMapRect"))
        let c = Self.coordinator
        #expect(c.contains("drawnLineBuilds = fitted.kept"))
        #expect(c.contains("NetworkLineHitTest.lineIDs("))
    }

    @Test func workspaceShowsTheChooserEvenWithATripCardOpen() throws {
        let w = Self.workspace
        let from = try #require(w.range(of: "private func selectFromMap("))
        let to = try #require(w.range(of: "private func selectLines(", range: from.upperBound..<w.endIndex))
        let body = w[from.lowerBound..<to.lowerBound]
        #expect(body.contains("sheet = .chooseRide(trains)"))
        #expect(!body.contains("if !journeyMenuOwnsSelection { sheet = .chooseRide(trains) }"))
        #expect(w.contains("case .line(let target):"))
        #expect(w.contains("case .chooseLine(let targets):"))
        #expect(w.contains("NetworkLineSheetView("))
    }

    @Test func tapMapRunsTheCoordinatorsAnswer() {
        #expect(Self.host.contains("case .tapMap(let target):"))
        #expect(Self.host.contains("answerTapForUITest"))
        #expect(Self.coordinator.contains("func answerTapForUITest("))
    }
}
