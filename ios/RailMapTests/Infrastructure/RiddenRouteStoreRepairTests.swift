import Foundation
@_spi(Testing) import RailCore
import Testing

@testable import RailMap

/// "Repair routes" keeps the route cache and the map; the full rebuild is the
/// old wipe. Every test runs against a private route-cache folder and counts
/// solver attempts through the DEBUG seams on `RiddenRouteStore`, so none of
/// them reads or removes the real Caches folder.
///
/// Serialized: the cache root and the attempt log are process-wide.
@MainActor
@Suite(.serialized)
struct RiddenRouteStoreRepairTests {
    // MARK: fixtures

    /// Two small bundled samples (Macao, Hong Kong) that solve from the
    /// bundled network. The count that actually solves is read back from the
    /// store, never assumed.
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
        let root = FileManager.default.temporaryDirectory
            .appending(path: "repair-tests-\(UUID().uuidString)", directoryHint: .isDirectory)

        init() {
            try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
            RiddenRouteStore.setCacheRootForTesting(root)
            RouteDigestIndexStore.shared.clear()
            RiddenRouteStore.resetSolveAttemptsForTesting()
        }

        deinit {
            RiddenRouteStore.setCacheRootForTesting(nil)
            RouteDigestIndexStore.shared.clear()
            try? FileManager.default.removeItem(at: root)
        }
    }

    private func settled(_ store: RiddenRouteStore) async {
        for _ in 0..<2400 {
            if case .loaded = store.state { return }
            try? await Task.sleep(for: .milliseconds(50))
        }
    }

    /// A store whose rides were read back from the cache files a first store
    /// solved and wrote, with the attempt log cleared afterwards. Both stores
    /// then hold cache-decoded geometry, so a later digest comparison is
    /// between the same bytes read twice.
    private func warmStore(_ trains: [Train]) async -> RiddenRouteStore {
        let seed = RiddenRouteStore()
        seed.load(trains: trains)
        await settled(seed)
        seed.clear()
        let store = RiddenRouteStore()
        store.load(trains: trains)
        await settled(store)
        RiddenRouteStore.resetSolveAttemptsForTesting()
        return store
    }

    // MARK: repair

    @Test func repairDoesNotResolveCachedTrips() async throws {
        let cache = IsolatedCache()
        defer { withExtendedLifetime(cache) {} }
        let trains = try solvableTrains()
        let store = await warmStore(trains)
        let before = store.rides.map(\.id)
        try #require(!before.isEmpty)
        let generation = store.ridesKeyGeneration

        await store.reloadAll(mode: .repair)
        await settled(store)

        #expect(RiddenRouteStore.solveAttempts.isEmpty)
        #expect(store.ridesKeyGeneration == generation)
        #expect(store.rides.map(\.id) == before)
        store.clear()
    }

    @Test func repairRetriesUncachedTrips() async throws {
        let cache = IsolatedCache()
        defer { withExtendedLifetime(cache) {} }
        let bad = unsolvableTrain("unsolvable")
        let trains = try solvableTrains() + [bad]
        let store = await warmStore(trains)
        let solvedIDs = Set(store.rides.map(\.id))
        try #require(!solvedIDs.isEmpty)

        await store.reloadAll(mode: .repair)
        await settled(store)

        let attempts = RiddenRouteStore.solveAttempts
        #expect(attempts[bad.id] == 1)
        for id in solvedIDs { #expect(attempts[id] == nil) }
        #expect(Set(store.rides.map(\.id)) == solvedIDs)
        store.clear()
    }

    @Test func reloadNeverBlanksMap() async throws {
        let cache = IsolatedCache()
        defer { withExtendedLifetime(cache) {} }
        let trains = try solvableTrains() + [unsolvableTrain("unsolvable")]
        let store = await warmStore(trains)
        let drawn = Set(store.rides.map(\.id))
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
        // set is exactly what solves, with no placeholder for the unsolvable trip.
        #expect(Set(store.rides.map(\.id)) == drawn)
        #expect(store.routeEntries["unsolvable"] != nil)
        store.clear()
    }

    @Test func reloadSettlesDerivedOnce() async throws {
        let cache = IsolatedCache()
        defer { withExtendedLifetime(cache) {} }
        let store = await warmStore(try solvableTrains())
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

    @Test func editDuringReloadWins() async throws {
        let cache = IsolatedCache()
        defer { withExtendedLifetime(cache) {} }
        let trains = try solvableTrains()
        let store = await warmStore(trains)
        try #require(!store.rides.isEmpty)
        let original = trains[0]
        var edited = original
        edited.number = original.number + "-edited"
        let updated = [edited] + trains.dropFirst()

        await store.reloadAll(mode: .repair)
        store.load(trains: updated)
        await settled(store)

        // The edit's input is what the store settled on; the repair's older
        // copy of that trip is not.
        #expect(store.hasSettledRoutes(in: [edited], matching: { _ in true }))
        #expect(!store.hasSettledRoutes(in: [original], matching: { _ in true }))
        #expect(store.reloadProgress == nil)
        #expect(!store.isLoading)
        #expect(store.canReloadAll)
        store.clear()
    }

    // MARK: rebuild

    @Test func rebuildResolvesAll() async throws {
        let cache = IsolatedCache()
        defer { withExtendedLifetime(cache) {} }
        let store = await warmStore(try solvableTrains())
        let solvedIDs = Set(store.rides.map(\.id))
        try #require(!solvedIDs.isEmpty)

        await store.reloadAll(mode: .rebuild)
        // The rebuild reports progress; repair is not required to.
        #expect(store.reloadProgress != nil)
        await settled(store)

        let attempts = RiddenRouteStore.solveAttempts
        for id in solvedIDs { #expect(attempts[id] == 1) }
        #expect(Set(store.rides.map(\.id)) == solvedIDs)
        store.clear()
    }
}
