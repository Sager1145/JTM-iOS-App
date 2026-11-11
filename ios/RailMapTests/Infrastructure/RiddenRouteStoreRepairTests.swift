import Foundation
@_spi(Testing) import RailCore
import Testing

@testable import RailMap

/// "Repair routes" keeps the route cache and the map; the full rebuild is the
/// old wipe. Every test runs against a private route-cache folder and counts
/// solver attempts through the DEBUG seams on `RiddenRouteStore`, so none of
/// them reads or removes the real Caches folder.
///
/// The cache root and the attempt log are process-wide, so the suite is
/// serialized and `IsolatedCache` records an issue if two tests ever overlap.
/// Other suites that load trips at the same time only add their own trip ids
/// to the attempt log, and these tests assert on their own ids only.
@MainActor
@Suite(.serialized)
struct RiddenRouteStoreRepairTests {
    // MARK: fixtures

    /// Two small bundled samples (Macao, Hong Kong) that solve from the
    /// bundled network. Which of them solve is read back from the store, never
    /// assumed.
    private func solvableTrains() throws -> [Train] {
        try ["train-store-mo", "train-store-hk"].flatMap { resource -> [Train] in
            let url = try #require(Bundle.main.url(forResource: resource, withExtension: "json"))
            return try JSONDecoder().decode(TrainStore.self, from: Data(contentsOf: url)).trains
        }
    }

    /// A trip that never solves: the same non-ride outcome the landing tests use.
    private func unsolvableTrain(_ id: String) -> Train {
        Train(
            id: id, number: id, company: "JR東日本",
            origin: "東京", destination: "品川",
            routeSections: [
                RouteSection(
                    from: "東京", to: "品川",
                    fromN02StationCode: "003700", toN02StationCode: "116021"),
            ],
            stops: [
                Stop(
                    name: "東京", n02StationCode: "003700", departure: "06:00",
                    stopType: "origin", rideSegment: true),
                Stop(name: "品川", arrival: "07:00", stopType: "destination", rideSegment: true),
            ],
            region: "jp")
    }

    private final class IsolatedCache {
        nonisolated(unsafe) private static var inUse = false
        let root = FileManager.default.temporaryDirectory
            .appending(path: "repair-tests-\(UUID().uuidString)", directoryHint: .isDirectory)

        init() {
            if Self.inUse { Issue.record("route-cache tests must run serialized: the cache root is process-wide") }
            Self.inUse = true
            try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
            RiddenRouteStore.setCacheRootForTesting(root)
            RouteDigestIndexStore.shared.clear()
            RiddenRouteStore.resetSolveAttemptsForTesting()
        }

        deinit {
            RiddenRouteStore.setCacheRootForTesting(nil)
            // Back to "not loaded": the next real use reads the real index file
            // instead of flushing this test's empty one over it.
            RouteDigestIndexStore.shared.resetForTesting()
            try? FileManager.default.removeItem(at: root)
            Self.inUse = false
        }
    }

    private func settled(_ store: RiddenRouteStore) async {
        for _ in 0..<2400 {
            if case .loaded = store.state { return }
            try? await Task.sleep(for: .milliseconds(50))
        }
    }

    private func failed(_ store: RiddenRouteStore) async {
        for _ in 0..<2400 {
            if case .failed = store.state { return }
            try? await Task.sleep(for: .milliseconds(50))
        }
    }

    /// One store that solves `trains` itself, so every ride it draws was
    /// solved in this session rather than decoded from a cache file.
    private func solvedStore(_ trains: [Train]) async -> RiddenRouteStore {
        let store = RiddenRouteStore()
        store.load(trains: trains)
        await settled(store)
        RiddenRouteStore.resetSolveAttemptsForTesting()
        return store
    }

    /// A store whose rides were read back from cache files another store
    /// solved and wrote.
    private func cacheReadStore(_ trains: [Train]) async -> RiddenRouteStore {
        let seed = RiddenRouteStore()
        seed.load(trains: trains)
        await settled(seed)
        seed.clear()
        return await solvedStore(trains)
    }

    private func rideIDs(_ store: RiddenRouteStore) -> Set<String> { Set(store.rides.map(\.id)) }

    // MARK: repair

    @Test func repairDoesNotResolveCachedTrips() async throws {
        let cache = IsolatedCache()
        defer { withExtendedLifetime(cache) {} }
        let store = await cacheReadStore(try solvableTrains())
        let routed = rideIDs(store)
        try #require(!routed.isEmpty)
        let generation = store.ridesKeyGeneration

        await store.reloadAll(mode: .repair)
        await settled(store)

        // Only trips with no route in the warm store may have been attempted.
        #expect(Set(RiddenRouteStore.solveAttempts.keys).isDisjoint(with: routed))
        #expect(store.ridesKeyGeneration == generation)
        #expect(rideIDs(store) == routed)
        store.clear()
    }

    /// A route solved in this session and a copy decoded from its cache file
    /// can hash differently; repair keeps the drawn ride, so the key does not move.
    @Test func repairKeepsKeyForFreshlySolvedRoutes() async throws {
        let cache = IsolatedCache()
        defer { withExtendedLifetime(cache) {} }
        let store = await solvedStore(try solvableTrains())
        let routed = rideIDs(store)
        try #require(!routed.isEmpty)
        let generation = store.ridesKeyGeneration

        await store.reloadAll(mode: .repair)
        await settled(store)

        #expect(Set(RiddenRouteStore.solveAttempts.keys).isDisjoint(with: routed))
        #expect(store.ridesKeyGeneration == generation)
        #expect(rideIDs(store) == routed)
        store.clear()
    }

    @Test func repairRetriesUncachedTrips() async throws {
        let cache = IsolatedCache()
        defer { withExtendedLifetime(cache) {} }
        let bad = unsolvableTrain("unsolvable")
        let store = await solvedStore(try solvableTrains() + [bad])
        let routed = rideIDs(store)
        try #require(!routed.isEmpty)

        await store.reloadAll(mode: .repair)
        await settled(store)

        let attempts = RiddenRouteStore.solveAttempts
        #expect(attempts[bad.id] == 1)
        for id in routed { #expect(attempts[id] == nil) }
        #expect(rideIDs(store) == routed)
        store.clear()
    }

    @Test func reloadNeverBlanksMap() async throws {
        let cache = IsolatedCache()
        defer { withExtendedLifetime(cache) {} }
        let store = await solvedStore(try solvableTrains() + [unsolvableTrain("unsolvable")])
        let drawn = rideIDs(store)
        let floor = drawn.count
        try #require(floor > 0)

        await store.reloadAll(mode: .repair)
        // Straight after the call, before any await: the map is not emptied.
        #expect(store.rides.count >= floor)
        var lowest = store.rides.count
        for _ in 0..<2400 {
            if case .loaded = store.state { break }
            lowest = min(lowest, store.rides.count)
            try? await Task.sleep(for: .milliseconds(5))
        }
        #expect(lowest >= floor)
        // Nothing the map was holding for the repair outlives it: the final
        // set is exactly what solves, with no stand-in for the unsolvable trip.
        #expect(rideIDs(store) == drawn)
        #expect(store.routeEntries["unsolvable"] != nil)
        store.clear()
    }

    @Test func reloadSettlesDerivedOnce() async throws {
        let cache = IsolatedCache()
        defer { withExtendedLifetime(cache) {} }
        let store = await solvedStore(try solvableTrains())
        try #require(!store.rides.isEmpty)
        let generation = store.ridesKeyGeneration
        let updates = store.lineDetector.updateCallCount

        await store.reloadAll(mode: .repair)
        var flips = 0
        var wasLoading = store.isLoading
        #expect(wasLoading)
        for _ in 0..<2400 {
            let now = store.isLoading
            if now != wasLoading { flips += 1; wasLoading = now }
            if case .loaded = store.state, !now { break }
            try? await Task.sleep(for: .milliseconds(5))
        }

        // true -> false exactly once, one detection pass for the whole repair,
        // and unchanged rides keep the key line detection and statistics are
        // cached under (so nothing is walked again).
        #expect(flips == 1)
        #expect(store.lineDetector.updateCallCount == updates + 1)
        #expect(store.ridesKeyGeneration == generation)
        store.clear()
    }

    /// The repair is mid-flight (one partial result has landed, an uncached
    /// trip is still solving) when a trip is edited: the edit's load takes
    /// over, and the old route of the edited trip is not left on the map.
    @Test func editDuringReloadWins() async throws {
        let cache = IsolatedCache()
        defer { withExtendedLifetime(cache) {} }
        let trains = try solvableTrains()
        let store = await solvedStore(trains + [unsolvableTrain("unsolvable")])
        let routed = rideIDs(store)
        try #require(routed.count >= 2)
        let original = trains[0]
        var edited = original
        edited.number = original.number + "-edited"
        let updated = [edited] + trains.dropFirst() + [unsolvableTrain("unsolvable")]

        await store.reloadAll(mode: .repair)
        var sawPartial = false
        for _ in 0..<4000 where !sawPartial {
            sawPartial = (store.reloadProgress?.done ?? 0) > 0
            if !sawPartial { try? await Task.sleep(for: .milliseconds(5)) }
        }
        try #require(sawPartial, "no partial result landed before the repair settled")
        store.load(trains: updated)

        // No stale stand-in: the edited trip has no ride until it is solved,
        // while the trips that did not change stay drawn.
        #expect(!store.rides.contains { $0.id == original.id })
        #expect(routed.subtracting([original.id]).isSubset(of: rideIDs(store)))
        await settled(store)

        #expect(store.hasSettledRoutes(in: [edited], matching: { _ in true }))
        #expect(!store.hasSettledRoutes(in: [original], matching: { _ in true }))
        #expect(store.rides.contains { $0.id == original.id })
        #expect(store.reloadProgress == nil)
        #expect(store.canReloadAll)
        store.clear()
    }

    /// A stand-in exists only for a trip whose solver input is unchanged.
    @Test func standInOnlyForUnchangedInput() async throws {
        let cache = IsolatedCache()
        defer { withExtendedLifetime(cache) {} }
        let trains = try solvableTrains()
        let store = await solvedStore(trains)
        let routed = rideIDs(store)
        try #require(routed.count >= 2)
        let original = trains[0]
        var edited = original
        edited.number = original.number + "-edited"

        await store.reloadAll(mode: .repair)
        store.load(trains: [edited] + trains.dropFirst())

        // Straight after the call: the unchanged trips stand in, the edited one does not.
        #expect(rideIDs(store) == routed.subtracting([original.id]))
        await settled(store)
        store.clear()
    }

    /// Stop on a repair settles from the cache alone: nothing is solved, the
    /// cached trips stay drawn, and the unsolved one is left for the next load.
    @Test func stopDuringRepairDoesNotSolve() async throws {
        let cache = IsolatedCache()
        defer { withExtendedLifetime(cache) {} }
        let bad = unsolvableTrain("unsolvable")
        let store = await solvedStore(try solvableTrains() + [bad])
        let routed = rideIDs(store)
        try #require(!routed.isEmpty)

        await store.reloadAll(mode: .repair)
        store.cancelReloadAll()
        await settled(store)

        #expect(RiddenRouteStore.solveAttempts[bad.id] == nil)
        #expect(rideIDs(store) == routed)
        #expect(store.routeEntries[bad.id] != nil)
        #expect(!store.hasSettledRoutes(in: [bad], matching: { _ in true }))
        #expect(store.reloadProgress == nil)
        #expect(store.canReloadAll)
        store.clear()
    }

    /// A repair whose load fails keeps its stand-ins drawn and completed, so
    /// the next ordinary load keeps them instead of blanking the trips.
    @Test func failedRepairKeepsStandIns() async throws {
        let cache = IsolatedCache()
        defer { withExtendedLifetime(cache) {} }
        let trains = try solvableTrains()
        let store = await solvedStore(trains)
        let routed = rideIDs(store)
        try #require(!routed.isEmpty)

        RiddenRouteStore.injectLoadFailureForTesting()
        await store.reloadAll(mode: .repair)
        await failed(store)
        guard case .failed = store.state else {
            Issue.record("the injected failure did not fail the load")
            return
        }
        #expect(rideIDs(store) == routed)

        store.load(trains: trains)
        // Straight after the call: nothing was removed and drawn again.
        #expect(rideIDs(store) == routed)
        await settled(store)
        #expect(rideIDs(store) == routed)
        store.clear()
    }

    // MARK: rebuild

    @Test func rebuildResolvesAll() async throws {
        let cache = IsolatedCache()
        defer { withExtendedLifetime(cache) {} }
        let store = await solvedStore(try solvableTrains())
        let routed = rideIDs(store)
        try #require(!routed.isEmpty)

        await store.reloadAll(mode: .rebuild)
        // The rebuild reports progress; repair is not required to.
        #expect(store.reloadProgress != nil)
        await settled(store)

        let attempts = RiddenRouteStore.solveAttempts
        for id in routed { #expect(attempts[id] == 1) }
        #expect(rideIDs(store) == routed)
        store.clear()
    }
}
