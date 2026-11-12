import Testing
@testable import RailPresentation

@Suite("MapLoadAhead")
struct MapLoadAheadTests {
    typealias Rect = MapBuildArea.Rect
    let visible = Rect(x: 1000, y: 1000, width: 400, height: 300)

    @Test func requestAlwaysContainsVisibleWithMarginRing() {
        let rect = MapLoadAhead.requestRect(visible: visible, velocity: .zero)
        #expect(MapLoadAhead.contains(rect, visible))
        #expect(rect == Rect(x: 800, y: 850, width: 800, height: 600))
    }

    @Test func extendsAtLeastOneScreenInTheDirectionOfTravel() {
        let rect = MapLoadAhead.requestRect(visible: visible, velocity: .init(dx: 10, dy: 0))
        #expect(rect.x + rect.width >= visible.x + visible.width + 400 + 200)
        #expect(rect.x == 800)
    }

    @Test func travelsOppositeWhenVelocityIsNegative() {
        let rect = MapLoadAhead.requestRect(visible: visible, velocity: .init(dx: 0, dy: -10))
        #expect(rect.y <= visible.y - 300 - 150)
        #expect(rect.y + rect.height == 1000 + 300 + 150)
    }

    @Test func fastTravelIsCappedAtMaximumScreens() {
        let rect = MapLoadAhead.requestRect(visible: visible, velocity: .init(dx: 1_000_000, dy: 0))
        #expect(rect.x + rect.width == 1000 + 400 + 4 * 400 + 200)
    }

    @Test func velocityHorizonScalesBetweenMinimumAndMaximum() {
        let v = MapLoadAhead.velocity(
            from: Rect(x: 0, y: 0, width: 400, height: 300),
            to: Rect(x: 200, y: 0, width: 400, height: 300), elapsed: 0.2)
        #expect(v == .init(dx: 1000, dy: 0))
        let rect = MapLoadAhead.requestRect(visible: visible, velocity: v)
        #expect(rect.x + rect.width == 1000 + 400 + 1500 + 200)
    }

    @Test func throttleRunsEveryIntervalNotEveryCallback() {
        #expect(MapLoadAhead.isDue(now: 5, lastPass: nil))
        #expect(!MapLoadAhead.isDue(now: 5.1, lastPass: 5))
        #expect(MapLoadAhead.isDue(now: 5.2, lastPass: 5))
    }

    @Test func tilesAreStableAtTheirScaleAndNegativeSafe() {
        let size = MapOverlayTiling.tileSize(mapPointsPerScreenPoint: 2)
        #expect(size == 2048)
        #expect(MapOverlayTiling.tile(x: 0, y: 2047, tileSize: size) == .init(x: 0, y: 0))
        #expect(MapOverlayTiling.tile(x: 2048, y: -1, tileSize: size) == .init(x: 1, y: -1))
    }
}

@Suite("AddOnlyBatchLedger")
struct AddOnlyBatchLedgerTests {
    typealias Entry = AddOnlyBatchLedger<String>.Entry
    func entry(_ item: String, _ group: String, _ x: Int, _ y: Int) -> Entry {
        .init(item: item, group: group, tile: .init(x: x, y: y))
    }

    @Test func panWithinOneLevelKeepsExistingBatchesAndOnlyAddsNew() {
        var ledger = AddOnlyBatchLedger<String>()
        let first = [entry("a", "red", 0, 0), entry("b", "red", 0, 0), entry("c", "blue", 1, 0)]
        ledger.update(first)
        let before = Dictionary(uniqueKeysWithValues: ledger.batches.map { ($0.key, $0.items) })
        #expect(Set(before.keys) == ["red|0,0", "blue|1,0"])

        // Pan: a line in a new tile, a late line in an existing tile and colour.
        let created = ledger.update(first + [entry("d", "red", 2, 0), entry("e", "red", 0, 0)])
        let after = Dictionary(uniqueKeysWithValues: ledger.batches.map { ($0.key, $0.items) })
        for (key, items) in before { #expect(after[key] == items) }
        #expect(Set(created) == ["red|2,0", "red|0,0#1"])
        #expect(Set(after.keys).subtracting(before.keys) == Set(created))
        #expect(after["red|0,0#1"] == ["e"])
    }

    @Test func repeatedIdenticalUpdateCreatesNothing() {
        var ledger = AddOnlyBatchLedger<String>()
        let entries = [entry("a", "red", 0, 0)]
        ledger.update(entries)
        #expect(ledger.update(entries).isEmpty)
        #expect(ledger.batches.count == 1)
    }

    @Test func offScreenItemsDoNotUnloadABatchWhileAnyMemberIsOffered() {
        var ledger = AddOnlyBatchLedger<String>()
        ledger.update([entry("a", "red", 0, 0), entry("b", "red", 0, 0)])
        ledger.update([entry("a", "red", 0, 0)])
        #expect(ledger.batches.first?.items == ["a", "b"])
    }

    @Test func batchNothingOffersAnyMoreIsDropped() {
        var ledger = AddOnlyBatchLedger<String>()
        ledger.update([entry("a", "red", 0, 0)])
        ledger.update([entry("z", "blue", 5, 5)])
        #expect(ledger.batches.map(\.key) == ["blue|5,5"])
    }

    @Test func orderIsGroupThenTileThenSerial() {
        var ledger = AddOnlyBatchLedger<String>()
        ledger.update([entry("a", "b", 1, 0), entry("b", "a", 2, 0), entry("c", "a", 1, 0)])
        #expect(ledger.batches.map(\.key) == ["a|1,0", "a|2,0", "b|1,0"])
    }
}

@Suite("StrokeStabilityLedger")
struct StrokeStabilityLedgerTests {
    @Test func laterWaveChangesNoStrokeGenerationOfLinesAlreadyDrawn() {
        var ledger = StrokeStabilityLedger()
        ledger.resolve(current: ["a": 1, "b": 1], moving: true)
        // A neighbour of a arrives: a's latest generation moves to 2; c is new.
        let drawn = ledger.resolve(current: ["a": 2, "b": 1, "c": 1], moving: true)
        #expect(drawn == ["a": 1, "b": 1, "c": 1])
        #expect(ledger.held(current: ["a": 2, "b": 1, "c": 1]) == ["a"])
    }

    @Test func settlingRefreshesHeldLines() {
        var ledger = StrokeStabilityLedger()
        ledger.resolve(current: ["a": 1], moving: true)
        ledger.resolve(current: ["a": 2], moving: true)
        let drawn = ledger.resolve(current: ["a": 2], moving: false)
        #expect(drawn == ["a": 2])
        #expect(ledger.held(current: ["a": 2]).isEmpty)
    }
}
