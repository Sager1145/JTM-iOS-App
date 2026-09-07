#!/usr/bin/env python3
"""Exercise production route invalidation and line-cache guards with controlled inputs.
The decoder/pixel builders are doubles; load, refreshLineInputs and strokeRef
are extracted unchanged from the application. Usage: script <SPM scratch>.
"""
from pathlib import Path
import subprocess
import sys
import tempfile

root = Path(__file__).resolve().parents[2]
libs = list(Path(sys.argv[1]).rglob('libRailCore.a'))
products = libs[0].parent
route = (root / 'ios/RailMap/RiddenRouteStore.swift').read_text()
map_source = (root / 'ios/RailMap/RailMapView.swift').read_text()
def section(text, start, end):
    return text[text.index(start):text.index(end, text.index(start))]
load = section(route, '    func load(trains:', '    /// Read the last-viewed route only.')
clear = section(route, '    func clear()', '    /// Solve one journey\'s route again')
refresh = section(map_source, '            private func refreshLineInputs()', '            private func prepareStrokeReferences()')
reference = section(map_source, '            func strokeRef(', '            /// The coordinates one ride segment')
harness = r'''
import Foundation
import RailCore
@MainActor final class RideStatusCenter {
    static let shared = RideStatusCenter()
    enum Phase { case idle, loading, loaded, failed(String) }
    var routeStore: RiddenRouteStore?
    func publish(entries: [String: Int], phase: Phase) {}
    func clear() {}
}
@MainActor final class RiddenRouteStore {
    struct DrawnSegment: Sendable { let segmentIndex: Int }
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
    private var completedInputs: [String: Train] = [:]
    private var resolutionTickets: [String: UUID] = [:]
    static var decoded: [[String]] = []
    static func loadPreferred(id: String?, wanted: [String: Train]) async -> DrawnRide? { nil }
    static func decode(wanted: [String: Train], primed: DrawnRide?,
        publish: @Sendable ([DrawnRide]) async -> Void) async throws -> [DrawnRide] {
        decoded.append(wanted.keys.sorted())
        // Deliberately deliver after cancellation to test the publication guard.
        try? await Task.sleep(for: .milliseconds(20))
        let values = wanted.values.map { DrawnRide(id: $0.id, visible: $0.visible != false,
            geometryDigest: $0.number.hashValue) }
        await publish(values)
        return values
    }
    static func statusEntries(for rides: [DrawnRide], wanted: [String]) -> [String: Int] { [:] }
    static func sweepRouteCacheOnce() {}
    func wait() async { await loadTask?.value }
__LOAD__
__CLEAR__
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
    var cachedTapIndex: Int?
    var linesGeneration = 1
    var strokeRefCache: [String: (geometryKey: String, linesGeneration: Int, refs: [Int: StrokeRef])] = [:]
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
        while RiddenRouteStore.decoded.last != ["pending"] { await Task.yield() }
        store.clear(); await store.wait()
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
        map.strokeRefCache[ride.id] = ("r:3", 1, [0: StrokeRef(chainID: line.id)])
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
harness = harness.replace('__LOAD__', load).replace('__CLEAR__', clear).replace('__REFRESH__', refresh).replace('__REFERENCE__', reference)
with tempfile.TemporaryDirectory(prefix='jtm-route-caches-') as temporary:
    folder = Path(temporary)
    checks = folder / 'Checks.swift'
    checks.write_text(harness)
    executable = folder / 'checks'
    sdk = subprocess.check_output(['xcrun', '--sdk', 'macosx', '--show-sdk-path'], text=True).strip()
    subprocess.run(['xcrun', 'swiftc', '-swift-version', '6', '-parse-as-library',
                    '-sdk', sdk, '-I', str(products), str(checks), str(libs[0]),
                    '-o', str(executable)], check=True)
    subprocess.run([str(executable)], check=True, timeout=30)
