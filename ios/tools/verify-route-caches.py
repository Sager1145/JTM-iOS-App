#!/usr/bin/env python3
"""Exercise production route invalidation and line-cache guards with controlled inputs.
The decoder/pixel builders are doubles; load, clear, partial-publication helpers,
refreshLineInputs and strokeRef are extracted unchanged from the application.
The production SolverInputCache is also exercised with controlled fixture decode,
completion delays and read-only observability for ownership/order assertions.
Usage: script <SPM scratch> [RiddenRouteStore.swift].
"""
from pathlib import Path
import subprocess
import sys
import tempfile

root = Path(__file__).resolve().parents[2]
libs = list(Path(sys.argv[1]).rglob('libRailCore.a'))
products = libs[0].parent
route = (Path(sys.argv[2]) if len(sys.argv) > 2 else root / 'ios/RailMap/RiddenRouteStore.swift').read_text()
map_source = (root / 'ios/RailMap/RailMapView.swift').read_text()
def section(text, start, end):
    return text[text.index(start):text.index(end, text.index(start))]
load = section(route, '    func load(trains:', '    /// Read the last-viewed route only.')
clear = section(route, '    func clear()', '    /// The railways every current ride')
partials = route[route.index('private final class PartialRideInbox: Sendable {'):]
refresh = section(map_source, '            private func refreshLineInputs()', '            private func prepareStrokeReferences()')
reference = section(map_source, '            func strokeRef(', '            /// The coordinates one ride segment')
harness = r'''
import Foundation
import os
import RailCore
__PARTIALS__
@MainActor final class RideStatusCenter {
    static let shared = RideStatusCenter()
    enum Phase { case idle, loading, loaded, failed(String) }
    var routeStore: RiddenRouteStore?
    func publish(entries: [String: Int], phase: Phase) {}
    func publish(pendingConfirmationIDs: Set<String>) {}
    func clear() {}
}
@MainActor final class RiddenRouteStore {
    struct DrawnSegment: Sendable { let segmentIndex: Int; var partIndex = 0 }
    struct DrawnRide: Sendable {
        let id: String
        let visible: Bool
        let geometryDigest: Int
        let identity = UUID()
    }
    enum State { case idle, loading, loaded(rides: [DrawnRide]), failed(String) }
    var state = State.idle
    var rides: [DrawnRide] = []
    var visibleRides: [DrawnRide] = []
    private var loadTask: Task<Void, Never>?
    private var loadRevision = 0
    private var loadingInputs: [String: Train]?
    private var requestedOrder: [String] = []
    private var completedInputs: [String: Train] = [:]
    private var resolutionTickets: [String: UUID] = [:]
    static var decoded: [[String]] = []
    static var pendingDecoder: CheckedContinuation<Void, Never>?
    static var latePublications = 0
    static func loadPreferred(id: String?, wanted: [String: Train]) async -> DrawnRide? { nil }
    static func decode(wanted: [String: Train], requestedOrder: [String],
        preferredTrainID: String?, primed: DrawnRide?,
        publish: @Sendable ([DrawnRide]) async -> Void) async throws -> [DrawnRide] {
        decoded.append(wanted.keys.sorted())
        // Suspend explicitly so clear always precedes this cancelled decoder's
        // publication, independent of scheduler speed.
        if wanted["pending"] != nil {
            await withCheckedContinuation { pendingDecoder = $0 }
        }
        let values = wanted.values.map { DrawnRide(id: $0.id, visible: $0.visible != false,
            geometryDigest: $0.number.hashValue) }
        await publish(values)
        if wanted["pending"] != nil { latePublications += 1 }
        return values
    }
    static func statusEntries(for rides: [DrawnRide], wanted: [String]) -> [String: Int] { [:] }
    static func sweepRouteCacheOnce() {}
    func wait() async { await loadTask?.value }
    func detectTraversedLines() {}
    private func cancelResolutions() { resolutionTickets.removeAll() }
__LOAD__
__CLEAR__
}
@MainActor struct TraversedLineDetector {
    static let shared = Self()
    func publishSelected(rides: [RiddenRouteStore.DrawnRide]) {}
    func reset() {}
}
enum Region: String { case jp }
enum RailNetworkStore {
    struct Follow { let canonicalID: String }
    struct DrawnLine {
        let id: String
        let contentID = UUID()
        var continuous = true
        var follows: [Follow] = []
    }
    struct Slot { let chain: Int; let anchor: Int }
    struct Station {
        let lineID: String
        var region = Region.jp
        let slot: Slot?
    }
}
struct StrokeRef { let chainID: String }
@MainActor final class Coordinator {
    struct LineInputs: Equatable {
        let contentID: UUID
        let anchors: [Int]
        let dependencies: [String: UUID]
    }
    var lines: [RailNetworkStore.DrawnLine] = []
    var stations: [RailNetworkStore.Station] = []
    var lineInputs: [String: LineInputs] = [:]
    var matchedLineInputs: [String: LineInputs] = [:]
    var strokeBuildCache: [String: Int] = [:]
    var lineBuildCache: [String: Int] = [:]
    var ridePolylineCache: [String: Int] = [:]
    // The production coordinator invalidates through its interaction owner.
    // Keep this cache observable so the existing geometry checks can inspect it.
    var cachedTapIndex: Int?
    var interaction: Coordinator { self }
    func invalidateRideGeometry() { cachedTapIndex = nil }
    var linesGeneration = 1
    var strokeRefCache: [String: (geometryKey: String, linesGeneration: Int, refs: [String: StrokeRef])] = [:]
    var networkGeometry: Coordinator { self }
    func retainLineBuilds(withIDs ids: Set<String>) {
        strokeBuildCache = strokeBuildCache.filter { ids.contains($0.key) }
        lineBuildCache = lineBuildCache.filter { ids.contains($0.key) }
        ridePolylineCache.removeAll()
    }
    func refresh() { refreshLineInputs() }
__REFRESH__
__REFERENCE__
}
@main struct Checks {
    @MainActor static func main() async {
        func train(_ id: String, number: String = "original") -> Train {
            Train(id: id, number: number, origin: "A", destination: "B", stops: [])
        }
        let store = RiddenRouteStore()
        let a = train("a"), b = train("b")
        store.load(trains: [a, b]); await store.wait()
        let oldB = store.rides.first { $0.id == "b" }!.identity
        let edited = train("a", number: "new route")
        store.load(trains: [edited, b])
        precondition(store.rides.map(\.id) == ["b"])
        await store.wait()
        precondition(RiddenRouteStore.decoded == [["a", "b"], ["a"]])
        precondition(store.rides.first { $0.id == "b" }!.identity == oldB)
        precondition(store.rides.first { $0.id == "a" }!.geometryDigest == edited.number.hashValue)
        store.load(trains: [b, edited]); await store.wait()
        precondition(store.rides.map(\.id) == ["b", "a"] && RiddenRouteStore.decoded.count == 2)
        store.load(trains: [b]); await store.wait()
        precondition(store.rides.map(\.id) == ["b"] && RiddenRouteStore.decoded.count == 2)
        store.load(trains: [a, b]); await store.wait()
        precondition(RiddenRouteStore.decoded.last == ["a"])
        print("PASS same-ID edits decode one route; untouched identity, reorder, delete and re-add stay correct")
        store.load(trains: [train("pending")])
        while RiddenRouteStore.pendingDecoder == nil { await Task.yield() }
        store.clear()
        RiddenRouteStore.pendingDecoder?.resume()
        RiddenRouteStore.pendingDecoder = nil
        await store.wait()
        precondition(RiddenRouteStore.latePublications == 1)
        precondition(store.rides.isEmpty)
        if case .idle = store.state {} else { preconditionFailure("cancelled decoder republished") }
        print("PASS a late decoder cannot restore routes after clear")

        let map = Coordinator()
        let line = RailNetworkStore.DrawnLine(id: "jp|A#0")
        let other = RailNetworkStore.DrawnLine(id: "jp|B#0")
        map.lines = [line, other]; map.refresh()
        map.matchedLineInputs = map.lineInputs
        map.strokeBuildCache = [line.id: 1, other.id: 2]
        map.lineBuildCache = map.strokeBuildCache
        let ride = RiddenRouteStore.DrawnRide(id: "r", visible: true, geometryDigest: 3)
        let segment = RiddenRouteStore.DrawnSegment(segmentIndex: 0)
        map.strokeRefCache[ride.id] = ("r:3", 1, ["0.0": StrokeRef(chainID: line.id)])
        map.lines.append(.init(id: "jp|C#0")); map.linesGeneration += 1; map.refresh()
        precondition(map.strokeBuildCache.count == 2 && map.lineBuildCache.count == 2)
        precondition(map.strokeRef(for: segment, of: ride) != nil)
        map.lines[0] = .init(id: line.id); map.refresh()
        precondition(map.strokeBuildCache[line.id] == nil && map.strokeBuildCache[other.id] == 2)
        precondition(map.strokeRef(for: segment, of: ride) == nil)
        print("PASS unrelated lines preserve caches and refs; replaced content with the same ID invalidates both")
        map.lines = [line, other]; map.refresh(); map.matchedLineInputs = map.lineInputs
        map.strokeBuildCache = [line.id: 1, other.id: 2]
        map.lines.append(.init(id: "jp|A#1")); map.refresh()
        precondition(map.strokeBuildCache[line.id] == nil && map.strokeBuildCache[other.id] == 2)
        map.strokeBuildCache[line.id] = 1
        map.stations = [.init(lineID: "A", slot: .init(chain: 0, anchor: 12))]; map.refresh()
        precondition(map.strokeBuildCache[line.id] == nil)
        var follower = RailNetworkStore.DrawnLine(id: "jp|F#0")
        follower.follows = [.init(canonicalID: other.id)]
        map.lines.append(follower); map.refresh(); map.strokeBuildCache[follower.id] = 3
        map.lines[1] = .init(id: other.id); map.refresh()
        precondition(map.strokeBuildCache[follower.id] == nil)
        print("PASS neighboring chains, station anchors and canonical follow dependencies invalidate their consumers")
    }
}
'''
harness = harness.replace('__PARTIALS__', partials).replace('__LOAD__', load).replace('__CLEAR__', clear).replace('__REFRESH__', refresh).replace('__REFERENCE__', reference)
with tempfile.TemporaryDirectory(prefix='jtm-route-caches-') as temporary:
    folder = Path(temporary)
    checks = folder / 'Checks.swift'
    checks.write_text(harness)
    executable = folder / 'checks'
    sdk = subprocess.check_output(['xcrun', '--sdk', 'macosx', '--show-sdk-path'], text=True).strip()
    subprocess.run(['xcrun', 'swiftc', '-swift-version', '6', '-parse-as-library',
                    '-sdk', sdk, '-module-cache-path', str(folder / 'modules'),
                    '-I', str(products), str(checks), str(libs[0]),
                    '-o', str(executable)], check=True)
    subprocess.run([str(executable)], check=True, timeout=30)

# Run the production immutable-input actor separately. Decoding is a controlled
# fixture double; only completion delays and read-only observability are added
# to its extracted source to make ordering and ARC assertions deterministic.
input_actor = section(route, '    private actor SolverInputCache {',
                      '    private nonisolated static func prepareSolverInputs')
input_actor = input_actor.replace('    private actor SolverInputCache {', '    actor SolverInputCache {', 1)
input_actor = input_actor.replace('let inputs = try await task.value',
                                'let inputs = try await task.value\n                await CompletionDelay.shared.waitIfHeld(key)', 2)
input_actor = input_actor.replace('if let task = running[key] {',
                                'if let task = running[key] {\n                observedWaiters.append(key)', 1)
position = input_actor.rfind('    }')
input_actor = input_actor[:position] + r'''
        private var observedWaiters: [String] = []
        func checkedWaiters(_ key: String) -> Int { observedWaiters.filter { $0 == key }.count }
        func checkedRetainedKeys() -> [String] { completed.map { [$0.key] } ?? [] }
        func checkedRunningKeys() -> Set<String> { Set(running.keys) }
''' + input_actor[position:]
input_harness = r'''
import Foundation
import RailCore

struct RouteScope: Sendable { let key: String }
struct RevisionSource: Sendable { func revision(for key: String) -> String { "fixture-v1" } }
enum DecodeFailure: Error { case expected }

final class BuildProbe: @unchecked Sendable {
    static let shared = BuildProbe()
    private let condition = NSCondition()
    private var held: Set<String> = []
    private var failures: Set<String> = []
    private var counts: [String: Int] = [:]
    private var active = 0
    private var maximum = 0
    private weak var previous: SolverInputs?
    private var releaseTarget: String?
    private var releasedBeforeDecode = false
    func hold(_ key: String) { condition.lock(); held.insert(key); condition.unlock() }
    func release(_ key: String) { condition.lock(); held.remove(key); condition.broadcast(); condition.unlock() }
    func fail(_ key: String) { condition.lock(); failures.insert(key); condition.unlock() }
    func count(_ key: String) -> Int {
        condition.lock(); defer { condition.unlock() }; return counts[key, default: 0]
    }
    func maximumActive() -> Int { condition.lock(); defer { condition.unlock() }; return maximum }
    func expectRelease(_ inputs: SolverInputs, before key: String) {
        condition.lock(); previous = inputs; releaseTarget = key; condition.unlock()
    }
    func didReleaseBeforeDecode() -> Bool {
        condition.lock(); defer { condition.unlock() }; return releasedBeforeDecode
    }
    func decode(_ scope: RouteScope) throws -> SolverInputs {
        condition.lock()
        counts[scope.key, default: 0] += 1
        active += 1
        maximum = max(maximum, active)
        if releaseTarget == scope.key { releasedBeforeDecode = previous == nil }
        while held.contains(scope.key) { condition.wait() }
        let shouldFail = failures.remove(scope.key) != nil
        condition.unlock()
        defer { condition.lock(); active -= 1; condition.unlock() }
        if shouldFail { throw DecodeFailure.expected }
        return SolverInputs(scope: scope.key)
    }
}

// A reference owner makes cache ARC observable without altering source data.
final class SolverInputs: @unchecked Sendable {
    let scope: String
    let sections: [RouteGraph.SectionFeature]
    let stationCollection = Stations.FeatureCollection(features: [])
    let physicalJunctions: [RouteGraph.PhysicalJunction] = []
    init(scope: String) {
        self.scope = scope
        sections = [.init(properties: .init(lineName: scope, operator: "Fixture",
            validFrom: "1900-01-01", validTo: "2000-01-01", historyId: "fixture-history"),
            lines: [[Coordinate(lon: 139, lat: 35), Coordinate(lon: 139.01, lat: 35)]])]
    }
}

actor CompletionDelay {
    static let shared = CompletionDelay()
    private var held: Set<String> = []
    private var continuations: [String: [CheckedContinuation<Void, Never>]] = [:]
    func hold(_ key: String) { held.insert(key) }
    func waitIfHeld(_ key: String) async {
        guard held.contains(key) else { return }
        await withCheckedContinuation { continuations[key, default: []].append($0) }
    }
    func waiting(_ key: String) -> Int { continuations[key]?.count ?? 0 }
    func release(_ key: String) {
        held.remove(key)
        for continuation in continuations.removeValue(forKey: key) ?? [] { continuation.resume() }
    }
}

enum RiddenRouteStore {
    static let resourceRevisions: RevisionSource? = .init()
    static func prepareSolverInputs(scope: RouteScope) throws -> SolverInputs {
        try BuildProbe.shared.decode(scope)
    }
__INPUT_ACTOR__
}

@main struct InputChecks {
    static func waitUntil(_ predicate: @Sendable () async -> Bool) async {
        while !(await predicate()) { await Task.yield() }
    }
    static func request(_ cache: RiddenRouteStore.SolverInputCache, _ key: String) -> Task<SolverInputs, Error> {
        Task { try await cache.inputs(scope: .init(key: key)) }
    }
    static func seedARC(_ cache: RiddenRouteStore.SolverInputCache) async throws {
        let inputs = try await cache.inputs(scope: .init(key: "arc-old"))
        BuildProbe.shared.expectRelease(inputs, before: "arc-new")
    }
    static func main() async throws {
        let cache = RiddenRouteStore.SolverInputCache()
        let probe = BuildProbe.shared
        probe.hold("same")
        let first = request(cache, "same")
        await waitUntil { probe.count("same") == 1 }
        let second = request(cache, "same")
        let cancelled = request(cache, "same")
        await waitUntil { await cache.checkedWaiters("same:fixture-v1") == 2 }
        cancelled.cancel()
        probe.release("same")
        let a = try await first.value, b = try await second.value
        precondition(a === b && probe.count("same") == 1)
        precondition(a.sections[0].properties.historyId == "fixture-history")
        precondition(a.sections[0].properties.validTo == "2000-01-01")
        precondition(a.sections[0].lines[0].count == 2)
        do { _ = try await cancelled.value; preconditionFailure("cancelled waiter returned inputs") }
        catch is CancellationError {}
        let warm = try await cache.inputs(scope: .init(key: "same"))
        precondition(warm === a && probe.count("same") == 1)
        let cancelledAtEntry = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try await cache.inputs(scope: .init(key: "never"))
        }
        do { _ = try await cancelledAtEntry.value; preconditionFailure("cancelled entry decoded") }
        catch is CancellationError {}
        precondition(probe.count("never") == 0)
        print("PASS production input actor coalesces same-scope requests; cancellation stays local; immutable history/geometry and warm identity survive")

        probe.hold("cancel-owner")
        let cancelledOwner = request(cache, "cancel-owner")
        await waitUntil { probe.count("cancel-owner") == 1 }
        let survivingWaiter = request(cache, "cancel-owner")
        await waitUntil { await cache.checkedWaiters("cancel-owner:fixture-v1") == 1 }
        cancelledOwner.cancel()
        probe.release("cancel-owner")
        do { _ = try await cancelledOwner.value; preconditionFailure("cancelled owner returned inputs") }
        catch is CancellationError {}
        let survivor = try await survivingWaiter.value
        let cancelOwnerKeys = await cache.checkedRetainedKeys()
        precondition(survivor.scope == "cancel-owner" && probe.count("cancel-owner") == 1)
        precondition(cancelOwnerKeys == ["cancel-owner:fixture-v1"])
        print("PASS cancelling the initiating caller preserves the shared build and surviving waiter")

        try await seedARC(cache)
        _ = try await cache.inputs(scope: .init(key: "arc-new"))
        precondition(probe.didReleaseBeforeDecode())
        let arcKeys = await cache.checkedRetainedKeys()
        precondition(arcKeys == ["arc-new:fixture-v1"])
        print("PASS one completed input owner; prior cache owner releases before replacement decoding")

        for key in ["serial-a", "serial-b", "serial-c"] { probe.hold(key) }
        let serialA = request(cache, "serial-a")
        await waitUntil { probe.count("serial-a") == 1 }
        let serialB = request(cache, "serial-b")
        await waitUntil { await cache.checkedRunningKeys().contains("serial-b:fixture-v1") }
        let serialC = request(cache, "serial-c")
        await waitUntil { await cache.checkedRunningKeys().contains("serial-c:fixture-v1") }
        precondition(probe.count("serial-b") == 0 && probe.count("serial-c") == 0)
        probe.release("serial-a")
        await waitUntil { probe.count("serial-b") == 1 }
        precondition(probe.count("serial-c") == 0)
        probe.release("serial-b")
        await waitUntil { probe.count("serial-c") == 1 }
        probe.release("serial-c")
        let values = try await [serialA.value, serialB.value, serialC.value]
        precondition(values.map(\.scope) == ["serial-a", "serial-b", "serial-c"])
        precondition(probe.maximumActive() == 1)
        let serialKeys = await cache.checkedRetainedKeys()
        precondition(serialKeys == ["serial-c:fixture-v1"])
        print("PASS different-scope decoder builds never overlap; queued results retain complete caller data")

        // Delay old await continuations until a newer result is already cached.
        // The source actor must not republish the old value on their return.
        await CompletionDelay.shared.hold("late-a:fixture-v1")
        probe.hold("late-a")
        let lateOwner = request(cache, "late-a")
        await waitUntil { probe.count("late-a") == 1 }
        let lateWaiter = request(cache, "late-a")
        await waitUntil { await cache.checkedWaiters("late-a:fixture-v1") == 1 }
        probe.release("late-a")
        await waitUntil { await CompletionDelay.shared.waiting("late-a:fixture-v1") == 2 }
        _ = try await cache.inputs(scope: .init(key: "late-b"))
        await CompletionDelay.shared.release("late-a:fixture-v1")
        let oldOwner = try await lateOwner.value, oldWaiter = try await lateWaiter.value
        precondition(oldOwner === oldWaiter && oldOwner.scope == "late-a")
        let lateKeys = await cache.checkedRetainedKeys()
        precondition(lateKeys == ["late-b:fixture-v1"])
        print("PASS late owner and shared waiter return old data without restoring an evicted completed slot")

        probe.hold("retry"); probe.fail("retry")
        let failedOwner = request(cache, "retry")
        await waitUntil { probe.count("retry") == 1 }
        let failedWaiter = request(cache, "retry")
        await waitUntil { await cache.checkedWaiters("retry:fixture-v1") == 1 }
        probe.release("retry")
        for task in [failedOwner, failedWaiter] {
            do { _ = try await task.value; preconditionFailure("decoder failure disappeared") }
            catch DecodeFailure.expected {}
        }
        let failedRunningKeys = await cache.checkedRunningKeys()
        let failedRetainedKeys = await cache.checkedRetainedKeys()
        precondition(failedRunningKeys.isEmpty && failedRetainedKeys.isEmpty)
        let retried = try await cache.inputs(scope: .init(key: "retry"))
        precondition(retried.scope == "retry" && probe.count("retry") == 2)
        precondition(probe.maximumActive() == 1)
        print("PASS shared decoder failures clear in-flight state; the next request retries successfully")
    }
}
'''
input_harness = input_harness.replace('__INPUT_ACTOR__', input_actor)
with tempfile.TemporaryDirectory(prefix='jtm-solver-input-cache-') as temporary:
    folder = Path(temporary)
    checks = folder / 'Checks.swift'
    checks.write_text(input_harness)
    executable = folder / 'checks'
    subprocess.run(['xcrun', 'swiftc', '-swift-version', '6', '-parse-as-library',
                    '-sdk', sdk, '-module-cache-path', str(folder / 'modules'),
                    '-I', str(products), str(checks), str(libs[0]),
                    '-o', str(executable)], check=True)
    subprocess.run([str(executable)], check=True, timeout=30)
