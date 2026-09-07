"""Check production MapKit chunk geometry and reuse on the host (macOS)."""
from pathlib import Path
import tempfile
import subprocess
root = Path(__file__).resolve().parents[2]
s=(root / 'ios/RailMap/RailMapView.swift').read_text()
a=s.index('private func mapPolylineChunks(')
b=s.index('\n/// One family',a)
helper=s[a:b]
main=r'''
for count in [0,1,2,128,129,130,257,1000] {
    let coordinates = (0..<count).map { CLLocationCoordinate2D(latitude: 35 + sin(Double($0)) / 100, longitude: 139 + Double($0) / 1000) }
    let chunks = mapPolylineChunks(coordinates)
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
let held = mapPolylineChunks(flat)
let point = MKMapPoint(flat[127])
let rect = MKMapRect(x: point.x - 2000, y: point.y - 2000, width: 4000, height: 4000)
let first = held.filter { $0.boundingMapRect.intersects(rect) }
let second = held.filter { $0.boundingMapRect.intersects(rect.offsetBy(dx: 100, dy: 0)) }
precondition(!first.isEmpty && !second.isEmpty)
precondition(first.contains { a in second.contains { $0 === a } }, "pan lost chunk identity")
print("PASS: exact segment coverage, seam endpoints, degenerate horizontal bounds, and cross-viewport chunk identity")
'''
with tempfile.TemporaryDirectory(prefix='jtm-pan-geometry-') as directory:
    folder = Path(directory)
    source = folder / 'check.swift'
    binary = folder / 'check'
    source.write_text('import MapKit\n' + helper + main)
    subprocess.run(['xcrun', 'swiftc', '-O', '-module-cache-path', str(folder / 'modules'),
                    str(source), '-o', str(binary)], check=True)
    subprocess.run([str(binary)], check=True)
