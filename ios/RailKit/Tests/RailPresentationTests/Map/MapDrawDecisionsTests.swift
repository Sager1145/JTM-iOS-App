import RailPresentation
import Testing

struct MapDrawDecisionsTests {
    // MARK: - rebuild policy and the preparation ledger

    /// One arrival that owes a rebuild, run through the same two decisions the
    /// coordinator makes: `rebuildOwed` (policy cancel) then
    /// `prepareNetworkGeometry` (gate).
    private func arrive(
        _ ledger: inout GeometryPreparationLedger, tripsOnly: Bool, key: String, missingWork: Bool = true
    ) -> GeometryPreparationGate.Decision {
        if MapRebuildOwedPolicy(tripsOnly: tripsOnly).cancelsGeometryPreparation { ledger.cancel() }
        let d = GeometryPreparationGate.decide(
            inFlightKey: ledger.inFlightKey, requestedKey: key, missingWork: missingWork)
        ledger.apply(d, key: key)
        return d
    }

    @Test func aTripsOnlyChangeNeverCancelsAPreparation() {
        var ledger = GeometryPreparationLedger()
        ledger.request(key: "frame-a")
        _ = arrive(&ledger, tripsOnly: true, key: "frame-a")
        #expect(ledger.cancelled == 0)
        #expect(ledger.started == 1)
        #expect(ledger.isInFlight)
    }

    @Test func anythingElseThatOwesARebuildCancelsAndRestarts() {
        var ledger = GeometryPreparationLedger()
        ledger.request(key: "frame-a")
        _ = arrive(&ledger, tripsOnly: false, key: "frame-a")
        #expect(ledger.cancelled == 1)
        #expect(ledger.started == 2)
    }

    @Test func aRequestForAnotherFrameLeavesThePreparationRunning() {
        var ledger = GeometryPreparationLedger()
        ledger.request(key: "frame-a")
        let d = arrive(&ledger, tripsOnly: true, key: "frame-b")
        #expect(!d.cancelInFlight && !d.start && !d.drawNow)
        #expect(ledger.cancelled == 0)
        #expect(ledger.inFlightKey == "frame-a")
    }

    /// A camera sweep asks for a new level every 1.2 s while one preparation
    /// takes 2.5 s. The old rule cancelled each, so none finished.
    @Test func aZoomSweepFinishesPreparationsInsteadOfCancellingEachOne() {
        var ledger = GeometryPreparationLedger()
        var busyUntil = 0.0
        var level = 0
        var now = 0.0
        for _ in 0..<40 {
            if ledger.isInFlight, now >= busyUntil { ledger.finish() }
            level += 1
            let d = GeometryPreparationGate.decide(
                inFlightKey: ledger.inFlightKey, requestedKey: "level-\(level)", missingWork: true)
            ledger.apply(d, key: "level-\(level)")
            if d.start { busyUntil = now + 2.5 }
            now += 1.2
        }
        #expect(ledger.finished > 0)
        #expect(ledger.cancelled == 0)
    }

    @Test func manyArrivalsDuringOnePreparationEndInExactlyOneFinishedDraw() {
        var ledger = GeometryPreparationLedger()
        _ = arrive(&ledger, tripsOnly: true, key: "frame-a")
        for _ in 0..<40 { _ = arrive(&ledger, tripsOnly: true, key: "frame-a") }
        ledger.finish()
        // The landing rebuild finds nothing missing and draws.
        let landing = arrive(&ledger, tripsOnly: true, key: "frame-a", missingWork: false)
        #expect(landing.drawNow)
        #expect(ledger.started == 1)
        #expect(ledger.cancelled == 0)
        #expect(ledger.finished == 1)
        #expect(!ledger.isInFlight)
    }

    @Test func theOldBehaviourNeverFinishedUnderTheSameArrivals() {
        var ledger = GeometryPreparationLedger()
        _ = arrive(&ledger, tripsOnly: false, key: "frame-a")
        for _ in 0..<40 { _ = arrive(&ledger, tripsOnly: false, key: "frame-a") }
        #expect(ledger.finished == 0)
        #expect(ledger.cancelled == 40)
    }

    @Test func nothingMissingDrawsWithoutStartingAnything() {
        let d = GeometryPreparationGate.decide(inFlightKey: nil, requestedKey: "a", missingWork: false)
        #expect(d == .init(cancelInFlight: false, start: false, drawNow: true))
    }

    @Test func cancelOnlyCountsWhenSomethingWasInFlight() {
        var ledger = GeometryPreparationLedger()
        let counted = ledger.cancel()
        #expect(!counted)
        #expect(ledger.cancelled == 0)
    }

    @Test func tripsOnlyKeepsTheLaneScaleAndDropsTheZoomBucketAndMarkers() {
        let trips = MapRebuildOwedPolicy(tripsOnly: true)
        #expect(!trips.invalidatesLaneZoom)
        #expect(trips.invalidatesZoomBucket)
        #expect(trips.invalidatesMarkerContext)
        #expect(trips.trigger == .tripsOnly)
        let other = MapRebuildOwedPolicy(tripsOnly: false)
        #expect(other.invalidatesLaneZoom)
        #expect(other.trigger == .update)
    }

    @Test func triggerRawValuesMatchTheSignpostNumbers() {
        #expect(MapRebuildTrigger.update.rawValue == 1)
        #expect(MapRebuildTrigger.playbackReleased.rawValue == 7)
        #expect(Set(MapRebuildTrigger.allCases.map(\.rawValue)).count == MapRebuildTrigger.allCases.count)
    }

    @Test func countersSeparateTriggers() {
        var counters = MapDrawCounters()
        counters.noteFullRebuild(.update)
        counters.noteFullRebuild(.strokeMatching)
        counters.noteFullRebuild(.update)
        counters.noteRideCacheMisses(0, trigger: .update)
        counters.noteRideCacheMisses(7, trigger: .strokeMatching)
        #expect(counters.fullRebuilds[.update] == 2)
        #expect(counters.totalFullRebuilds == 3)
        #expect(counters.rideCacheMisses[.update] == nil)
        #expect(counters.totalRideCacheMisses == 7)
    }

    // MARK: - tap index

    @Test func noTapIndexPrebuildWhileLoading() {
        #expect(!TapIndexPrebuildPolicy.mayPrebuild(
            ridesAreLoading: true, hasIndex: false, hasSnapshotProvider: true))
        #expect(TapIndexPrebuildPolicy.mayPrebuild(
            ridesAreLoading: false, hasIndex: false, hasSnapshotProvider: true))
        #expect(!TapIndexPrebuildPolicy.mayPrebuild(
            ridesAreLoading: false, hasIndex: true, hasSnapshotProvider: true))
        #expect(!TapIndexPrebuildPolicy.mayPrebuild(
            ridesAreLoading: false, hasIndex: false, hasSnapshotProvider: false))
    }

    // MARK: - trip-line cache key

    private func key(
        _ ride: String, line: String?, generation: Int = 1, digest: Int = 7,
        from: Double = 0, to: Double = 100
    ) -> RideLineCacheKey {
        RideLineCacheKey(
            rideID: ride, geometryDigest: digest, segmentIndex: 0, partIndex: 0,
            stroke: line.map { .init(lineID: $0, generation: generation, from: from, to: to) })
    }

    @Test func aLineChangeInvalidatesOnlyTripsOnThatLine() {
        let keys = [
            key("hokkaido", line: "L-hokkaido"),
            key("kyushu-1", line: "L-kyushu"),
            key("kyushu-2", line: "L-kyushu"),
            key("surveyed", line: nil),
        ]
        // The Kyushu line is rebuilt: its generation moves, the rest do not.
        let generations = ["L-hokkaido": 1, "L-kyushu": 2]
        let kept = keys.filter { $0.isCurrent(lineGenerations: generations) }
        #expect(kept.map(\.rideID) == ["hokkaido", "surveyed"])
    }

    @Test func aRebuiltLinesGenerationInvalidatesItsTrips() {
        let old = key("t", line: "L", generation: 3)
        #expect(old.isCurrent(lineGenerations: ["L": 3]))
        #expect(!old.isCurrent(lineGenerations: ["L": 4]))
        // A line that left the cache invalidates its trips too.
        #expect(!old.isCurrent(lineGenerations: [:]))
    }

    @Test func aSegmentWithNoLineIsNeverInvalidatedByLines() {
        #expect(key("t", line: nil).isCurrent(lineGenerations: [:]))
    }

    @Test func theKeyNamesLineGenerationAndSpan() {
        let base = key("t", line: "L", generation: 1)
        #expect(base == key("t", line: "L", generation: 1))
        #expect(base != key("t", line: "L", generation: 2))
        #expect(base != key("t", line: "M", generation: 1))
        #expect(base != key("t", line: "L", generation: 1, to: 101))
        #expect(base != key("t", line: nil))
        #expect(base.segmentIdentity == key("t", line: nil).segmentIdentity)
    }
}
