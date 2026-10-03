#!/usr/bin/env python3
"""Exercise the production projection fit with independent holdout positions.
This checks projective math and degenerate input, not MapKit display timing.
"""
from pathlib import Path
import subprocess
import tempfile

root = Path(__file__).resolve().parents[2]
checks = r'''
import CoreGraphics
import Foundation
@main struct Checks {
    static func main() {
        let origin = CGPoint(x: 268_430_000, y: 106_900_000)
        func plane(_ x: Double, _ y: Double) -> CGPoint {
            CGPoint(x: origin.x + x * 20_000, y: origin.y + y * 20_000)
        }
        func expected(_ x: Double, _ y: Double) -> CGPoint {
            let denominator = 1 + 0.17 * x - 0.23 * y
            return CGPoint(x: (145 * x - 78 * y + 201) / denominator,
                           y: (71 * x + 239 * y + 437) / denominator)
        }
        let corners = [(-1.0, -1.0), (1.0, -1.0), (1.0, 1.0), (-1.0, 1.0)]
        let samples = corners.map { MapRailHomography.Sample(source: plane($0.0, $0.1),
                                                             displayed: expected($0.0, $0.1)) }
        let grid = [-1.0, 0.0, 1.0].flatMap { x -> [MapRailHomography.Sample] in
            [-1.0, 0.0, 1.0].map { y in .init(source: plane(x, y), displayed: expected(x, y)) }
        }
        for fitSamples in [samples, grid] {
        let projection = MapRailHomography.fit(fitSamples)!
        for x in [-1.3, -0.8, -0.17, 0.42, 1.2] {
            for y in [-1.2, -0.4, 0.11, 0.76, 1.3] {
                let actual = projection.project(plane(x, y))!
                let expected = expected(x, y)
                precondition(hypot(actual.x - expected.x, actual.y - expected.y) < 0.000001,
                    "Independent pitch/rotation holdout failed")
            }
        }
        }
        let collinear = (-2...2).map { index in
            MapRailHomography.Sample(source: plane(Double(index), 0),
                                     displayed: CGPoint(x: index * 30, y: 0))
        }
        precondition(MapRailHomography.fit(collinear) == nil,
                     "Collinear references must not produce a camera projection")
        precondition(MapRailHomography.fit(Array(samples.prefix(3))) == nil)
        let invalid = samples + [.init(source: CGPoint(x: CGFloat.nan, y: 0), displayed: .zero)]
        precondition(MapRailHomography.fit(invalid) == nil)
        print("PASS production homography: four/nine-reference fits, independent pitched/rotated Mercator holdouts and invalid/degenerate reference rejection")
    }
}
'''
with tempfile.TemporaryDirectory(prefix='jtm-public-projection-') as temporary:
    folder = Path(temporary)
    source = folder / 'Checks.swift'
    source.write_text(checks)
    executable = folder / 'checks'
    subprocess.run(['xcrun', 'swiftc', '-swift-version', '6', '-parse-as-library',
                    '-module-cache-path', str(folder / 'modules'),
                    str(root / 'ios/RailMap/MapRailHomography.swift'), str(source),
                    '-o', str(executable)], check=True)
    subprocess.run([str(executable)], check=True)
