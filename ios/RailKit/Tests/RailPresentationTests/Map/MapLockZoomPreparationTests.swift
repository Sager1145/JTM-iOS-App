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
                inFlightKey: ledger.inFlightKey, requestedKey: "frame-a", missingWork: true)
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
}
