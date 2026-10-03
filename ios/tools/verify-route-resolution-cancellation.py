#!/usr/bin/env python3
"""Test the production route task lifecycle with a cancellable solver double.

Uses extracted application methods; no app build, simulator or data mutation.
"""
from pathlib import Path
import os
import subprocess
import tempfile

root = Path(__file__).resolve().parents[2]
source = (root / 'ios/RailMap/RiddenRouteStore.swift').read_text()
def method(start, end):
    return source[source.index(start):source.index(end, source.index(start))]
load = method('    func load(trains:', '    /// Read the last-viewed route only.')
clear = method('    func clear()', '    /// The railways every current ride')
resolve = method('    func resolve(_ train:', '    /// One journey through the same cache-then-solve path')
harness = r'''
import Foundation
struct Train: Sendable, Equatable { let id: String; let number: String }
struct RouteScope: Sendable { init(_ train: Train) {} }
actor Probe {
    static let shared = Probe()
    var started: [String] = []
    var cancelled: [String] = []
    func start(_ number: String) { started.append(number) }
    func cancel(_ number: String) { cancelled.append(number) }
    func hasStarted(_ number: String) -> Bool { started.contains(number) }
    func count(_ number: String) -> Int { started.filter { $0 == number }.count }
    func hasCancelled(_ number: String) -> Bool { cancelled.contains(number) }
}
@MainActor final class RideStatusCenter {
    static let shared = RideStatusCenter()
    enum Outcome { case unavailable(expected: Int), historyDatabaseInvalid(String), resolved }
    struct Entry { let outcome: Outcome; let drawnSegments: Int }
    enum Phase: Equatable { case idle, loading, loaded, failed(String) }
    var routeStore: RiddenRouteStore?
    var resolving = Set<String>()
    var finished: [String] = []
    func publish(entries: [String: Entry], phase: Phase) { resolving.removeAll() }
    func beginResolving(_ id: String) { resolving.insert(id) }
    func finishResolving(_ id: String, entry: Entry?) { resolving.remove(id); finished.append(id) }
    func clear() { resolving.removeAll() }
}
@MainActor final class RiddenRouteStore {
    struct DrawnRide: Sendable {
        let id: String
        let number: String
        var visible: Bool { true }
        var route: RideStatusCenter.Outcome { .resolved }
        var segments: [Int] { [1] }
    }
    enum LoadState { case idle, loading, loaded(rides: [DrawnRide]), failed(String) }
    enum SingleResolve: Sendable { case ride(DrawnRide?), invalidHistory(String), failed }
    enum LoadError: Error { case invalidHistory }
    var state = LoadState.idle
    var rides: [DrawnRide] = []
    var visibleRides: [DrawnRide] = []
    private var loadTask: Task<Void, Never>?
    private var loadRevision = 0
    private var loadingInputs: [String: Train]?
    private var requestedOrder: [String] = []
    private var completedInputs: [String: Train] = [:]
    private var resolutionTickets: [String: UUID] = [:]
    private var resolutionTasks: [String: Task<Void, Never>] = [:]
    nonisolated static func resolveOne(_ train: Train, scope: RouteScope) async throws -> DrawnRide? {
        await Probe.shared.start(train.number)
        do { try await Task.sleep(for: .milliseconds(100)) }
        catch { await Probe.shared.cancel(train.number); throw error }
        return DrawnRide(id: train.id, number: train.number)
    }
    nonisolated static func loadPreferred(id: String?, wanted: [String: Train]) async -> DrawnRide? { nil }
    nonisolated static func decode(wanted: [String: Train], primed: DrawnRide?,
        publish: @Sendable ([DrawnRide]) async -> Void) async throws -> [DrawnRide] {
        await Probe.shared.start("batch-" + wanted.keys.sorted().joined(separator: ","))
        try await Task.sleep(for: .milliseconds(100))
        try Task.checkCancellation()
        return wanted.values.map { DrawnRide(id: $0.id, number: $0.number) }
    }
    nonisolated static func statusEntries(for rides: [DrawnRide], wanted: [String]) -> [String: RideStatusCenter.Entry] { [:] }
    static func sweepRouteCacheOnce() {}
    func detectTraversedLines() {}
    func wait() async { await loadTask?.value; for task in resolutionTasks.values { await task.value } }
__LOAD__
__CLEAR__
__RESOLVE__
}
@MainActor struct TraversedLineDetector { static var shared = Self(); func reset() {}; func publishSelected(rides: [RiddenRouteStore.DrawnRide]) {} }
@main struct Checks {
    @MainActor static func main() async throws {
        func started(_ number: String) async {
            for _ in 0..<10000 { if await Probe.shared.hasStarted(number) { return }; await Task.yield() }
            preconditionFailure("solver never started")
        }
        func cancelled(_ number: String) async {
            for _ in 0..<10000 { if await Probe.shared.hasCancelled(number) { return }; await Task.yield() }
            preconditionFailure("superseded solver kept running")
        }
        let batch = RiddenRouteStore()
        let inputs = [Train(id: "coalesced-a", number: "a"), Train(id: "coalesced-b", number: "b")]
        batch.load(trains: inputs)
        await started("batch-coalesced-a,coalesced-b")
        for _ in 0..<50 { batch.load(trains: inputs) }
        batch.load(trains: Array(inputs.reversed()))
        await batch.wait()
        let batchCount = await Probe.shared.count("batch-coalesced-a,coalesced-b")
        precondition(batchCount == 1, "same inputs restarted the running batch")
        precondition(batch.rides.map(\.id) == inputs.reversed().map(\.id), "order-only change was lost")
        for _ in 0..<50 { batch.load(trains: inputs) }
        let warmCount = await Probe.shared.count("batch-coalesced-a,coalesced-b")
        precondition(warmCount == 1)
        precondition(batch.rides.map(\.id) == inputs.map(\.id))
        print("PASS100 duplicate requests and order-only changes share one batch; completed inputs do not solve again")
        batch.clear()
        batch.load(trains: inputs)
        await batch.wait()
        let restartedCount = await Probe.shared.count("batch-coalesced-a,coalesced-b")
        precondition(restartedCount == 2, "clear failed to allow a fresh load")
        print("PASS clear permits one fresh batch rather than retaining an abandoned input ticket")
        let store = RiddenRouteStore()
        store.resolve(Train(id: "a", number: "first")); await started("first")
        store.resolve(Train(id: "a", number: "latest")); await cancelled("first")
        await store.wait()
        precondition(store.rides.map(\.number) == ["latest"])
        precondition(RideStatusCenter.shared.finished == ["a"])
        print("PASS repeated rebuild cancels old solver; only latest result publishes")
        store.resolve(Train(id: "a", number: "superseded-by-load")); await started("superseded-by-load")
        store.load(trains: [Train(id: "a", number: "loaded")])
        await cancelled("superseded-by-load"); await store.wait()
        precondition(store.rides.map(\.number) == ["loaded"])
        print("PASS working-set load cancels duplicate per-route solver")
        store.resolve(Train(id: "a", number: "cleared")); await started("cleared")
        store.clear(); await cancelled("cleared")
        precondition(store.rides.isEmpty && RideStatusCenter.shared.resolving.isEmpty)
        if case .idle = store.state {} else { preconditionFailure("stale result restored after clear") }
        print("PASS clear stops solver and prevents stale publication")
    }
}
'''
harness = harness.replace('__LOAD__', load).replace('__CLEAR__', clear).replace('__RESOLVE__', resolve)
with tempfile.TemporaryDirectory(prefix='jtm-resolution-cancel-') as temporary:
    folder = Path(temporary)
    checks = folder / 'Checks.swift'
    checks.write_text(harness)
    executable = folder / 'checks'
    environment = dict(os.environ, CLANG_MODULE_CACHE_PATH=str(folder / 'ModuleCache'))
    subprocess.run(['xcrun', 'swiftc', '-swift-version', '6', '-parse-as-library',
                    '-module-cache-path', str(folder / 'ModuleCache'), str(checks),
                    '-o', str(executable)], check=True, env=environment)
    subprocess.run([str(executable)], check=True, timeout=30)
