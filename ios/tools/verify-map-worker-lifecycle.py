#!/usr/bin/env python3
"""Exercise production render worker admission, publication and route-cache reuse."""
from pathlib import Path
import subprocess
import tempfile

root = Path(__file__).resolve().parents[2]
view = (root / 'ios/RailMap/RailMapView.swift').read_text()
rendering = (root / 'ios/RailMap/MapNetworkRendering.swift').read_text()
limiter = (root / 'ios/RailKit/Sources/RailCore/RouteSolveLimiter.swift').read_text()


def section(source, start, end):
    a = source.index(start)
    return source[a:source.index(end, a)]


cache = section(rendering, '@MainActor\nfinal class MapNetworkGeometryCache',
                '/// The installed overlay identities')
retain = section(view, '            private func retainRidePolylines(',
                 '            /// Revalidate only the inputs')
matching = section(view, '            private func prepareStrokeReferences()',
                   '            /// Reads prepared results')
cancel_geometry = section(view, '            private func cancelGeometryPreparation()',
                          '            /// Prepare immutable line geometry')
preparation = section(view, '            private func prepareNetworkGeometry(',
                      '            private func rebuild(on mapView:')
geometry_workers = section(preparation, '                let limiter = renderWorkLimiter',
                          '                return false')

reconciliation = section(rendering, '@MainActor\nstruct MapOverlayReconciliation',
                         '/// Builds network overlay batches')
installer_header = section(rendering, '@MainActor\nfinal class MapOverlayInstaller',
                           '    func networkOverlays(')
installer_install = section(rendering, '    func install(\n', '\n#if DEBUG')
installer = (installer_header + installer_install).replace('MKMapView', 'TestMapView')

# Production task closures, cache and limiter execute unchanged. Only expensive
# geometry/index computation and UI callbacks are doubled, to force overlap and
# cancellation at exact points without a simulator or timing-dependent sleeps.
doubles = r'''
import Foundation
import MapKit
import Synchronization

final class WorkGate: Sendable {
    let release = DispatchSemaphore(value: 0)
}
final class Probe: Sendable {
    struct State {
        var active = 0
        var peak = 0
        var counts: [String: Int] = [:]
        var gates: [String: WorkGate] = [:]
        var materialized: [Int] = []
    }
    let state = Mutex(State())
    func gate(_ kind: String, _ gate: WorkGate) {
        state.withLock { $0.gates[kind] = gate }
    }
    func run(_ kind: String) -> Int {
        let (gate, revision) = state.withLock { state in
            state.active += 1
            state.peak = max(state.peak, state.active)
            state.counts[kind, default: 0] += 1
            return (state.gates.removeValue(forKey: kind), state.counts[kind]!)
        }
        gate?.release.wait() // Deliberately finishes synchronous work after cancellation.
        state.withLock { $0.active -= 1 }
        return revision
    }
    func count(_ kind: String) -> Int { state.withLock { $0.counts[kind] ?? 0 } }
    var peak: Int { state.withLock { $0.peak } }
    func reset() { state.withLock { $0 = State() } }
}
let probe = Probe()
enum Region: String, Sendable { case jp }
enum RailNetworkStore {
    struct DrawnLine: Sendable { let id: String; var continuous = true }
    struct Slot: Sendable { let chain: Int; let anchor: Int }
    struct DrawnStation: Sendable {
        let slot: Slot?
        let region = Region.jp
        let lineID: String
    }
}
enum RiddenRouteStore {
    struct DrawnSegment: Sendable {
        let segmentIndex: Int
        let partIndex: Int
        let coordinates: [Int] = [1, 2]
    }
    struct DrawnRide: Sendable {
        let id: String
        let geometryDigest: Int
        var segments: [DrawnSegment] = [.init(segmentIndex: 0, partIndex: 0)]
    }
}
struct ChainRef: Sendable {
    let id: String
    let points: [Int]
    let measures: [Double]
    let anchors: [Int]
}
struct StrokeRef: Equatable, Sendable { let chainID: String }
enum StrokeRide {
    struct Index: Sendable {
        let revision: Int
        init(chains: [ChainRef]) { revision = probe.run("index") }
        func resolve(segment: [Int]) -> StrokeRef? { .init(chainID: "line") }
    }
}
func joinedChainCoordinates(of line: RailNetworkStore.DrawnLine) -> (points: [Int], measures: [Double]) {
    ([1, 2], [0, 1])
}
enum ContinuousStroke { struct Stroke: Sendable { let revision: Int } }
struct ContinuousStrokeBuild: Sendable { let revision: Int }
struct LineBuild { let revision: Int }
enum MapLineGeometry {
    struct PreparedGeometry: Sendable { let revision: Int }
    struct Prepared {
        let strokes: [String: ContinuousStrokeBuild]
        let lines: [String: LineBuild]
    }
    static func prepare(
        lines: [RailNetworkStore.DrawnLine], strokes: [RailNetworkStore.DrawnLine],
        allLines: [String: RailNetworkStore.DrawnLine], anchors: [String: [Int]],
        cachedStrokes: [String: ContinuousStrokeBuild], mapScale: Double, scale: CGFloat,
        laneScale: Double, era: Int, rideDate: String?, todayByRegion: [String: String]
    ) throws -> PreparedGeometry {
        .init(revision: probe.run("geometry"))
    }
    @MainActor static func materialize(_ geometry: PreparedGeometry) -> Prepared {
        probe.state.withLock { $0.materialized.append(geometry.revision) }
        return .init(strokes: [:], lines: ["line": .init(revision: geometry.revision)])
    }
}
@MainActor final class MapView {}
@MainActor final class Playback { var isActive = false }
@MainActor final class PlaybackLayer { var lastSnapshot: Int? }
struct BuildState { mutating func invalidateZoomBucket() {} }
@MainActor final class Coordinator {
    struct LineInputs: Equatable, Sendable { let revision: Int }
    typealias StrokeMatches =
        [String: (geometryKey: String, linesGeneration: Int, refs: [String: StrokeRef])]
    var mapView: MapView? = MapView()
    var lines = [RailNetworkStore.DrawnLine(id: "line")]
    var stations: [RailNetworkStore.DrawnStation] = []
    var rides: [RiddenRouteStore.DrawnRide] = []
    var linesGeneration = 1
    var lineInputs: [String: LineInputs] = [:]
    var strokeRefCache: StrokeMatches = [:]
    var matchingTask: Task<Void, Never>?
    var matchingRevision = 0
    var pendingStrokeRefs: (revision: Int, refs: StrokeMatches, inputs: [String: LineInputs])?
    var preparedStrokeIndex: (generation: Int, index: StrokeRide.Index)?
    var renderWorkLimiter = RouteSolveLimiter(limit: 1)
    var networkBuildState = BuildState()
    let networkGeometry = MapNetworkGeometryCache()
    var geometryPreparation: Task<Void, Never>?
    var geometryPreparationID = UUID()
    var geometryPreparationKey: String?
    let playback: Playback? = nil
    let playbackLayer = PlaybackLayer()
    var rebuildDeferredByPlayback = false
    var rebuildDeferredByGesture = false
    var isManipulating = false
    var rebuilds = 0
    func rebuild(on mapView: MapView) { rebuilds += 1 }
    func match() { prepareStrokeReferences() }
    func retain(excludingStrokeFor ids: Set<String> = []) { retainRidePolylines(excludingStrokeFor: ids) }
__RETAIN__
__MATCHING__
__CANCEL__
    func geometry(key: String) {
        cancelGeometryPreparation()
        networkGeometry.beginFrame(key: key)
        let mapView = self.mapView!
        let requestID = UUID()
        geometryPreparationID = requestID
        geometryPreparationKey = key
        let missingLines = lines, missingStrokes = lines
        let byID = ["line": lines[0]]
        let anchors: [String: [Int]] = [:]
        let cachedStrokes = networkGeometry.preparedStrokes
        let mapScale = 1.0
        let scale: CGFloat = 1
        let laneLOD = (scale: 1.0, bucket: 0)
        let era = 0
        let rideDate: String? = nil
        let todayByRegion: [String: String] = [:]
__GEOMETRY__
    }
}
'''
installer_doubles = r'''
@MainActor final class MapOverlayStyles {
    struct Style { var alpha: CGFloat = 1 }
    var values: [String: Style] = [:]
    subscript(key: String) -> Style? {
        get { values[key] }
        set { values[key] = newValue }
    }
    func forget(_ overlays: [MKOverlay]) {
        for overlay in overlays { if let key = overlay.title ?? nil { values[key] = nil } }
    }
    func presentedAlpha(forKey key: String) -> CGFloat { values[key]?.alpha ?? 1 }
    func hasRenderer(forKey key: String) -> Bool { false } // This stub never creates renderers.
    func rekey(from old: String, to new: String) { values[new] = values.removeValue(forKey: old) }
    func forgetRenderer(forKey key: String) {}
    func forgetStyle(forKey key: String) { values[key] = nil }
    func animateOpacity(forKey key: String, duration: TimeInterval,
                        fromAlpha: CGFloat? = nil, completion: (() -> Void)? = nil) {}
    func rescale(to scale: CGFloat, alphaTransitionDuration: TimeInterval?) {}
}
@MainActor final class TestMapView {
    var mounted: [MKOverlay] = []
    var exchanges = 0
    var ignored: Set<ObjectIdentifier> = []
    func overlays(in level: MKOverlayLevel) -> [MKOverlay] { mounted }
    func removeOverlay(_ overlay: MKOverlay) { mounted.removeAll { $0 === overlay } }
    func removeOverlays(_ overlays: [MKOverlay]) {
        let ids = Set(overlays.map(ObjectIdentifier.init))
        mounted.removeAll { ids.contains(ObjectIdentifier($0)) }
    }
    func addOverlays(_ overlays: [MKOverlay], level: MKOverlayLevel) {
        for overlay in overlays where !ignored.contains(ObjectIdentifier(overlay)) {
            if !mounted.contains(where: { $0 === overlay }) { mounted.append(overlay) }
        }
    }
    func exchangeOverlay(_ first: MKOverlay, with second: MKOverlay) {
        exchanges += 1
        let a = mounted.firstIndex { $0 === first }!, b = mounted.firstIndex { $0 === second }!
        mounted.swapAt(a, b)
    }
}
@MainActor func checkInstaller() {
    func batch(_ key: String) -> MKMultiPolyline {
        let coordinates = [CLLocationCoordinate2D(latitude: 35, longitude: 139),
                           CLLocationCoordinate2D(latitude: 36, longitude: 140)]
        let result = MKMultiPolyline([MKPolyline(coordinates: coordinates, count: 2)])
        result.title = key
        return result
    }
    func ordered(_ map: TestMapView, _ expected: [MKOverlay]) {
        precondition(map.mounted.count == expected.count)
        precondition(zip(map.mounted, expected).allSatisfy { $0 === $1 })
    }
    let map = TestMapView(), styles = MapOverlayStyles()
    let installer = MapOverlayInstaller(styles: styles)
    let a = batch("ride|a"), b = batch("ride|b"), absent = batch("network|absent")
    map.mounted = [b, a]
    map.ignored = [ObjectIdentifier(absent)]
    installer.install([absent, a, a, b], replacing: installer.reconciliation(on: map), scale: 1, on: map)
    ordered(map, [a, b]) // Previous code indexes position 2 in this two-overlay snapshot.
    installer.install([b, a], replacing: installer.reconciliation(on: map), scale: 1, on: map)
    ordered(map, [b, a]) // Ordinary selection reordering remains exact.
    let staleReconciliation = installer.reconciliation(on: map)
    map.mounted = [b] // An old identity is absent from MapKit despite the previous reconciliation.
    installer.install([a, b], replacing: staleReconciliation, scale: 1, on: map)
    ordered(map, [b])

    let network = batch("network|old")
    styles["network|old"] = .init()
    map.mounted = [network, a, b]
    installer.install([a, b], replacing: installer.reconciliation(on: map), scale: 1, on: map,
                      detailTransitionDuration: 1)
    ordered(map, [network, a, b]) // Retiring network remains under the ride stack.
    precondition((network.title ?? "")?.hasPrefix("retiring|") == true)
    let newNetwork = batch("network|new")
    installer.install([newNetwork, absent, b, b, a], replacing: installer.reconciliation(on: map),
                      scale: 1, on: map)
    ordered(map, [newNetwork, network, b, a])
    installer.install([newNetwork, a, b], replacing: installer.reconciliation(on: map), scale: 1, on: map)
    ordered(map, [newNetwork, network, a, b])
    installer.removeRetiring(on: map)
    ordered(map, [newNetwork, a, b])
    let largeDeck = (0..<287).flatMap { index in
        [batch("ride|\(index)"), batch("stations|\(index)")]
    }
    installer.install(largeDeck, replacing: installer.reconciliation(on: map), scale: 1, on: map)
    ordered(map, largeDeck)
    let settledExchanges = map.exchanges
    for _ in 0..<3 {
        installer.install(largeDeck, replacing: installer.reconciliation(on: map), scale: 1, on: map)
        ordered(map, largeDeck)
    }
    precondition(map.exchanges == settledExchanges,
                 "Unchanged interleaved 287-journey deck must not reorder mounted overlays")
    print("PASS actual installer: ignored/missing and duplicate overlays; normal selection order and retiring stack")
}
'''

checks = r'''
@main struct Checks {
    @MainActor static func waitUntil(_ description: String, _ condition: () async -> Bool) async {
        let deadline = ContinuousClock.now + .seconds(10)
        while !(await condition()) {
            precondition(ContinuousClock.now < deadline, "Timed out: \(description)")
            await Task.yield()
        }
    }
    @MainActor static func main() async {
        checkInstaller()
        let c = Coordinator()
        let a = RiddenRouteStore.DrawnRide(id: "a|id", geometryDigest: 1)
        let b = RiddenRouteStore.DrawnRide(id: "b", geometryDigest: 2)
        func key(_ ride: RiddenRouteStore.DrawnRide, stroke: Bool = false) -> String {
            MapNetworkGeometryCache.ridePolylineKey(rideID: ride.id, geometryDigest: ride.geometryDigest,
                segmentIndex: 0, partIndex: 0, usesStroke: stroke)
        }
        func polyline() -> MKPolyline {
            let points = [CLLocationCoordinate2D(latitude: 35, longitude: 139),
                          CLLocationCoordinate2D(latitude: 36, longitude: 140)]
            return MKPolyline(coordinates: points, count: 2)
        }
        c.networkGeometry.beginFrame(key: "camera")
        c.rides = [a]
        let original = polyline(), stroke = polyline()
        c.networkGeometry.storeRidePolyline(original, for: key(a))
        c.networkGeometry.storeRidePolyline(stroke, for: key(a, stroke: true))
        c.rides = [a, b]; c.retain()
        precondition(c.networkGeometry.ridePolyline(for: key(a)) === original)
        precondition(c.networkGeometry.ridePolyline(for: key(a, stroke: true)) === stroke)
        c.retain(excludingStrokeFor: [a.id])
        precondition(c.networkGeometry.ridePolyline(for: key(a)) === original)
        precondition(c.networkGeometry.ridePolyline(for: key(a, stroke: true)) == nil)
        c.rides = [b]; c.retain()
        precondition(c.networkGeometry.ridePolyline(for: key(a)) == nil)
        c.rides = [a]; c.networkGeometry.storeRidePolyline(original, for: key(a))
        c.rides = [.init(id: a.id, geometryDigest: 11)]; c.retain()
        precondition(c.networkGeometry.ridePolyline(for: key(a)) == nil)
        c.rides = [a]; c.networkGeometry.storeRidePolyline(original, for: key(a))
        c.networkGeometry.beginFrame(key: "zoom-change")
        precondition(c.networkGeometry.ridePolyline(for: key(a)) == nil)
        c.networkGeometry.storeRidePolyline(original, for: key(a))
        c.networkGeometry.retainLineBuilds(withIDs: [])
        precondition(c.networkGeometry.ridePolyline(for: key(a)) == nil)
        print("PASS progressive route identity; removed/edited rides, changed stroke match, zoom and network invalidation")

        probe.reset()
        let indexGate = WorkGate(); probe.gate("index", indexGate)
        c.rides = [a]; c.match()
        await waitUntil("initial index starts") { probe.count("index") == 1 }
        c.rides = [a, b]; c.match() // Cancel while index construction is winding down.
        for arrival in 2..<12 {
            c.rides.append(.init(id: "arrival-\(arrival)", geometryDigest: arrival))
            c.match()
        }
        let latestMatch = c.matchingTask!
        c.geometry(key: "old-camera")
        await waitUntil("matching and geometry queued") { await c.renderWorkLimiter.queuedPermitCount == 2 }
        c.geometry(key: "new-camera")
        await waitUntil("canceled camera waiter replaced") { await c.renderWorkLimiter.queuedPermitCount == 2 }
        precondition(probe.count("geometry") == 0 && probe.peak == 1)
        indexGate.release.signal()
        await latestMatch.value
        await c.geometryPreparation?.value
        precondition(probe.count("index") == 1, "ride-only arrival rebuilt a completed network index")
        precondition(probe.count("geometry") == 1 && probe.peak == 1)
        precondition(c.pendingStrokeRefs?.revision == c.matchingRevision && c.pendingStrokeRefs?.refs.count == 12)
        precondition(c.networkGeometry.lineBuild(for: "line")?.revision == 1)
        print("PASS shared matching/geometry limit, canceled queued camera, reusable index and latest ride revision")

        let geometryGate = WorkGate(); probe.gate("geometry", geometryGate)
        c.geometry(key: "winding-camera")
        await waitUntil("geometry starts") { probe.count("geometry") == 2 }
        c.geometry(key: "latest-camera")
        await waitUntil("replacement geometry queued") { await c.renderWorkLimiter.queuedPermitCount == 1 }
        precondition(probe.count("geometry") == 2 && probe.peak == 1)
        geometryGate.release.signal()
        await c.geometryPreparation?.value
        precondition(probe.count("geometry") == 3 && probe.peak == 1)
        precondition(c.networkGeometry.lineBuild(for: "line")?.revision == 3)
        precondition(probe.state.withLock { $0.materialized } == [1, 3], "canceled camera materialized stale geometry")
        print("PASS canceled running geometry holds its permit until exit; stale camera cannot materialize")

        probe.reset()
        let changed = Coordinator()
        let staleGate = WorkGate(); probe.gate("index", staleGate)
        changed.rides = [a]; changed.match()
        await waitUntil("stale index starts") { probe.count("index") == 1 }
        changed.linesGeneration += 1
        changed.match()
        let currentMatch = changed.matchingTask!
        await waitUntil("new generation queued") { await changed.renderWorkLimiter.queuedPermitCount == 1 }
        staleGate.release.signal()
        await currentMatch.value
        precondition(probe.count("index") == 2 && probe.peak == 1)
        precondition(changed.preparedStrokeIndex?.generation == 2 && changed.preparedStrokeIndex?.index.revision == 2)
        precondition(changed.pendingStrokeRefs?.refs[a.id]?.linesGeneration == 2)
        print("PASS changed network/anchor generation rejects the canceled index")
    }
}
'''
source = (doubles.replace('__RETAIN__', retain).replace('__MATCHING__', matching)
          .replace('__CANCEL__', cancel_geometry).replace('__GEOMETRY__', geometry_workers))
with tempfile.TemporaryDirectory(prefix='jtm-map-workers-') as directory:
    folder = Path(directory)
    swift = folder / 'Checks.swift'
    binary = folder / 'checks'
    swift.write_text(limiter + '\n' + cache + '\n' + source + '\n' + installer_doubles + '\n' + reconciliation + installer + '\n' + checks)
    subprocess.run(['xcrun', 'swiftc', '-swift-version', '6', '-parse-as-library', '-O',
                    '-module-cache-path', str(folder / 'modules'), str(swift), '-o', str(binary)], check=True)
    subprocess.run([str(binary)], check=True, timeout=40)
