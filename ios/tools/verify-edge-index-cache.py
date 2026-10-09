#!/usr/bin/env python3
"""Exercise actual statistics-cache ownership with controlled heavy payloads."""
from pathlib import Path
import subprocess
import tempfile

root = Path(__file__).resolve().parents[2]
source = (root / 'ios/RailMap/EdgeIndexCache.swift').read_text()
actor = source[source.index('actor EdgeIndexCache {'):source.index('    nonisolated static func merge(')]
ready_start = source.index('    func ready(country:')
ready_end = source.index('    private nonisolated static func build(', ready_start)
actor += source[ready_start:ready_end]
actor += r'''
    nonisolated static func build(country: String) throws -> Statistics.EdgeIndex {
        try probe.build(country)
    }
    nonisolated static func appendingVector(to index: Statistics.EdgeIndex, network: String) -> Statistics.EdgeIndex {
        let value = Statistics.EdgeIndex(parts: index.parts, km: index.km + [99])
        probe.state.withLock { $0.latest[index.parts[0]] = WeakIndex(value: value) }
        return value
    }
    nonisolated static func merge(_ parts: [(country: String, index: Statistics.EdgeIndex)]) -> Statistics.EdgeIndex {
        if parts.count == 1 { return parts[0].index }
        return Statistics.EdgeIndex(parts: parts.map(\.country), km: parts.flatMap { $0.index.km })
    }
}
'''
limiter = (root / 'ios/RailKit/Sources/RailCore/RouteSolveLimiter.swift').read_text()
doubles = r'''
import Foundation
import Synchronization

enum Statistics {
    final class EdgeIndex: Sendable {
        let parts: [String]
        let km: [Double]
        let denominator: Int?
        init(parts: [String], km: [Double], denominator: Int? = nil) {
            self.parts = parts; self.km = km; self.denominator = denominator
        }
    }
}
enum JapanAreaLeaf: String, Sendable { case hokkaido, tohoku }
struct Region { let code: String; static let jp = Region(code: "jp") }
struct JapanAreaGrid: Sendable {
    static let shared = Self()
    static func restricting(_ index: Statistics.EdgeIndex, country: String,
        to leaves: Set<JapanAreaLeaf>, grid: Self, denominatorEdgeCount: Int) -> Statistics.EdgeIndex {
        Statistics.EdgeIndex(parts: index.parts, km: index.km, denominator: denominatorEdgeCount)
    }
}
final class Gate: Sendable { let release = DispatchSemaphore(value: 0) }
struct WeakIndex: Sendable { weak var value: Statistics.EdgeIndex? }
final class Probe: Sendable {
    enum Failure: Error { case planned }
    struct State {
        var counts: [String: Int] = [:]
        var latest: [String: WeakIndex] = [:]
        var buildGates: [String: Gate] = [:]
        var displayGates: [String: Gate] = [:]
        var displayStarted: Set<String> = []
        var failures: Set<String> = []
    }
    let state = Mutex(State())
    func count(_ country: String) -> Int { state.withLock { $0.counts[country, default: 0] } }
    func build(_ country: String) throws -> Statistics.EdgeIndex {
        let (gate, fail) = state.withLock { s in
            s.counts[country, default: 0] += 1
            return (s.buildGates.removeValue(forKey: country), s.failures.remove(country) != nil)
        }
        gate?.release.wait()
        if fail { throw Failure.planned }
        return Statistics.EdgeIndex(parts: [country], km: [1, 2])
    }
    func display(_ country: String) -> String {
        let gate = state.withLock { s in s.displayStarted.insert(country); return s.displayGates.removeValue(forKey: country) }
        gate?.release.wait()
        return country
    }
}
let probe = Probe()
struct DisplayNetworkCache: Sendable {
    static let shared = Self()
    func network(country: String) async throws -> String { probe.display(country) }
}
extension EdgeIndexCache {
    func retainedKey() -> String? {
        guard let completed else { return nil }
        switch completed.key {
        case .country(let key): return key
        case .merged(let countries, _): return countries.joined(separator: "+")
        case .scoped(let countries, let leaves): return countries.joined(separator: "+") + ":" + leaves
        }
    }
    func pendingCount() -> Int { inFlight.count }
}
func wait(_ condition: @Sendable () async -> Bool) async {
    let deadline = ContinuousClock.now + .seconds(8)
    while !(await condition()) {
        precondition(ContinuousClock.now < deadline, "Synchronization timed out")
        await Task.yield()
    }
}
@main struct Checks {
    static func main() async throws {
        let cache = EdgeIndexCache()
        let displayGate = Gate()
        probe.state.withLock { $0.displayGates["a"] = displayGate }
        let first = Task { try await cache.index(country: "a") }
        await wait { probe.state.withLock { $0.displayStarted.contains("a") } }
        let joined = Task { try await cache.index(country: "a") }
        first.cancel()
        let second = Task { try await cache.index(country: "b") }
        await wait { await cache.pendingCount() == 2 }
        precondition(probe.count("b") == 0, "Permit must span the display-network await")
        displayGate.release.signal()
        let firstValue = try await first.value
        let secondValue = try await second.value
        let joinedValue = try await joined.value
        precondition(firstValue === joinedValue && firstValue.parts == ["a"])
        precondition(secondValue.parts == ["b"] && probe.count("a") == 1)
        let retained = await cache.retainedKey()
        precondition(retained == "b|attribution-policy-v2")
        print("PASS country coalescing, cancelled waiter, serialized build including display await, no stale reinsert")

        let eviction = EdgeIndexCache()
        weak var old: Statistics.EdgeIndex?
        do { let value = try await eviction.index(country: "old"); old = value }
        precondition(old != nil)
        let buildGate = Gate(); probe.state.withLock { $0.buildGates["next"] = buildGate }
        let replacement = Task { try await eviction.index(country: "next") }
        await wait { probe.count("next") == 1 }
        precondition(old == nil, "Evicted pixels/index must release before replacement allocation")
        buildGate.release.signal(); _ = try await replacement.value
        print("PASS completed cache ARC release before replacement build")

        let mergeCache = EdgeIndexCache()
        let merged = try await mergeCache.merged(countries: ["jp", "tw", "jp"])
        precondition(merged.parts == ["jp", "tw", "jp"] && merged.km == [1,2,99,1,2,99,1,2,99])
        let jpCount = probe.count("jp"), twCount = probe.count("tw")
        let warmMerge = try await mergeCache.merged(countries: ["jp", "tw", "jp"])
        precondition(warmMerge === merged && probe.count("jp") == jpCount && probe.count("tw") == twCount)
        print("PASS caller order and duplicate countries, shared completed merge hit")

        let scopeCache = EdgeIndexCache()
        let scope = try await scopeCache.scoped(countries: ["jp"], japanLeaves: [.hokkaido])
        precondition(scope.denominator == 2 && scope.km.count == 3)
        let count = probe.count("jp")
        let warmScope = try await scopeCache.scoped(countries: ["jp"], japanLeaves: [.hokkaido])
        precondition(warmScope === scope && probe.count("jp") == count)
        _ = try await scopeCache.index(country: "tw")
        let rebuiltScope = try await scopeCache.scoped(countries: ["jp"], japanLeaves: [.tohoku])
        precondition(rebuiltScope.denominator == 2 && rebuiltScope.km.count == 3)
        print("PASS scope cache hit and N02 denominator preserved across country eviction")

        let clipLifetime = EdgeIndexCache()
        let otherGate = Gate(); probe.state.withLock { $0.buildGates["other"] = otherGate }
        let clippedRequest = Task { try await clipLifetime.scoped(countries: ["jp", "other"], japanLeaves: [.hokkaido]) }
        await wait { probe.count("other") == 1 }
        precondition(probe.state.withLock { $0.latest["jp"]?.value == nil },
            "Full Japan result must not remain in the suspended scope frame")
        otherGate.release.signal()
        let combined = try await clippedRequest.value
        precondition(combined.parts == ["jp", "other"])
        print("PASS full country owner released before waiting for another scoped country")

        let failed = EdgeIndexCache()
        _ = probe.state.withLock { $0.failures.insert("failure") }
        do { _ = try await failed.index(country: "failure"); preconditionFailure("Expected error") }
        catch Probe.Failure.planned {}
        let pending = await failed.pendingCount(); precondition(pending == 0)
        let retry = try await failed.index(country: "failure")
        precondition(retry.parts == ["failure"] && probe.count("failure") == 2)
        print("PASS error clears in-flight entry and releases admission for retry")

        let singleCache = EdgeIndexCache()
        let country = try await singleCache.index(country: "single")
        let ready = await singleCache.ready(country: "single"); precondition(ready === country)
        let missing = await singleCache.ready(country: "missing"); precondition(missing == nil)
        let single = try await singleCache.merged(countries: ["single"])
        precondition(single === country)
        let empty = try await singleCache.merged(countries: [])
        precondition(empty.parts.isEmpty && empty.km.isEmpty)
        print("PASS single-country reuse and empty merge")
    }
}
'''
with tempfile.TemporaryDirectory(prefix='jtm-edge-cache-') as directory:
    path = Path(directory)
    swift = path / 'checks.swift'
    swift.write_text(doubles + limiter + actor)
    subprocess.run(['swiftc', '-swift-version', '6', '-parse-as-library', '-module-cache-path', str(path/'modules'), str(swift), '-o', str(path/'checks')], check=True)
    subprocess.run([str(path/'checks')], check=True, timeout=35)
