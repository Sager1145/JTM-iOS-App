#!/usr/bin/env python3
"""Run the production display-cache lifecycle with small controlled payloads."""
from pathlib import Path
import subprocess
import sys
import tempfile

root = Path(__file__).resolve().parents[2]
products = next(Path(sys.argv[1]).rglob('libRailCore.a')).parent
cache = (root / 'ios/RailMap/DisplayNetworkCache.swift').read_text()
a = cache.index('    private nonisolated static func build(')
b = cache.index('    struct MissingPackage:', a)
cache = cache[:a] + '''    private nonisolated static func build(
        country: String, seeded: (lineIDs: [String], parts: [[[Coordinate]]])? = nil
    ) throws -> RouteNetwork {
        try probe.build(country, seeded: seeded)
    }
''' + cache[b:]
# Only package decoding and heavy network payloads are doubled. The actor,
# admission limiter, task ownership, scope merging and retention run unchanged.
doubles = r'''
import Foundation
import Synchronization
import RailCore
final class RouteNetwork: Sendable {
    struct Line: Sendable { let lineId: String }
    let lines: [Line]
    init(lines: [Line]) { self.lines = lines }
}
enum Region: String, CaseIterable, Sendable {
    case jp, hk
    var code: String { rawValue }
}
struct RouteScope: Sendable {
    let regions: [Region]
    var graphRegions: [Region] { Region.allCases.filter { regions.contains($0) } }
    var code: String { regions[0].code }
    var key: String { graphRegions.map(\.code).joined(separator: "+") }
    var crossesBorder: Bool { graphRegions.count > 1 }
}
final class Gate: Sendable { let release = DispatchSemaphore(value: 0) }
final class Probe: Sendable {
    enum Failure: Error { case planned }
    struct State {
        var counts: [String: Int] = [:]
        var gates: [String: Gate] = [:]
        var failures: Set<String> = []
        var seeds: [String: [String]] = [:]
        var active = 0
        var peak = 0
    }
    let state = Mutex(State())
    func count(_ key: String) -> Int { state.withLock { $0.counts[key, default: 0] } }
    func gate(_ key: String, _ gate: Gate) { state.withLock { $0.gates[key] = gate } }
    func build(_ key: String, seeded: (lineIDs: [String], parts: [[[Coordinate]]])?) throws -> RouteNetwork {
        let (gate, fails) = state.withLock { state in
            state.counts[key, default: 0] += 1
            state.active += 1
            state.peak = max(state.peak, state.active)
            state.seeds[key] = seeded?.lineIDs ?? []
            return (state.gates.removeValue(forKey: key), state.failures.remove(key) != nil)
        }
        defer { state.withLock { $0.active -= 1 } }
        gate?.release.wait()
        if fails { throw Failure.planned }
        return RouteNetwork(lines: [.init(lineId: key)])
    }
}
let probe = Probe()
extension DisplayNetworkCache {
    func retainedKeys() -> [String] { networks.keys.sorted() }
    func seedKeys() -> [String] { seededParts.keys.sorted() }
    func pendingCount() -> Int { inFlight.count }
}
func wait(_ condition: @Sendable () async -> Bool) async {
    let deadline = ContinuousClock.now + .seconds(5)
    while !(await condition()) {
        precondition(ContinuousClock.now < deadline, "Synchronization timed out")
        await Task.yield()
    }
}
@main struct Checks {
    static func main() async throws {
        let cache = DisplayNetworkCache()
        let firstGate = Gate(); probe.gate("jp", firstGate)
        let first = Task { try await cache.network(country: "jp") }
        await wait { probe.count("jp") == 1 }
        let joiner = Task { try await cache.network(country: "jp") }
        first.cancel()
        let second = Task { try await cache.network(country: "hk") }
        await wait { await cache.pendingCount() == 2 }
        precondition(probe.count("hk") == 0)
        firstGate.release.signal()
        let original = try await first.value
        let joined = try await joiner.value; precondition(joined === original)
        _ = try await second.value
        precondition(probe.count("jp") == 1 && probe.state.withLock { $0.peak } == 1)
        let keys = await cache.retainedKeys(); precondition(keys.count == 1)
        print("PASS same-country coalescing, independent cancellation and serialized country builds")

        let eviction = DisplayNetworkCache()
        weak var old: RouteNetwork?
        do { let loaded = try await eviction.network(country: "jp"); old = loaded }
        precondition(old != nil)
        let replacementGate = Gate(); probe.gate("hk", replacementGate)
        let replacement = Task { try await eviction.network(country: "hk") }
        await wait { probe.count("hk") == 2 }
        precondition(old == nil, "Old cache must release before replacement allocation")
        replacementGate.release.signal()
        _ = try await replacement.value
        print("PASS cache ownership releases before the next payload is built")

        await eviction.seed(country: "jp", lineIDs: ["seed-jp"], parts: [])
        await eviction.seed(country: "other", lineIDs: ["seed-other"], parts: [])
        let seeds = await eviction.seedKeys(); precondition(seeds == ["other"])
        _ = try await eviction.network(country: "other")
        precondition(probe.state.withLock { $0.seeds["other"] } == ["seed-other"])
        let consumed = await eviction.seedKeys(); precondition(consumed.isEmpty)
        print("PASS unused layout seeds have one slot and are consumed")

        let combined = try await eviction.network(scope: .init(regions: [.hk, .jp]))
        precondition(combined.lines.map(\.lineId) == ["jp", "hk"])
        let scopeKeys = await eviction.retainedKeys(); precondition(scopeKeys == ["jp+hk"])
        let shared = try await eviction.network(scope: .init(regions: [.jp, .hk])); precondition(shared === combined)
        _ = try await eviction.network(country: "other")
        precondition(combined.lines.map(\.lineId) == ["jp", "hk"])
        print("PASS scope order, shared combined slot and active caller survive eviction")

        _ = probe.state.withLock { $0.failures.insert("failure") }
        do {
            _ = try await eviction.network(country: "failure")
            preconditionFailure("Expected build error")
        } catch Probe.Failure.planned { }
        let pending = await eviction.pendingCount(); precondition(pending == 0)
        _ = try await eviction.network(country: "failure")
        precondition(probe.count("failure") == 2)
        print("PASS failed builds release admission and retry without poisoned in-flight entries")
    }
}
'''
with tempfile.TemporaryDirectory(prefix='jtm-display-cache-') as directory:
    folder = Path(directory)
    swift = folder / 'Checks.swift'
    binary = folder / 'checks'
    swift.write_text(cache + '\n' + doubles)
    subprocess.run(['xcrun', 'swiftc', '-swift-version', '6', '-parse-as-library', '-O',
                    '-module-cache-path', str(folder / 'modules'), '-I', str(products),
                    '-L', str(products), '-lRailCore', str(swift), '-o', str(binary)], check=True)
    subprocess.run([str(binary)], check=True, timeout=25)
