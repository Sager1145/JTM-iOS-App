#!/usr/bin/env python3
"""Execute production batched availability control flow with bounded Swift doubles.

Pass an existing SwiftPM build directory containing libRailCore.a. No package
build, fixture decode, route graph construction, or test runner is invoked.
"""
from pathlib import Path
import argparse
import subprocess
import tempfile


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('build_directory', type=Path)
    parser.add_argument('source', nargs='?', type=Path, help='RiddenRouteStore.swift (defaults to repository source)')
    args = parser.parse_args()
    root = Path(__file__).resolve().parents[2]
    libraries = sorted(args.build_directory.rglob('libRailCore.a'))
    if not libraries:
        parser.error('build directory must contain an existing libRailCore.a')
    products = libraries[0].parent
    source = (args.source or root / 'ios/RailMap/RiddenRouteStore.swift').read_text()
    start = source.index('    struct RouteAvailability: Sendable {')
    end = source.index('    /// One journey through the same cache-then-solve path', start)
    # Keep both the result type and the entire production method unchanged,
    # including scope-local graph ownership, cancellation and both snapshots.
    extracted = source[start:end]
    # Adapt only the controlled solver double's name to Main or the CLI worker branch.
    # The extracted production method remains byte-for-byte unchanged.
    helper_name = ('solveMissingSequentialWithPermit' if 'solveMissingSequentialWithPermit(' in extracted
                   else 'solveMissingWithPermit')
    helpers = HELPERS.replace('solveMissingSequentialWithPermit', helper_name)
    swift = DOUBLES + '\nenum RiddenRouteStore {\n' + helpers + extracted + '\n}\n' + CHECKS
    with tempfile.TemporaryDirectory(prefix='jtm-route-availability-') as directory:
        folder = Path(directory)
        script = folder / 'Checks.swift'
        binary = folder / 'checks'
        script.write_text(swift)
        subprocess.run([
            'xcrun', 'swiftc', '-swift-version', '6', '-parse-as-library', '-O',
            '-module-cache-path', str(folder / 'modules'), '-I', str(products),
            '-L', str(products), '-lRailCore', str(script), '-o', str(binary)
        ], check=True, timeout=90)
        subprocess.run([str(binary)], check=True, timeout=25)


DOUBLES = r'''
import Foundation
import Synchronization
import RailCore

struct RouteScope: Hashable, Sendable {
    let code: String
    init(_ train: Train) { code = train.region ?? "jp" }
    static func ordered(_ scopes: Dictionary<RouteScope, [(Int, Train)]>.Keys) -> [RouteScope] {
        scopes.sorted { $0.code < $1.code }
    }
}
struct Route: Sendable { let isResolved: Bool }
struct DrawnRide: Sendable { let route: Route }
final class GraphStore: Sendable {
    let id = UUID()
    let scope: String
    init(scope: String) {
        self.scope = scope
        probe.state.withLock { state in
            state.liveGraphs[id] = scope
            state.maximumLiveGraphs = max(state.maximumLiveGraphs, state.liveGraphs.count)
        }
    }
    deinit { probe.state.withLock { $0.liveGraphs[id] = nil } }
}
struct UncheckedGraphStoreBox: Sendable { let store: GraphStore }
struct Inputs: Sendable { let scope: RouteScope }
typealias SolverInputs = Inputs
struct Network: Sendable { }
enum Failure: Error { case planned }

actor Gate {
    private var continuation: CheckedContinuation<Void, Never>?
    private var released = false
    private(set) var entered = false
    func wait() async {
        entered = true
        if released { return }
        await withCheckedContinuation { continuation = $0 }
    }
    func release() { released = true; continuation?.resume(); continuation = nil }
}
struct Key: Hashable, Sendable {
    let id: String
    let date: String?
    init(_ train: Train) { id = train.id; date = train.date }
    init(_ id: String, _ date: String?) { self.id = id; self.date = date }
}
struct SolveCall: Sendable {
    let key: Key
    let scope: String
    let graph: UUID
    let save: Bool
    let legacy: Bool
}
final class Probe: Sendable {
    struct State {
        var cached: [Key: Bool] = [:]
        var answers: [Key: Bool] = [:]
        var cacheReads: [Key] = []
        var cancelCacheRead: Key?
        var inputScopes: [String] = []
        var decodedScopes: [String] = []
        var completedInputScope: String?
        var liveGraphs: [UUID: String] = [:]
        var maximumLiveGraphs = 0
        var decodedBesideOtherScopeGraph = false
        var cancelInputScope: String?
        var cancelDisplayScope: String?
        var displayScopes: [String] = []
        var graphScopes: [String] = []
        var solves: [SolveCall] = []
        var solveFailure: Key?
        var inputFailure: String?
        var displayFailure: String?
        var permitFailure = false
        var gateKey: Key?
        var gate: Gate?
        var cooperate = true
        var permits = 0
        var writes = 0
        var publications = 0
        var callbacks = 0
    }
    let state = Mutex(State())
    func reset() { state.withLock { $0 = State() } }
}
let probe = Probe()
struct SolverInputCache: Sendable {
    static let shared = SolverInputCache()
    func inputs(scope: RouteScope) async throws -> Inputs {
        let (fail, cancel) = probe.state.withLock { state in
            state.inputScopes.append(scope.code)
            if state.completedInputScope != scope.code {
                state.decodedScopes.append(scope.code)
                state.decodedBesideOtherScopeGraph = state.decodedBesideOtherScopeGraph
                    || state.liveGraphs.values.contains { $0 != scope.code }
                state.completedInputScope = scope.code
            }
            return (state.inputFailure == scope.code, state.cancelInputScope == scope.code)
        }
        if cancel { withUnsafeCurrentTask { $0?.cancel() } }
        if fail { throw Failure.planned }
        return Inputs(scope: scope)
    }
}
struct DisplayNetworkCache: Sendable {
    static let shared = DisplayNetworkCache()
    func network(scope: RouteScope) async throws -> Network {
        let (fail, cancel) = probe.state.withLock { state in
            state.displayScopes.append(scope.code)
            return (state.displayFailure == scope.code, state.cancelDisplayScope == scope.code)
        }
        if cancel { withUnsafeCurrentTask { $0?.cancel() } }
        if fail { throw Failure.planned }
        return Network()
    }
}
struct RouteSolveLimiter: Sendable {
    static let shared = RouteSolveLimiter()
    func withPermit<T: Sendable>(_ work: @Sendable () async throws -> T) async throws -> T {
        let fail = probe.state.withLock { state in
            state.permits += 1
            return state.permitFailure
        }
        if fail { throw Failure.planned }
        return try await work()
    }
}
'''

HELPERS = r'''
    static func loadCached(_ trains: [Train], country: String) -> (rides: [DrawnRide], missing: [Train]) {
        precondition(trains.count == 1 && country == (trains[0].region ?? "jp"))
        let key = Key(trains[0])
        let (hit, cancel) = probe.state.withLock { state in
            state.cacheReads.append(key)
            return (state.cached[key], state.cancelCacheRead == key)
        }
        if cancel { withUnsafeCurrentTask { $0?.cancel() } }
        return (hit.map { [DrawnRide(route: Route(isResolved: $0))] } ?? [], hit == nil ? trains : [])
    }
    static func fallbackGraphStore(inputs: Inputs, displayNetwork: Network?) -> GraphStore {
        probe.state.withLock { $0.graphScopes.append(inputs.scope.code) }
        return GraphStore(scope: inputs.scope.code)
    }
    static func solveMissingSequentialWithPermit(
        _ trains: [Train], scope: RouteScope, allowLegacy: Bool,
        graphStore: GraphStore, providedInputs: Inputs? = nil, rejectPrecomputed: @Sendable (Train) -> Void,
        publish: @Sendable (DrawnRide) -> Void, saveRoutes: Bool
    ) async throws -> [DrawnRide] {
        precondition(trains.count == 1)
        // The production prologue uses coupled immutable inputs when supplied.
        let inputs: Inputs
        if let providedInputs { inputs = providedInputs }
        else { inputs = try await SolverInputCache.shared.inputs(scope: scope) }
        precondition(inputs.scope == scope)
        let key = Key(trains[0])
        let (gate, cooperate, fail, answer) = probe.state.withLock { state in
            state.solves.append(SolveCall(key: key, scope: scope.code, graph: graphStore.id,
                                         save: saveRoutes, legacy: allowLegacy))
            return (state.gateKey == key ? state.gate : nil, state.cooperate,
                    state.solveFailure == key, state.answers[key, default: false])
        }
        if let gate { await gate.wait() }
        if cooperate { try Task.checkCancellation() }
        if fail { throw Failure.planned }
        let ride = DrawnRide(route: Route(isResolved: answer))
        // Exercise both supplied callbacks. The production availability probe
        // supplies no-op callbacks and disables the persisted-route branch.
        rejectPrecomputed(trains[0]); publish(ride)
        probe.state.withLock { state in
            state.callbacks += 2
            if saveRoutes { state.writes += 1 }
        }
        return [ride]
    }
    static func publishRide(_ ride: DrawnRide) {
        probe.state.withLock { $0.publications += 1 }
    }
'''

CHECKS = r'''
func train(_ id: String, _ date: String? = "2001-01-01", _ scope: String = "jp") -> Train {
    Train(id: id, date: date, number: id, origin: "A", destination: "B", stops: [], region: scope)
}
func flags(_ results: [RiddenRouteStore.RouteAvailability]) -> [[Bool]] {
    results.map { [$0.undatedResolved, $0.datedResolved] }
}
func quiet() {
    probe.state.withLock { state in
        precondition(state.writes == 0 && state.publications == 0)
        precondition(state.solves.allSatisfy { !$0.save && $0.legacy })
        precondition(state.liveGraphs.isEmpty && state.maximumLiveGraphs <= 1)
    }
}
func waitForEntry(_ gate: Gate) async {
    let deadline = ContinuousClock.now + .seconds(5)
    while !(await gate.entered) {
        precondition(ContinuousClock.now < deadline, "Gate entry timed out")
        await Task.yield()
    }
}
func expectFailure(_ operation: @Sendable () async throws -> Void) async throws {
    do { try await operation(); preconditionFailure("Expected planned failure") }
    catch Failure.planned { }
}
func expectCancellation(_ task: Task<[RiddenRouteStore.RouteAvailability], Error>) async throws {
    do { _ = try await task.value; preconditionFailure("Expected cancellation") }
    catch is CancellationError { }
}
@main struct Checks {
    static func main() async throws {
        probe.reset()
        probe.state.withLock { $0.answers[Key("retired", "2001-01-01")] = true }
        let retired = train("retired")
        let first = try await RiddenRouteStore.routeAvailabilities([retired])
        precondition(flags(first) == [[false, true]], "Historical-only railway must prove its dated ride")
        precondition(retired.date == "2001-01-01")
        probe.state.withLock { state in
            precondition(state.solves.map(\.key) == [Key("retired", nil), Key("retired", "2001-01-01")])
            precondition(state.graphScopes == ["jp"] && Set(state.solves.map(\.graph)).count == 1)
            precondition(state.callbacks == 4)
        }
        quiet(); print("PASS historical date-only success probes both snapshots and reuses one graph")

        probe.reset()
        probe.state.withLock { $0.answers[Key("closed", nil)] = true }
        let closed = try await RiddenRouteStore.routeAvailabilities([train("closed")])
        precondition(flags(closed) == [[true, false]])
        quiet(); print("PASS historical closure retains undated true and dated false")

        probe.reset()
        let absent = try await RiddenRouteStore.routeAvailabilities([train("missing")])
        precondition(flags(absent) == [[false, false]])
        quiet(); print("PASS both failed snapshots remain unproven")

        probe.reset()
        let mixed = [train("cached", "2001-01-01", "jp"), train("hongkong", "2001-01-01", "hk"), train("japan")]
        probe.state.withLock { state in
            state.cached[Key("cached", nil)] = true
            state.cached[Key("cached", "2001-01-01")] = false
            state.answers[Key("hongkong", "2001-01-01")] = true
            state.answers[Key("japan", nil)] = true
            state.answers[Key("japan", "2001-01-01")] = true
        }
        let ordered = try await RiddenRouteStore.routeAvailabilities(mixed)
        precondition(flags(ordered) == [[true, false], [false, true], [true, true]])
        probe.state.withLock { state in
            precondition(state.decodedScopes == ["hk", "jp"] && state.graphScopes == ["hk", "jp"])
            precondition(state.solves.map(\.key.id) == ["hongkong", "hongkong", "japan", "japan"])
            precondition(state.solves.map(\.scope) == ["hk", "hk", "jp", "jp"])
            precondition(state.solves[0].graph == state.solves[1].graph)
            precondition(state.solves[2].graph == state.solves[3].graph)
            precondition(state.maximumLiveGraphs == 1 && state.liveGraphs.isEmpty)
            precondition(!state.decodedBesideOtherScopeGraph)
        }
        quiet(); print("PASS ordered scopes, cache positions and original output order")

        probe.reset()
        probe.state.withLock { $0.cached[Key("undated", nil)] = true }
        let undated = try await RiddenRouteStore.routeAvailabilities([train("undated", nil)])
        precondition(flags(undated) == [[true, true]])
        probe.state.withLock { state in
            precondition(state.cacheReads == [Key("undated", nil), Key("undated", nil)])
            precondition(state.solves.isEmpty && state.graphScopes.isEmpty && state.permits == 0)
        }
        quiet(); print("PASS nil-date input and cache-only snapshots need no graph or solver")

        probe.reset()
        probe.state.withLock { $0.answers[Key("undated", nil)] = true }
        let uncachedNil = try await RiddenRouteStore.routeAvailabilities([train("undated", nil)])
        precondition(flags(uncachedNil) == [[true, true]])
        probe.state.withLock { state in
            precondition(state.solves.map(\.key) == [Key("undated", nil), Key("undated", nil)])
            precondition(state.decodedScopes == ["jp"] && state.graphScopes == ["jp"])
        }
        quiet(); print("PASS uncached nil-date snapshots preserve both passes with one graph")

        probe.reset()
        let empty = try await RiddenRouteStore.routeAvailabilities([])
        precondition(empty.isEmpty)
        probe.state.withLock { precondition($0.cacheReads.isEmpty && $0.inputScopes.isEmpty && $0.permits == 0) }
        print("PASS empty batch has no cache, graph or limiter work")

        probe.reset()
        let before = Gate()
        let preCancelled = Task { await before.wait(); return try await RiddenRouteStore.routeAvailabilities([train("cancel")]) }
        await waitForEntry(before); preCancelled.cancel(); await before.release()
        try await expectCancellation(preCancelled)
        probe.state.withLock { precondition($0.cacheReads.isEmpty && $0.solves.isEmpty) }
        print("PASS cancellation before probing prevents cache and solve work")

        probe.reset()
        let during = Gate()
        probe.state.withLock { state in state.gateKey = Key("cancel", nil); state.gate = during }
        let cancelled = Task { try await RiddenRouteStore.routeAvailabilities([train("cancel")]) }
        await waitForEntry(during); cancelled.cancel(); await during.release()
        try await expectCancellation(cancelled)
        probe.state.withLock { precondition($0.solves.count == 1 && $0.callbacks == 0) }
        quiet(); print("PASS cancellation thrown by suspended solver propagates")

        probe.reset()
        let ignoring = Gate()
        probe.state.withLock { state in
            state.gateKey = Key("first", nil); state.gate = ignoring; state.cooperate = false
        }
        let interrupted = Task { try await RiddenRouteStore.routeAvailabilities([train("first"), train("second")]) }
        await waitForEntry(ignoring); interrupted.cancel(); await ignoring.release()
        try await expectCancellation(interrupted)
        probe.state.withLock { precondition($0.solves.count == 1) }
        quiet(); print("PASS next-entry cancellation guard stops a noncooperative previous solve")

        for dated in [false, true] {
            probe.reset()
            let finalGate = Gate()
            probe.state.withLock { state in
                if dated { state.cached[Key("final", nil)] = false }
                state.gateKey = Key("final", dated ? "2001-01-01" : nil)
                state.gate = finalGate
                state.cooperate = false
            }
            let final = Task { try await RiddenRouteStore.routeAvailabilities([train("final")]) }
            await waitForEntry(finalGate); final.cancel(); await finalGate.release()
            try await expectCancellation(final)
            probe.state.withLock { state in
                precondition(state.solves.count == 1 && state.callbacks == 2)
                let expectedReads = dated
                    ? [Key("final", nil), Key("final", "2001-01-01")]
                    : [Key("final", nil)]
                precondition(state.cacheReads == expectedReads,
                             "Cancelled undated phase must never enter the dated phase")
            }
            quiet()
        }
        print("PASS cancellation after noncooperative final solve rejects undated and dated phase outputs")

        probe.reset()
        probe.state.withLock { state in
            state.cached[Key("cached-cancel", nil)] = true
            state.cancelCacheRead = Key("cached-cancel", nil)
        }
        let cachedCancelled = Task { try await RiddenRouteStore.routeAvailabilities([train("cached-cancel", nil)]) }
        try await expectCancellation(cachedCancelled)
        probe.state.withLock { state in
            precondition(state.cacheReads == [Key("cached-cancel", nil)])
            precondition(state.solves.isEmpty && state.graphScopes.isEmpty)
        }
        quiet(); print("PASS cancellation during final cache-only read rejects output before the next phase")

        for failure in ["inputs", "limiter", "solver"] {
            probe.reset()
            probe.state.withLock { state in
                switch failure {
                case "inputs": state.inputFailure = "jp"
                case "limiter": state.permitFailure = true
                default: state.solveFailure = Key("failure", nil)
                }
            }
            try await expectFailure { _ = try await RiddenRouteStore.routeAvailabilities([train("failure")]) }
            quiet()
        }
        print("PASS input, limiter and solver errors propagate without writes/publication")

        probe.reset()
        probe.state.withLock { state in
            state.cached[Key("dated-error", nil)] = false
            state.solveFailure = Key("dated-error", "2001-01-01")
        }
        try await expectFailure { _ = try await RiddenRouteStore.routeAvailabilities([train("dated-error")]) }
        probe.state.withLock { state in
            precondition(state.solves.map(\.key) == [Key("dated-error", "2001-01-01")])
        }
        quiet(); print("PASS dated-phase solver failure propagates even after an undated false cache hit")

        probe.reset()
        probe.state.withLock { state in
            state.displayFailure = "jp"
            state.answers[Key("fallback", nil)] = true
            state.answers[Key("fallback", "2001-01-01")] = true
        }
        let fallback = try await RiddenRouteStore.routeAvailabilities([train("fallback")])
        precondition(flags(fallback) == [[true, true]])
        quiet(); print("PASS optional display failure uses fallback graph and remains read-only")
        probe.reset()
        let scopes = ["jp", "hk", "tw", "mo", "kr", "jp"]
        let multi = scopes.enumerated().map { train("multi-\($0.offset)", "2001-01-01", $0.element) }
        probe.state.withLock { state in
            for (position, train) in multi.enumerated() {
                state.answers[Key(train.id, nil)] = position.isMultiple(of: 2)
                state.answers[Key(train)] = !position.isMultiple(of: 2)
            }
        }
        let multiResults = try await RiddenRouteStore.routeAvailabilities(multi)
        precondition(flags(multiResults) == [[true, false], [false, true], [true, false], [false, true], [true, false], [false, true]])
        probe.state.withLock { state in
            precondition(state.decodedScopes == ["hk", "jp", "kr", "mo", "tw"])
            precondition(state.graphScopes == state.decodedScopes)
            precondition(state.maximumLiveGraphs == 1 && state.liveGraphs.isEmpty)
            precondition(!state.decodedBesideOtherScopeGraph)
            for scope in Set(scopes) {
                precondition(Set(state.solves.filter { $0.scope == scope }.map(\.graph)).count == 1)
            }
        }
        quiet(); print("PASS five scopes release graph ownership before replacement decode, decode once per pair, and preserve original per-train tuples")

        for stage in ["inputs", "display"] {
            probe.reset()
            probe.state.withLock { state in
                if stage == "inputs" { state.cancelInputScope = "jp" }
                else { state.cancelDisplayScope = "jp" }
            }
            let cancelledAwait = Task { try await RiddenRouteStore.routeAvailabilities([train("await-cancel")]) }
            try await expectCancellation(cancelledAwait)
            probe.state.withLock { state in
                precondition(state.solves.isEmpty && state.graphScopes.isEmpty && state.permits == 0)
                if stage == "inputs" { precondition(state.displayScopes.isEmpty) }
            }
            quiet()
        }
        print("PASS cancellation after noncooperative input/display awaits prevents graph construction and solving")
        probe.reset()
        let evictionGate = Gate()
        probe.state.withLock { state in
            state.answers[Key("eviction", nil)] = true
            state.answers[Key("eviction", "2001-01-01")] = true
            state.gateKey = Key("eviction", nil)
            state.gate = evictionGate
        }
        let evictedPair = Task { try await RiddenRouteStore.routeAvailabilities([train("eviction")]) }
        await waitForEntry(evictionGate)
        // Model another caller replacing the single completed cache slot
        // while this scope's first noncooperative solve is suspended.
        probe.state.withLock { $0.completedInputScope = "other-caller" }
        await evictionGate.release()
        let evictionResults = try await evictedPair.value
        precondition(flags(evictionResults) == [[true, true]])
        probe.state.withLock { state in
            precondition(state.inputScopes == ["jp"] && state.decodedScopes == ["jp"])
            precondition(Set(state.solves.map(\.graph)).count == 1)
        }
        quiet(); print("PASS external completed-slot eviction during first solve cannot reload the paired scope inputs")
        print("PASS prior 21 runtime cases plus external-eviction case; actual method extraction; controlled doubles, no real footprint claim")
    }
}
'''

if __name__ == '__main__':
    main()
