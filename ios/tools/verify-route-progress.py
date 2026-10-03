#!/usr/bin/env python3
"""Exercise the production decoder's progressive publication with controlled work."""
from pathlib import Path
import os
import subprocess
import tempfile

root = Path(__file__).resolve().parents[2]
source = (root / "ios/RailMap/RiddenRouteStore.swift").read_text()
start = source.index("    @concurrent private nonisolated static func decode(")
end = source.index("    /// The rides one precomputed dataset can answer for.", start)
decode = source[start:end]
harness = r'''
import Foundation
struct Train: Sendable { let id: String }
struct RouteScope: Hashable, Sendable {
    let code = "jp"
    var home: String { code }
    var regions: [String] { [code] }
    init(_ train: Train) {}
    static func ordered(_ scopes: Dictionary<RouteScope, [Train]>.Keys) -> [RouteScope] { Array(scopes) }
}
enum RideLibrary { static func routeDatasets(for region: String) -> [String] { ["sample"] } }
actor StationClockIndex {
    static let shared = StationClockIndex()
    func prime(regions: [String]) {}
}
actor Probe {
    let useDataset: Bool
    let pause: Bool
    let useCompact: Bool
    let rejectDataset: Bool
    var datasetCalls = 0
    var snapshots: [[String]] = []
    var resumed = false
    var waiting: CheckedContinuation<Void, Never>?
    var observed: CheckedContinuation<Void, Never>?
    init(useDataset: Bool = false, pause: Bool = true, useCompact: Bool = false, rejectDataset: Bool = false) {
        self.useDataset = useDataset; self.pause = pause
        self.useCompact = useCompact; self.rejectDataset = rejectDataset
    }
    func datasetCalled() { datasetCalls += 1 }
    func publish(_ rides: [RiddenRouteStore.DrawnRide]) {
        snapshots.append(rides.map(\.id).sorted())
        if snapshots.last!.contains("a") { observed?.resume(); observed = nil }
    }
    func first() async {
        if snapshots.contains(where: { $0.contains("a") }) { return }
        await withCheckedContinuation { observed = $0 }
    }
    func afterFirst() async {
        guard pause, !resumed else { return }
        await withCheckedContinuation { waiting = $0 }
    }
    func release() { resumed = true; waiting?.resume(); waiting = nil }
}
enum RiddenRouteStore {
    struct DrawnRide: Sendable { let id: String }
    // The decoder is unchanged; only resource loading and solving are doubles.
    static var datasetProbe: Probe { Tests.currentProbe }
    static func loadCachedConcurrently(_ trains: [Train], country: String) async
        -> (rides: [DrawnRide], missing: [Train]) {
        (trains.filter { $0.id == "cached" }.map { DrawnRide(id: $0.id) },
         trains.filter { $0.id != "cached" })
    }
    static func datasetRides(dataset: String, country: String, wanted: [String: Train],
        publish: @Sendable ([DrawnRide]) async -> Void) async throws -> [DrawnRide] {
        await datasetProbe.datasetCalled()
        guard datasetProbe.useDataset else { return [] }
        return try await emit(Array(wanted.values), publish: publish)
    }
    actor PrecomputedRouteRejections {
        private var ids: Set<String> = []
        func reject(_ id: String) { ids.insert(id) }
        func allowed(_ trains: [String: Train]) -> [String: Train] { trains.filter { !ids.contains($0.key) } }
    }
    static func solveMissing(_ trains: [Train], scope: RouteScope, allowLegacy: Bool = true,
        rejectPrecomputed: @Sendable (String) async -> Void = { _ in },
        publish: @Sendable ([DrawnRide]) async -> Void) async throws -> [DrawnRide] {
        if !allowLegacy {
            if datasetProbe.rejectDataset {
                for train in trains { await rejectPrecomputed(train.id) }
            }
            guard datasetProbe.useCompact else { return [] }
        }
        return try await emit(trains, publish: publish)
    }
    static func emit(_ trains: [Train], publish: @Sendable ([DrawnRide]) async -> Void)
        async throws -> [DrawnRide] {
        var result: [DrawnRide] = []
        for train in trains.sorted(by: { $0.id < $1.id }) {
            try Task.checkCancellation()
            result.append(DrawnRide(id: train.id))
            await publish(result)
            if train.id == "a" { await datasetProbe.afterFirst() }
        }
        return result
    }
__DECODE__
    static func run(_ probe: Probe) async throws -> [DrawnRide] {
        let trains = ["cached", "a", "b"].map { Train(id: $0) }
        return try await decode(wanted: Dictionary(uniqueKeysWithValues: trains.map { ($0.id, $0) })) {
            await probe.publish($0)
        }
    }
}
@main struct Tests {
    // Each scenario is completed before installing the next immutable probe.
    nonisolated(unsafe) static var currentProbe = Probe()
    static func main() async throws {
        for (dataset, compact, reject) in [(false, false, false), (true, false, false), (true, true, false), (true, false, true)] {
            let probe = Probe(useDataset: dataset, useCompact: compact, rejectDataset: reject)
            currentProbe = probe
            let task = Task { try await RiddenRouteStore.run(probe) }
            await probe.first()
            let before = await probe.snapshots
            precondition(before.last == ["a", "cached"])
            precondition(!before.contains(where: { $0.contains("b") }))
            await probe.release()
            let rides = try await task.value
            precondition(rides.map(\.id).sorted() == ["a", "b", "cached"])
            let after = await probe.snapshots
            precondition(after.last == ["a", "b", "cached"])
            if compact || reject { let calls = await probe.datasetCalls; precondition(calls == 0) }
            print("PASS dataset=\(dataset) compact=\(compact) reject=\(reject): progressive publication and inference precedence")
        }
        let probe = Probe()
        currentProbe = probe
        let task = Task { try await RiddenRouteStore.run(probe) }
        await probe.first()
        task.cancel()
        await probe.release()
        do { _ = try await task.value; preconditionFailure("cancelled solve completed") }
        catch is CancellationError {}
        let snapshots = await probe.snapshots
        precondition(snapshots.last == ["a", "cached"])
        print("PASS cancellation stops later publication and preserves completed rides")
    }
}
'''
harness = harness.replace("__DECODE__", decode)
with tempfile.TemporaryDirectory(prefix="jtm-route-progress-") as temporary:
    folder = Path(temporary)
    checks = folder / "Checks.swift"
    checks.write_text(harness)
    executable = folder / "checks"
    environment = dict(os.environ, CLANG_MODULE_CACHE_PATH=str(folder / "ModuleCache"))
    subprocess.run(["xcrun", "swiftc", "-swift-version", "6", "-parse-as-library",
                    "-module-cache-path", str(folder / "ModuleCache"), str(checks),
                    "-o", str(executable)], check=True, env=environment)
    subprocess.run([str(executable)], check=True, timeout=30)
