"""Check production MapKit chunk geometry and reuse on the host (macOS)."""
from pathlib import Path
import tempfile
import subprocess
root = Path(__file__).resolve().parents[2]
s=(root / 'ios/RailMap/MapLineGeometry.swift').read_text()
a=s.index('func mapCoordinateChunks(')
b=s.index('\n/// One family',a)
helper=s[a:b]
prepare_start = s.index('    static func prepare(')
prepare_end = s.index('    /// Publish a worker result', prepare_start)
worker_prepare = s[prepare_start:prepare_end]
assert 'MKPolyline(' not in worker_prepare
assert 'mapCoordinateChunks(points)' in worker_prepare
assert '@unchecked Sendable' not in s
assert '@MainActor\n    static func materialize(' in s
cache_source = (root / 'ios/RailMap/MapNetworkRendering.swift').read_text()
cache_start = cache_source.index('@MainActor\nfinal class MapNetworkGeometryCache')
cache_end = cache_source.index('/// The installed overlay identities', cache_start)
cache = cache_source[cache_start:cache_end]
state_start = cache_source.index('@MainActor\nstruct MapNetworkBuildState')
state_end = cache_source.index('/// Zoom-dependent network geometry', state_start)
build_state = cache_source[state_start:state_end]
lane_lod = (root / 'ios/RailKit/Sources/RailCore/LaneLOD.swift').read_text()
policy = (root / 'ios/RailKit/Sources/RailPresentation/MapRebuildPolicy.swift').read_text().replace('import RailCore', '')
view = (root / 'ios/RailMap/RailMapView.swift').read_text()
preparation = view[view.index('private func prepareNetworkGeometry('):view.index('private func rebuild(on mapView:')]
assert 'networkBuildState.previewLaneLOD(at: zoom)' in preparation
assert 'networkBuildState.resolveLaneLOD(at: zoom)' not in preparation
assert preparation.index('self.geometryPreparationID == requestID') < preparation.index('MapLineGeometry.materialize(geometry)')
doubles = r'''
enum ContinuousStroke { struct Stroke { let revision: Int } }
struct ContinuousStrokeBuild { let revision: Int }
struct LineBuild { let revision: Int }
enum MapLineGeometry {
    struct Prepared {
        let strokes: [String: ContinuousStrokeBuild]
        let lines: [String: LineBuild]
    }
}
'''
main=r'''
var buildState = MapNetworkBuildState()
let viewport = CGSize(width: 400, height: 800)
let visibleRect = MKMapRect(x: 0, y: 0, width: 400, height: 800)
_ = buildState.resolveLaneLOD(at: 11.8)
buildState.commit(zoom: 12.2, visibilityBucket: 12, viewportSize: viewport, builtRect: visibleRect)
precondition(buildState.laneLODBucket == 1)
// The requested bucket would advance, but its worker has not published.
precondition(buildState.previewLaneLOD(at: 12.26).bucket == 2)
precondition(buildState.laneLODBucket == 1, "cancelled preparation advanced installed lane spacing")
precondition(buildState.shouldRebuild(zoom: 12.26, visibilityBucket: 12,
    viewportSize: viewport, hasLanedLines: true, visibleRect: visibleRect),
    "cancelled boundary build suppressed the replacement")
_ = buildState.resolveLaneLOD(at: 12.26)
buildState.commit(zoom: 12.26, visibilityBucket: 12, viewportSize: viewport, builtRect: visibleRect)
precondition(!buildState.shouldRebuild(zoom: 12.26, visibilityBucket: 12,
    viewportSize: viewport, hasLanedLines: true, visibleRect: visibleRect))
for count in [0,1,2,128,129,130,257,1000] {
    let coordinates = (0..<count).map { CLLocationCoordinate2D(latitude: 35 + sin(Double($0)) / 100, longitude: 139 + Double($0) / 1000) }
    let coordinateChunks = mapCoordinateChunks(coordinates)
    let chunks = mapPolylineChunks(coordinateChunks)
    let segmentCount = chunks.reduce(0) { $0 + $1.pointCount - 1 }
    precondition(segmentCount == max(0, count - 1), "lost/duplicated segments")
    var cursor = 0
    for chunk in chunks {
        precondition(chunk.pointCount <= 129)
        for i in 0..<chunk.pointCount {
            let actual = chunk.points()[i]
            let expected = MKMapPoint(coordinates[cursor + i])
            precondition(abs(actual.x - expected.x) < 1e-6 && abs(actual.y - expected.y) < 1e-6)
        }
        cursor += chunk.pointCount - 1
    }
}
let flat = (0..<300).map { CLLocationCoordinate2D(latitude: 35, longitude: 139 + Double($0) / 1000) }
let held = mapPolylineChunks(mapCoordinateChunks(flat))
let point = MKMapPoint(flat[127])
let rect = MKMapRect(x: point.x - 2000, y: point.y - 2000, width: 4000, height: 4000)
let first = held.filter { $0.boundingMapRect.intersects(rect) }
let second = held.filter { $0.boundingMapRect.intersects(rect.offsetBy(dx: 100, dy: 0)) }
precondition(!first.isEmpty && !second.isEmpty)
precondition(first.contains { a in second.contains { $0 === a } }, "pan lost chunk identity")
let cache = MapNetworkGeometryCache()
let old = MapLineGeometry.Prepared(strokes: ["line": .init(revision: 1)], lines: ["line": .init(revision: 1)])
cache.beginFrame(key: "old-camera")
precondition(cache.storePrepared(old, key: "old-camera"))
cache.storeStroke((stroke: .init(revision: 1), mapPointsPerScreenPoint: 10), for: "line")
cache.beginFrame(key: "new-camera")
precondition(!cache.storePrepared(old, key: "old-camera"), "late worker polluted new camera")
precondition(cache.lineBuild(for: "line") == nil && cache.strokeBuild(for: "line") == nil)
precondition(cache.stroke(for: "line")?.stroke.revision == 1, "pending build discarded mounted ride geometry")
let fresh = MapLineGeometry.Prepared(strokes: ["line": .init(revision: 2)], lines: ["line": .init(revision: 2)])
precondition(cache.storePrepared(fresh, key: "new-camera"))
cache.beginFrame(key: "new-camera")
precondition(cache.lineBuild(for: "line")?.revision == 2, "same camera lost cached chunks")
cache.retainLineBuilds(withIDs: [])
precondition(!cache.hasLineBuild(for: "line") && !cache.hasStrokeBuild(for: "line"))
print("PASS: exact segments, seams, chunk identity, cancelled lane-bucket transition, stale-worker rejection, mounted-geometry retention and input invalidation")
'''
with tempfile.TemporaryDirectory(prefix='jtm-pan-geometry-') as directory:
    folder = Path(directory)
    source = folder / 'check.swift'
    binary = folder / 'check'
    source.write_text('import MapKit\n' + lane_lod + policy + build_state + helper + doubles + cache + '@main struct Checks { @MainActor static func main() {\n' + main + '\n} }')
    subprocess.run(['xcrun', 'swiftc', '-parse-as-library', '-O', '-module-cache-path', str(folder / 'modules'),
                    str(source), '-o', str(binary)], check=True)
    subprocess.run([str(binary)], check=True)
