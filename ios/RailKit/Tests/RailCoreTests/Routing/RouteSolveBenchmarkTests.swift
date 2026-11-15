import Foundation
import Testing
@_spi(Testing) @testable import RailCore

/// Measurement harness and history-independence guard for the route solver
/// (route-solve speed report, step 0).
///
/// The census and the ride oracle historically ran with a 100k-node graph
/// budget, under which the whole-country graph is never kept, so the app's
/// real cold-load path was never measured. This file solves the frozen
/// oracle's trips (the 287 distinct bundled sample rides) with the budget the
/// app uses (`ResourceProfile.current.regionalGraphLoadNodeBudget`): one graph
/// store per scope shared by both passes, the section memo shared per scope,
/// canonical input built per ride, the two passes in app order.
///
/// Benchmark (opt-in, minutes in Debug):
///
///     RIDE_SOLVE_BENCHMARK=1 swift test --package-path ios/RailKit \
///       -Xswiftc -enable-testing --filter RouteSolveBenchmark          # Debug
///     ... -c release ...                                                # Release
///
/// Optional: `RIDE_SOLVE_BENCHMARK_BUDGET=<nodes>` (default: the profile's),
/// `RIDE_SOLVE_BENCHMARK_STORES=train-store,train-store-tw` (default: all),
/// `RIDE_SOLVE_BENCHMARK_OUTPUT=/abs/out.json`.
///
/// History independence (always on for the non-Japan scopes; opt-in for the
/// whole oracle with `RIDE_HISTORY_INDEPENDENCE=1`): every trip must produce
/// the same canonical route record whatever was solved before it.
@Suite(.serialized)
struct RouteSolveBenchmarkTests {
    typealias Census = UserPathCensusTests

    // MARK: - Benchmark

    struct Report: Encodable {
        var configuration: String
        var graphBudget: Int
        var trips: Int
        var solveSeconds: Double
        var medianMs: Double
        var p95Ms: Double
        var maxMs: Double
        var maxTrip: String
        var builds: [String: GraphBuildSummary]
        var graphBuildSeconds: Double
        var graphBuildShare: Double
        var setupSeconds: Double
        var peakResidentMB: Double
        var peakFootprintMB: Double
    }

    struct GraphBuildSummary: Encodable {
        var count: Int
        var seconds: Double
        var meanNodes: Int
    }

    @Test("Solve the oracle trips with the app's budget and report time, builds and memory",
          .enabled(if: ProcessInfo.processInfo.environment["RIDE_SOLVE_BENCHMARK"] == "1"))
    func benchmark() throws {
        let environment = ProcessInfo.processInfo.environment
        let budget = environment["RIDE_SOLVE_BENCHMARK_BUDGET"].flatMap(Int.init)
            ?? ResourceProfile.current.regionalGraphLoadNodeBudget
        let stores = environment["RIDE_SOLVE_BENCHMARK_STORES"].map { Set($0.split(separator: ",").map(String.init)) }
        let root = try PortFixtures.repositoryRoot()
        let setupStart = ContinuousClock.now
        var rides = try RegressionGuardRideOracle.sampleRides(root: root)
        if let stores { rides = rides.filter { stores.contains($0.store) } }
        let context = try Census.Context.make(rides: rides, root: root)
        var setupSeconds = (ContinuousClock.now - setupStart).seconds

        var perTripSeconds: [String: Double] = [:]
        var solveSeconds = 0.0
        RouteGraph.BuildLog.reset()
        try context.withRegistryPhase {
            let solvable = rides.filter { !$0.train.requiresRouteConfirmation }
            let byScope = Dictionary(grouping: solvable) { Census.Scope(regions: Census.regionsTouched($0.train)) }
            for scope in Census.ordered(byScope.keys) {
                let loadStart = ContinuousClock.now
                let data = try Census.load(scope: scope, root: root, junctions: context.junctions, graphBudget: budget)
                setupSeconds += (ContinuousClock.now - loadStart).seconds
                let start = ContinuousClock.now
                let outcomes = try Census.solveScope(
                    scope: scope, rides: byScope[scope] ?? [], data: data, registry: context.registry,
                    timetable: context.timetable,
                    graphStores: .shared(budget: budget, clearMemoBeforeEachSolve: false))
                solveSeconds += (ContinuousClock.now - start).seconds
                for (id, outcome) in outcomes { perTripSeconds[id] = outcome.seconds }
            }
        }
        let builds = RouteGraph.BuildLog.snapshot()
        let sorted = perTripSeconds.values.sorted()
        func percentile(_ p: Double) -> Double {
            guard !sorted.isEmpty else { return 0 }
            return sorted[min(sorted.count - 1, Int((Double(sorted.count) * p).rounded(.up)) - 1)] * 1000
        }
        let buildSeconds = builds.values.reduce(0) { $0 + $1.seconds }
        let memory = MachMemory.read()
        let slowest = perTripSeconds.max { $0.value < $1.value }
        let report = Report(
            configuration: Self.buildConfiguration, graphBudget: budget, trips: perTripSeconds.count,
            solveSeconds: solveSeconds,
            medianMs: sorted.isEmpty ? 0 : (sorted[(sorted.count - 1) / 2] + sorted[sorted.count / 2]) / 2 * 1000,
            p95Ms: percentile(0.95), maxMs: (sorted.last ?? 0) * 1000, maxTrip: slowest?.key ?? "",
            builds: builds.mapValues {
                GraphBuildSummary(count: $0.count, seconds: $0.seconds, meanNodes: $0.count == 0 ? 0 : $0.nodes / $0.count)
            },
            graphBuildSeconds: buildSeconds,
            graphBuildShare: solveSeconds == 0 ? 0 : buildSeconds / solveSeconds,
            setupSeconds: setupSeconds,
            peakResidentMB: Double(memory.peakResident) / 1_048_576,
            peakFootprintMB: Double(memory.peakFootprint) / 1_048_576)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let json = try encoder.encode(report)
        print("route solve benchmark:\n" + String(decoding: json, as: UTF8.self))
        if let output = environment["RIDE_SOLVE_BENCHMARK_OUTPUT"] {
            try json.write(to: URL(fileURLWithPath: output))
        }
        #expect(report.trips == rides.filter { !$0.train.requiresRouteConfirmation }.count)
    }

    static var buildConfiguration: String {
        #if DEBUG
        "debug"
        #else
        "release"
        #endif
    }

    // MARK: - History independence

    enum Variant: String, CaseIterable {
        case baseline, reversed, shuffled, memoCold, freshStorePerSolve
    }

    /// Each scope solved several ways. The baseline is natural order with one
    /// shared graph store and a memo that warms up. Every other variant must
    /// give identical canonical records.
    static func assertHistoryIndependent(scopeRides: [Census.Ride], root: URL, label: String) throws {
        let context = try Census.Context.make(rides: scopeRides, root: root)
        let budget = ResourceProfile.current.regionalGraphLoadNodeBudget
        try context.withRegistryPhase {
            let solvable = scopeRides.filter { !$0.train.requiresRouteConfirmation }
            let byScope = Dictionary(grouping: solvable) { Census.Scope(regions: Census.regionsTouched($0.train)) }
            for scope in Census.ordered(byScope.keys) {
                let rides = byScope[scope] ?? []
                let data = try Census.load(scope: scope, root: root, junctions: context.junctions, graphBudget: budget)
                var encodings: [Variant: [String: String]] = [:]
                for variant in Variant.allCases {
                    data.inputs.clearResolutionMemo()
                    var order = rides
                    var stores = Census.GraphStores.shared(budget: budget, clearMemoBeforeEachSolve: false)
                    switch variant {
                    case .baseline: break
                    case .reversed: order.reverse()
                    case .shuffled:
                        var generator = SeededGenerator(seed: 0x5EED_2026)
                        order.shuffle(using: &generator)
                    case .memoCold: stores = .shared(budget: budget, clearMemoBeforeEachSolve: true)
                    case .freshStorePerSolve: stores = .freshPerSolve(budget: budget, clearMemoBeforeEachSolve: true)
                    }
                    let outcomes = try Census.solveScope(
                        scope: scope, rides: order, data: data, registry: context.registry,
                        timetable: context.timetable, graphStores: stores)
                    var encoded: [String: String] = [:]
                    for ride in rides {
                        let outcome = try #require(outcomes[ride.train.id])
                        let record = try RegressionGuardRideOracle.record(
                            ride: ride, scope: scope, pass: outcome.pass, result: outcome.result,
                            timetableMatched: outcome.timetableMatched)
                        encoded[ride.train.id] = try Self.canonicalEncoding(record)
                    }
                    encodings[variant] = encoded
                }
                let baseline = try #require(encodings[.baseline])
                for variant in Variant.allCases where variant != .baseline {
                    let other = try #require(encodings[variant])
                    let different = rides.map(\.train.id).filter { baseline[$0] != other[$0] }
                    #expect(different.isEmpty,
                            "\(label) \(scope.key): \(variant.rawValue) differs from baseline for \(different.count) trips, e.g. \(different.prefix(5))")
                }
            }
        }
    }

    static func canonicalEncoding(_ record: RegressionGuardRideOracle.Ride) throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return String(decoding: try encoder.encode(record), as: UTF8.self)
    }

    @Test("Non-Japan trips solve identically in any order, with a warm or cold memo, in a shared or fresh store")
    func historyIndependenceSmallScopes() throws {
        let root = try PortFixtures.repositoryRoot()
        let small: Set<String> = ["train-store-tw", "train-store-hk", "train-store-mo", "train-store-kr"]
        let rides = try RegressionGuardRideOracle.sampleRides(root: root).filter { small.contains($0.store) }
        #expect(rides.count == 31)
        try Self.assertHistoryIndependent(scopeRides: rides, root: root, label: "small scopes")
    }

    @Test("All 287 oracle trips solve identically in any order, memo state and store sharing",
          .enabled(if: ProcessInfo.processInfo.environment["RIDE_HISTORY_INDEPENDENCE"] == "1"))
    func historyIndependenceFull() throws {
        let root = try PortFixtures.repositoryRoot()
        let rides = try RegressionGuardRideOracle.sampleRides(root: root)
        try Self.assertHistoryIndependent(scopeRides: rides, root: root, label: "oracle")
    }
}

// MARK: - Shared solve loop

extension UserPathCensusTests {
    /// Everything a scope solve needs besides the scope's own data.
    struct Context {
        let registry: Registry
        let junctions: PhysicalRailJunctionRegistry
        let timetable: TimetableEvidence

        static func make(rides: [Ride], root: URL) throws -> Context {
            let data = root.appending(path: "app/data")
            let regionsInUse = Set(rides.flatMap { UserPathCensusTests.regionsTouched($0.train) })
            var bundles: [String: RegistryBundle] = [:]
            for region in regionsInUse {
                let url = data.appending(path: "registry-bundle/\(region).json")
                guard FileManager.default.fileExists(atPath: url.path) else { continue }
                let bundle = try JSONDecoder().decode(RegistryBundle.self, from: Data(contentsOf: url))
                if bundle.region.lowercased() == region { bundles[region] = bundle }
            }
            let registry = Registry(bundles: bundles, identities: bundles.mapValues(RegistryIdentity.init(bundle:)))
            let junctions = try PhysicalRailJunctionRegistry(
                data: Data(contentsOf: data.appending(path: "physical-rail-junctions.json")))
            let timetableURL = data.appending(path: "train-service-history/derived/train-service-timetable.sqlite")
            guard FileManager.default.fileExists(atPath: timetableURL.path) else {
                throw CocoaError(.fileNoSuchFile, userInfo: [NSFilePathErrorKey: timetableURL.path])
            }
            return Context(registry: registry, junctions: junctions, timetable: TimetableEvidence(url: timetableURL))
        }

        /// `awaitScopeRegistry`: the solve runs after the registry settles.
        func withRegistryPhase<T>(_ body: () throws -> T) rethrows -> T {
            let identities = registry.identities
            return try RegistryIdentityLookup.withTestPhase({ region in
                identities[region.lowercased()].map(RegistryPhase.ready) ?? .unavailable
            }, operation: body)
        }
    }

    /// How graph stores are shared between solves.
    struct GraphStores {
        enum Sharing { case shared, freshPerSolve }
        let sharing: Sharing
        let budget: Int
        let clearMemoBeforeEachSolve: Bool
        static func shared(budget: Int, clearMemoBeforeEachSolve: Bool) -> GraphStores {
            GraphStores(sharing: .shared, budget: budget, clearMemoBeforeEachSolve: clearMemoBeforeEachSolve)
        }
        static func freshPerSolve(budget: Int, clearMemoBeforeEachSolve: Bool) -> GraphStores {
            GraphStores(sharing: .freshPerSolve, budget: budget, clearMemoBeforeEachSolve: clearMemoBeforeEachSolve)
        }
        func make(for data: ScopeData) -> RouteGraph.RouteGraphStore {
            RouteGraph.RouteGraphStore(
                sections: data.inputs.sections, policy: .physicalRailway, junctions: data.inputs.physicalJunctions,
                cachePolicy: .bounded(maximumNodes: budget),
                identityPeriods: data.inputs.identityPeriods, sourceSnapshotID: data.inputs.snapshotID)
        }
    }

    struct SolveOutcome {
        var pass: String
        var result: RideRouteResolution.Result
        var timetableMatched: Bool
        /// Canonical input plus every pass that ran for this ride.
        var seconds: Double
    }

    /// One scope the way the app solves it: canonical input per ride, the
    /// inference pass over `rides` in the given order, then the legacy pass for
    /// the rides the first pass dropped. Mirrors `solveMissing` (see the
    /// header of the census). The store inside `data` is not used; stores
    /// come from `graphStores`.
    static func solveScope(
        scope: Scope, rides: [Ride], data: ScopeData, registry: Registry, timetable: TimetableEvidence,
        graphStores: GraphStores
    ) throws -> [String: SolveOutcome] {
        let country = scope.home
        let shared = graphStores.make(for: data)
        var canonical: [String: CanonicalInput] = [:]
        var seconds: [String: Double] = [:]
        for ride in rides {
            let start = ContinuousClock.now
            canonical[ride.train.id] = canonicalRouteInput(
                ride.train, country: country, registry: registry, timetable: timetable)
            seconds[ride.train.id] = (ContinuousClock.now - start).seconds
        }
        func solve(_ ride: Ride, allowLegacy: Bool) throws -> RideRouteResolution.Result {
            let start = ContinuousClock.now
            defer { seconds[ride.train.id, default: 0] += (ContinuousClock.now - start).seconds }
            if graphStores.clearMemoBeforeEachSolve { data.inputs.clearResolutionMemo() }
            let input = canonical[ride.train.id]!
            var resolver = RideRouteResolution(
                inputs: data.inputs, country: country, network: data.prepared,
                officialIntervals: data.inputs.officialIntervals,
                graphStore: graphStores.sharing == .shared ? shared : graphStores.make(for: data))
            return try resolver.resolve(.init(
                train: registry.upgradeIfReady(ride.train), canonicalTrain: input.train,
                databaseSections: input.databaseSections, databaseProvenance: input.databaseProvenance),
                allowLegacy: allowLegacy)
        }
        func emitsRide(_ result: RideRouteResolution.Result) -> Bool {
            switch result.disposition {
            case .geometry, .unavailable: true
            case .unsupported, .awaitingConfirmation, .noSections: false
            }
        }
        var outcomes: [String: (pass: String, result: RideRouteResolution.Result)] = [:]
        var missing: [Ride] = []
        for ride in rides {
            let result = try solve(ride, allowLegacy: false)
            outcomes[ride.train.id] = ("inference", result)
            if !emitsRide(result) { missing.append(ride) }
        }
        for ride in missing {
            outcomes[ride.train.id] = ("legacy", try solve(ride, allowLegacy: true))
        }
        return Dictionary(uniqueKeysWithValues: rides.map { ride in
            let (pass, result) = outcomes[ride.train.id]!
            return (ride.train.id, SolveOutcome(
                pass: pass, result: result,
                timetableMatched: canonical[ride.train.id]!.databaseProvenance != nil,
                seconds: seconds[ride.train.id] ?? 0))
        })
    }
}

// MARK: - Helpers

private extension Duration {
    var seconds: Double { Double(components.seconds) + Double(components.attoseconds) * 1e-18 }
}

/// Deterministic generator so the shuffled order is the same on every run.
private struct SeededGenerator: RandomNumberGenerator {
    private var state: UInt64
    init(seed: UInt64) { state = seed }
    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}

/// Peak memory of this process from the kernel (`task_info`).
private enum MachMemory {
    struct Reading { var peakResident: UInt64; var peakFootprint: UInt64 }
    static func read() -> Reading {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<natural_t>.size)
        let status = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
            }
        }
        guard status == KERN_SUCCESS else { return Reading(peakResident: 0, peakFootprint: 0) }
        return Reading(peakResident: UInt64(info.resident_size_peak),
                       peakFootprint: UInt64(info.ledger_phys_footprint_peak))
    }
}
