import Foundation
import Testing

@testable import RailPresentation

/// Map-lock zoom diagnosis guards: preparations must be able to finish and
/// land while the camera moves, and a residency change alone must not cancel.
struct MapLockZoomPreparationTests {
    // MARK: - F2a: lines changing alone never cancels

    @Test func lineDataOnlyChangeDoesNotCancelButEverythingElseStillDoes() {
        #expect(!MapRebuildOwedPolicy(tripsOnly: false, lineDataOnly: true).cancelsGeometryPreparation)
        #expect(MapRebuildOwedPolicy(tripsOnly: false, lineDataOnly: false).cancelsGeometryPreparation)
        #expect(!MapRebuildOwedPolicy(tripsOnly: true).cancelsGeometryPreparation)
    }

    @Test func manyResidencyChangesDuringOnePreparationGiveNoCancelAndOneFinish() {
        var ledger = GeometryPreparationLedger()
        ledger.request(key: "frame-a")
        for _ in 0..<12 {
            if MapRebuildOwedPolicy(tripsOnly: false, lineDataOnly: true).cancelsGeometryPreparation {
                ledger.cancel()
            }
            let gate = GeometryPreparationGate.decide(
                inFlightKey: ledger.inFlightKey, requestedKey: "frame-a", prebuildKey: nil, missingWork: true)
            ledger.apply(gate, key: "frame-a")
        }
        ledger.finish()
        #expect(ledger.started == 1)
        #expect(ledger.cancelled == 0)
        #expect(ledger.finished == 1)
    }

    @Test func admissionKeepsOnlyLinesWhoseInputsStillMatch() {
        let requested = ["a": 1, "b": 2, "c": 3]
        let current = ["a": 1, "b": 9, "d": 4]
        let admitted = PreparedGeometryAdmission.admitted(
            ids: ["a", "b", "c", "d"], requested: requested, current: current)
        #expect(admitted == ["a"])
    }

    // MARK: - F3a: fallback ride builds wait for matching

    @Test func fallbackWaitsOnlyWhileAnUnmatchedRideHasMatchingDue() {
        #expect(RideStrokeBuildPolicy.defersFallback(
            hasStroke: false, matchIsCurrent: false, matchingPending: true))
        #expect(!RideStrokeBuildPolicy.defersFallback(
            hasStroke: false, matchIsCurrent: false, matchingPending: false))
        #expect(!RideStrokeBuildPolicy.defersFallback(
            hasStroke: false, matchIsCurrent: true, matchingPending: true))
        #expect(!RideStrokeBuildPolicy.defersFallback(
            hasStroke: true, matchIsCurrent: false, matchingPending: true))
    }

    // MARK: - F2b: a landed level is installed

    @Test func landedLevelNearerTheCameraIsInstalled() {
        // Camera at z8.75 (level 17 nominal 8.5); installed 10 (z5); landed 14 (z7).
        #expect(GeometryZoomLevels.installsLanded(landed: 14, installed: 10, zoom: 8.75, ready: true))
        #expect(!GeometryZoomLevels.installsLanded(landed: 14, installed: 10, zoom: 8.75, ready: false))
        #expect(!GeometryZoomLevels.installsLanded(landed: 10, installed: 14, zoom: 8.75, ready: true))
        #expect(!GeometryZoomLevels.installsLanded(landed: 14, installed: 14, zoom: 8.75, ready: true))
        #expect(!GeometryZoomLevels.installsLanded(landed: 14, installed: nil, zoom: 8.75, ready: true))
    }

    /// z5 to z12.25 in quarter steps with each preparation taking three steps,
    /// the shape of the traced sweep: the wanted level has always moved on by
    /// the time a preparation lands.
    private func sweep(installsLanded: Bool) -> [Int] {
        var installed = GeometryZoomLevels.nearestLevel(zoom: 5)
        var history = [installed]
        var inFlight: (level: Int, remaining: Int)?
        // The sweep ends at z12.25; the camera then rests there while the
        // last preparations land, so the final level is a settled one.
        let sweepSteps = 29
        for step in 0..<(sweepSteps + 16) {
            let zoom = min(5.0 + Double(step) * 0.25, 12.25)
            if let flight = inFlight {
                if flight.remaining == 0 {
                    inFlight = nil
                    let wantedNow = GeometryZoomLevels.wantedLevel(zoom: zoom, installed: installed)
                    if flight.level == wantedNow
                        || (installsLanded && GeometryZoomLevels.installsLanded(
                            landed: flight.level, installed: installed, zoom: zoom, ready: true)) {
                        installed = flight.level
                        history.append(installed)
                    }
                } else {
                    inFlight = (flight.level, flight.remaining - 1)
                }
            }
            if inFlight == nil {
                let wanted = GeometryZoomLevels.wantedLevel(zoom: zoom, installed: installed)
                if wanted != installed { inFlight = (wanted, 3) }
            }
        }
        return history
    }

    @Test func aSweepMovesTheInstalledLevelForwardStepByStep() {
        let withRule = sweep(installsLanded: true)
        #expect(withRule.count > 3)
        #expect(zip(withRule, withRule.dropFirst()).allSatisfy { $0 < $1 })
        let finalWanted = GeometryZoomLevels.nearestLevel(zoom: 12.25)
        #expect(withRule.last == finalWanted)
        // Without it, "latest wins" never lands anything during the sweep.
        #expect(sweep(installsLanded: false).count < withRule.count)
    }

    // MARK: - F4a: frame count cap

    @Test func unpinnedFrameCountIsCappedWhateverTheBytes() {
        var residency = GeometryFrameResidency(byteCap: 1_000_000, maxUnpinnedFrames: 2)
        for key in ["a", "b", "c", "d", "e"] {
            _ = residency.begin(key)
            _ = residency.setBytes(1, for: key)
        }
        #expect(residency.current == "e")
        #expect(residency.unpinnedFrameCount <= 2)
        #expect(residency.order == ["c", "d", "e"])
    }

    // MARK: - F1a: identical display requests are skipped

    @Test func displayRequestMemoSkipsOnlyAnIdenticalRequest() {
        var memo = DisplayRequestMemo()
        func ask(_ x: Double, _ zoom: Double, _ epoch: Int) -> Bool {
            memo.shouldSkip(x: x, y: 2, width: 3, height: 4, cameraZoom: zoom, epoch: epoch)
        }
        let answers = [ask(1, 7, 0), ask(1, 7, 0), ask(1, 7.25, 0), ask(1, 7.25, 1), ask(2, 7.25, 1), ask(2, 7.25, 1)]
        #expect(answers == [false, true, false, false, false, true])
        memo.reset()
        #expect(ask(2, 7.25, 1) == false)
    }

    // MARK: - continuous zoom-out preparation (round 7)

    private struct ZoomOutResult {
        var installs: Int
        var coversAtStop: Bool
        var installedAtStop: Int
        var wantedAtStop: Int
        var coversAfterSettle: Bool
        var installedAfterSettle: Int
    }

    /// Model of a fast zoom-out, z11.33 to z5.33 at 0.83 zoom/s, with one
    /// preparation in flight that lands `prepareSeconds` after its request.
    /// A prepared rect covers the view down to its level's nominal zoom less
    /// the build padding; a preparation whose rect no longer covers the view
    /// is cancelled. The stop is the end of the motion; 0.35 s later the
    /// stop re-check requests the wanted level once, and it lands one
    /// preparation after that.
    private func zoomOutRun(prepareSeconds: Double) -> ZoomOutResult {
        let padding = 0.26
        let startZoom = 11.33, endZoom = 5.33, speed = 0.83, dt = 0.1
        var travel = ZoomTravel()
        var installed = GeometryZoomLevels.nearestLevel(zoom: startZoom)
        var installedFloor = GeometryZoomLevels.nominalZoom(level: installed) - padding
        var flight: (level: Int, floor: Double, lands: Double)?
        var installs = 0
        let steps = Int(((startZoom - endZoom) / speed / dt).rounded())
        for step in 0...steps {
            let now = Double(step) * dt
            let zoom = max(startZoom - speed * now, endZoom)
            travel.note(zoom: zoom, at: now)
            if let f = flight, now >= f.lands - 1e-9 {
                flight = nil
                if zoom >= f.floor {
                    installed = f.level
                    installedFloor = f.floor
                    installs += 1
                }
            }
            if let f = flight, zoom < f.floor { flight = nil }
            if flight == nil,
               let level = GeometryZoomLevels.travelLevel(
                   zoom: zoom, rate: travel.rate(at: now), prepareSeconds: prepareSeconds,
                   minimumLevel: 4) {
                let nominal = GeometryZoomLevels.nominalZoom(level: level)
                flight = (level, nominal - padding, now + prepareSeconds)
            }
        }
        let wanted = GeometryZoomLevels.wantedLevel(zoom: endZoom, installed: installed)
        let atStop = (endZoom >= installedFloor, installed)
        // The stop: the rate reads 0, so the wanted level is requested on the
        // padded rect and lands one preparation later (a travel preparation
        // still in flight keeps its own rect only if it covers and lands first).
        var settledLevel = installed, settledFloor = installedFloor
        if let f = flight, endZoom >= f.floor, f.level == wanted { settledLevel = f.level; settledFloor = f.floor }
        else if wanted != installed || endZoom < installedFloor {
            settledLevel = wanted
            settledFloor = GeometryZoomLevels.nominalZoom(level: wanted) - padding
        }
        return ZoomOutResult(
            installs: installs, coversAtStop: atStop.0, installedAtStop: atStop.1,
            wantedAtStop: wanted, coversAfterSettle: endZoom >= settledFloor,
            installedAfterSettle: settledLevel)
    }

    @Test(arguments: [1.0, 2.0, 3.0, 4.0])
    func fastZoomOutInstallsALevelAheadAndSettlesOnTheWantedOne(prepareSeconds: Double) {
        let run = zoomOutRun(prepareSeconds: prepareSeconds)
        #expect(run.installs >= 1)
        // One preparation after the stop the exact level covers the view.
        #expect(run.coversAfterSettle)
        #expect(run.installedAfterSettle == run.wantedAtStop)
    }

    /// With preparations short enough to be aimed true (up to two seconds), the
    /// installed level already covers the view at the stop and is within three
    /// levels of the wanted one. Slower preparations can be outrun by the
    /// camera: that is the documented limit, not asserted here.
    @Test(arguments: [1.0, 2.0])
    func shortPreparationsCoverTheViewAtTheStop(prepareSeconds: Double) {
        let run = zoomOutRun(prepareSeconds: prepareSeconds)
        #expect(run.coversAtStop)
        #expect(abs(run.installedAtStop - run.wantedAtStop) <= 3)
    }
}
