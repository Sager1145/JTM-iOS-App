import Foundation
import RailTestSupport
import Testing

/// Source-structure guards for the map tap. The rules are tested in
/// RailPresentation (`MapTapPolicyTests`); these pin that the app still uses
/// them and still wires the recognisers the way the rules assume.
@Suite("RegressionGuardMapTap")
struct RegressionGuardMapTap {
    private static let view = SourceFiles.textRecording("RailMap/Map/RailMapView.swift")
    private static let coordinator = SourceFiles.textRecording("RailMap/Map/RailMapCoordinator.swift")
    private static let workspace = SourceFiles.textRecording("RailMap/Workspace/RailWorkspaceView.swift")
    private static let host = SourceFiles.textRecording("RailMap/Diagnostics/AppControl/AppControlHost.swift")

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
            atPath: SourceFiles.ios.appendingPathComponent("RailMap").path
        ).filter { $0.hasSuffix(".swift") }
        for file in files {
            let source = SourceFiles.textRecording("RailMap/" + file)
            #expect(!source.contains("networkLineReach ="), "\(file) redefines networkLineReach")
            #expect(!source.contains("networkLineReach:"), "\(file) redefines networkLineReach")
            #expect(!source.contains("static let tripReach"), "\(file) redefines tripReach")
            #expect(!source.contains("static let stationReach"), "\(file) redefines stationReach")
        }
    }

    @Test func lineHitTestReusesTheDrawnBuildsAndTheSharedDistance() {
        let hit = SourceFiles.textRecording("RailMap/Map/NetworkLineHitTest.swift")
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
        #expect(Self.host.contains("case .tapMap(let target, let doubleTap):"))
        #expect(Self.host.contains("answerTapForUITest"))
        #expect(Self.coordinator.contains("func answerTapForUITest("))
    }

    /// A double tap selects no annotation (MapKit selects only after its double-tap
    /// recogniser fails) and reports whether it dropped a banked answer.
    @Test func tapMapDoubleTapSelectsNothingAndReportsCancellation() throws {
        let c = Self.coordinator
        let from = try #require(c.range(of: "func answerTapForUITest("))
        let body = c[from.upperBound...].prefix(1400)
        #expect(body.contains("if !doubleTap, outcome.answer == .annotation"))
        #expect(body.contains("report.cancelledByDoubleTap = bankedTap != nil"))
        #expect(Self.host.contains("\"cancelledByDoubleTap\""))
    }

    private static let hitTest = SourceFiles.textRecording("RailMap/Map/NetworkLineHitTest.swift")

    /// A trip dot under the finger is its own trip's tap, whatever else passes.
    @Test func tripDotOwnsItsTapAndSkipsLineReach() {
        let c = Self.coordinator
        #expect(c.contains("measured.hits.tripIDsInReach = [dot.rideID]"))
        #expect(c.contains("!measured.hits.selectedTripStationDot, !dotOwnsTap"))
        #expect(!c.contains("measured.hits.tripIDsInReach.append(dot.rideID)"))
    }

    /// The station reach is measured from the bead's coordinate, over views
    /// somebody can see and touch.
    @Test func stationReachMeasuresTheBeadAndSkipsInvisibleViews() throws {
        let c = Self.coordinator
        let from = try #require(c.range(of: "private func stationAnnotation("))
        let to = try #require(c.range(of: "private func networkLines(", range: from.upperBound..<c.endIndex))
        let body = c[from.lowerBound..<to.lowerBound]
        #expect(body.contains("mapView.convert(annotation.coordinate, toPointTo: mapView)"))
        #expect(!body.contains("convert(view.center"))
        #expect(body.contains("!view.isHidden"))
        #expect(body.contains("view.alpha >= 0.01"))
        #expect(body.contains("view.isUserInteractionEnabled"))
    }

    /// Over a panel card a double tap near a station or line only zooms: the
    /// rule is the policy's, the coordinator banks and the double tap cancels.
    @Test func doubleTapOverPanelCardCancelsBankedStationOrLine() throws {
        let c = Self.coordinator
        #expect(c.contains("MapTapPolicy.defersAnswer("))
        #expect(c.contains("controller?.mapCardHost"))
        #expect(c.contains("private func answerOrBank("))
        let from = try #require(c.range(of: "func answerDoubleTap("))
        #expect(c[from.upperBound...].prefix(200).contains("bankedTap = nil"))
        let handler = try #require(c.range(of: "@objc func handleMapDoubleTap("))
        #expect(c[handler.upperBound...].prefix(300).contains("answerDoubleTap("))
        // The station and line answers go through the bank, not straight to the card.
        let tap = try #require(c.range(of: "func answerTap("))
        let end = try #require(c.range(of: "private func answerOrBank(", range: tap.upperBound..<c.endIndex))
        let body = c[tap.lowerBound..<end.lowerBound]
        #expect(!body.contains("onSelectStation("))
        #expect(!body.contains("onSelectLines("))
        // tapMap runs the same two answers.
        #expect(c.contains("answerDoubleTap(at: point, on: mapView)"))
        #expect(Self.workspace.contains("controller.mapCardHost = host"))
        #expect(Self.host.contains("doubleTap"))
    }

    /// A tap-then-drag zoom must not deliver a clear banked by its first tap.
    @Test func manipulationBeginDropsABankedClear() throws {
        let c = Self.coordinator
        let from = try #require(c.range(of: "@objc func handleManipulation("))
        let began = try #require(c.range(of: "case .began:", range: from.upperBound..<c.endIndex))
        #expect(c[began.upperBound...].prefix(300).contains("bankedTap = nil"))
    }

    /// Every network polyline MapKit draws answers a tap, fallbacks and
    /// withheld runs included, and a pitched camera still answers.
    @Test func lineHitTestCoversEveryDrawnPolyline() {
        let c = Self.coordinator
        #expect(c.contains("drawnExtraPolylines = extraPolylines"))
        #expect(c.contains("extraPolylines[build.line.lineID, default: []].append(contentsOf: kept)"))
        #expect(c.contains("extraPolylines[build.line.lineID, default: []].append(polyline)"))
        #expect(c.contains("extra: drawnExtraPolylines"))
        #expect(Self.hitTest.contains("extra[build.line.lineID]?.forEach(scan)"))
        #expect(c.contains("let local = hypot(b.x - a.x, b.y - a.y) / 10"))
    }

    /// A tap on a mounted network bead answers at once; `tapMap` selects what
    /// MapKit would for the other annotations.
    @Test func beadAnswersAtOnceAndTapMapCoversAnnotations() {
        let c = Self.coordinator
        #expect(c.contains("measured.annotation as? StationAnnotation"))
        #expect(c.contains("annotationUnderTap = measured.annotation"))
        #expect(c.contains("self.mapView(mapView, didSelect: annotation)"))
        #expect(c.contains("interaction.beginTouch()\n                let outcome = answerTap("))
    }

    /// A chooser replacing an open card must keep the card's selection lease,
    /// and a panel card replacing a system sheet must not run its cleanup.
    @Test func replacedSystemSheetKeepsTheSelectionLease() throws {
        let w = Self.workspace
        let from = try #require(w.range(of: "private func sheetDidDismiss()"))
        let body = w[from.lowerBound...].prefix(1500)
        #expect(body.contains("if panelSheet != nil { return }"))
        #expect(body.contains("if case .chooseRide = sheet { return }"))
        #expect(body.contains("restoreSelection("))
    }

    /// The three map-tap handlers answer through the policy and keep no
    /// inline lease or preview guard of their own.
    @Test func tapHandlersAnswerThroughMapTapAnswer() {
        let w = Self.workspace
        #expect(w.contains("WorkspaceSurfacePolicy.mapTapAnswer("))
        for name in ["selectStation", "selectFromMap", "selectLines"] {
            guard let start = w.range(of: "private func \(name)(") else {
                Issue.record("\(name) missing"); continue
            }
            let rest = w[start.upperBound...]
            let end = rest.range(of: "\n    }\n")?.lowerBound ?? rest.endIndex
            let body = String(rest[..<end])
            #expect(body.contains("mapTapAnswer("), "\(name) must call mapTapAnswer")
            #expect(!body.contains("journeyMenuOwnsSelection"), "\(name) holds a bare lease guard")
            #expect(!body.contains("linePreview == nil"), "\(name) holds a bare preview guard")
        }
        #expect(w.contains("onSelectStation: { selectStation($0) }"))
    }

    /// A tap that hit rides is never empty (the line preview is a ride), the
    /// panel's nested-surface flag reaches the policy, Esc steps back first,
    /// and the trip chooser swaps directly in the panel.
    @Test func panelTapAndEscRulesStayWired() throws {
        let w = Self.workspace
        let from = try #require(w.range(of: "private func selectFromMap("))
        let body = String(w[from.upperBound...].prefix(900))
        #expect(body.contains("if trains.isEmpty, !ids.isEmpty { return }"))
        #expect(w.contains("nestedSurfaceUp: panelNestedSurface"))
        #expect(w.contains("if let back = panelBackStep(for: panelSheet) { back() } else { self.sheet = nil }"))
        let chooser = try #require(w.range(of: "case .chooseRide(let trains):"))
        let chooserBody = String(w[chooser.upperBound...].prefix(700))
        #expect(chooserBody.contains("if host == .panel"))
    }
}
