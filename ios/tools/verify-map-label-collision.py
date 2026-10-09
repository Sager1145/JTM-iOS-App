#!/usr/bin/env python3
"""Exercise the production label collision grid against explicit cases and an oracle."""
from pathlib import Path
import subprocess
import tempfile

root = Path(__file__).resolve().parents[2]
checks = r'''
import Foundation
import CoreGraphics

@main struct Checks {
    static func main() {
        var negative = MapLabelCollisionGrid()
        precondition(negative.insertIfClear(CGRect(x: -106, y: -106, width: 10, height: 10)))
        precondition(!negative.insertIfClear(CGRect(x: -88, y: -106, width: 2, height: 10)))
        precondition(negative.insertIfClear(CGRect(x: -50, y: -50, width: 10, height: 10)))
        var boundary = MapLabelCollisionGrid()
        precondition(boundary.insertIfClear(CGRect(x: 80, y: 80, width: 8, height: 8)))
        precondition(!boundary.insertIfClear(CGRect(x: 100, y: 98, width: 8, height: 8)))
        print("PASS negative coordinates and collisions across cell boundaries")

        var padding = MapLabelCollisionGrid()
        precondition(padding.insertIfClear(CGRect(x: 0, y: 0, width: 10, height: 10)))
        // These raw boxes are disjoint; horizontal padding makes them collide.
        precondition(!padding.insertIfClear(CGRect(x: 25, y: 0, width: 10, height: 10)))
        // Overlaps only the rejected box, which must not reserve any cells.
        precondition(padding.insertIfClear(CGRect(x: 42, y: 0, width: 10, height: 10)))
        precondition(!padding.insertIfClear(CGRect(x: 0, y: 21, width: 10, height: 10)))
        print("PASS horizontal/vertical padding rejects collisions; rejected boxes do not reserve")

        var endpoints = MapLabelCollisionGrid()
        endpoints.reserve(CGRect(x: 0, y: 0, width: 30, height: 30))
        endpoints.reserve(CGRect(x: 20, y: 0, width: 30, height: 30))
        precondition(!endpoints.insertIfClear(CGRect(x: -10, y: 0, width: 5, height: 5)))
        precondition(!endpoints.insertIfClear(CGRect(x: 55, y: 0, width: 5, height: 5)))
        precondition(endpoints.insertIfClear(CGRect(x: 80, y: 0, width: 5, height: 5)))
        print("PASS overlapping endpoint reservations both block later station labels")

        var empty = MapLabelCollisionGrid()
        let zeroWidth = CGRect(x: 0, y: 0, width: 0, height: 20)
        let zeroHeight = CGRect(x: 0, y: 0, width: 20, height: 0)
        precondition(!empty.insertIfClear(zeroWidth))
        precondition(!empty.insertIfClear(zeroHeight))
        empty.reserve(zeroWidth)
        empty.reserve(zeroHeight)
        precondition(empty.insertIfClear(CGRect(x: 0, y: 0, width: 10, height: 10)))
        print("PASS zero-size inserts and reservations occupy no space")

        var grid = MapLabelCollisionGrid()
        var oracle: [CGRect] = []
        var admitted = 0, rejected = 0, reserved = 0
        let widths: [CGFloat] = [0, 1, 17, 95, 130]
        let heights: [CGFloat] = [1, 0, 23, 96, 143]
        // Fixed arithmetic covers negative cells, exact 96-point boundaries,
        // fractional edges, multi-cell boxes, repeats and zero-size boxes.
        for index in 0..<600 {
            let column = (index * 37) % 19 - 9
            let row = (index * 23) % 17 - 8
            let x = CGFloat(column) * 48 + CGFloat(index % 3) / 4
            let y = CGFloat(row) * 48 + CGFloat(index % 4) / 4
            let width = widths[index % widths.count]
            let height = heights[(index / 3) % heights.count]
            let box = CGRect(
                x: x, y: y, width: width, height: height)
            let nonempty = box.width > 0 && box.height > 0
            let padded = box.insetBy(dx: -8, dy: -6)
            if index % 11 == 0 {
                grid.reserve(box)
                if nonempty { oracle.append(padded); reserved += 1 }
            } else {
                let expected = nonempty && !oracle.contains { $0.intersects(padded) }
                let actual = grid.insertIfClear(box)
                precondition(actual == expected, "Oracle mismatch at deterministic operation \(index): \(box)")
                if expected { oracle.append(padded); admitted += 1 }
                else { rejected += 1 }
            }
        }
        precondition(admitted > 0 && rejected > 0 && reserved > 0)
        print("PASS 600 deterministic operations match brute-force padded CGRect intersection oracle")
    }
}
'''
with tempfile.TemporaryDirectory(prefix='jtm-map-label-collision-') as directory:
    folder = Path(directory)
    swift = folder / 'Checks.swift'
    binary = folder / 'checks'
    swift.write_text(checks)
    subprocess.run(['xcrun', 'swiftc', '-swift-version', '6', '-parse-as-library',
                    '-module-cache-path', str(folder / 'modules'), str(swift),
                    str(root / 'ios/RailMap/MapLabelCollisionGrid.swift'),
                    '-o', str(binary)], check=True)
    subprocess.run([str(binary)], check=True, timeout=30)
