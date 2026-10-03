#!/usr/bin/env python3
"""Raster-check production screen-space rail paint, independently of MapKit.
This confirms compositing/alpha/path semantics only, not displayed-camera sync.
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
        let width = 80, height = 80
        let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!
        let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
            bytesPerRow: width * 4, space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue)!
        context.setFillColor(CGColor(gray: 1, alpha: 1)); context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        context.setFillColor(CGColor(gray: 0, alpha: 0.1)); context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        let path = CGMutablePath(); path.move(to: CGPoint(x: 10, y: 40)); path.addLine(to: CGPoint(x: 70, y: 40))
        let red = CGColor(colorSpace: colorSpace, components: [1, 0, 0, 1])!
        let blue = CGColor(colorSpace: colorSpace, components: [0, 0, 1, 1])!
        let scene = MapProjectedRailScene(strokes: [.init(path: path, color: red, width: 8, alpha: 1)],
            beads: [.init(center: CGPoint(x: 40, y: 40), radius: 8,
                fill: blue, rim: blue, rimWidth: 2, alpha: 0.5)])
        scene.draw(in: context)
        let pixels = context.data!.assumingMemoryBound(to: UInt8.self)
        func pixel(_ x: Int, _ y: Int) -> [UInt8] { let at = (y * width + x) * 4; return Array(UnsafeBufferPointer(start: pixels + at, count: 4)) }
        let background = pixel(5, 5)
        precondition((228...231).contains(background[0]) && background[0] == background[1] && background[1] == background[2],
            "veil must uniformly darken the entire background")
        precondition(pixel(20, 40) == [255, 0, 0, 255], "solid rail ink was modulated by the basemap veil: \(pixel(20, 40))")
        let bead = pixel(40, 40)
        precondition((126...129).contains(bead[0]) && bead[1] == 0 && (126...129).contains(bead[2]),
            "circle fill/rim alpha must apply once to the complete marker above its stroke")
        print("PASS actual screen-space paint: uniform veil, unmodulated red rail and grouped marker alpha")
    }
}
'''
with tempfile.TemporaryDirectory(prefix='jtm-independent-paint-') as temporary:
    folder = Path(temporary)
    source = folder / 'Checks.swift'
    source.write_text(checks)
    executable = folder / 'checks'
    subprocess.run(['xcrun', 'swiftc', '-swift-version', '6', '-parse-as-library',
                    '-module-cache-path', str(folder / 'modules'),
                    str(root / 'ios/RailMap/MapProjectedRailScene.swift'), str(source), '-o', str(executable)], check=True)
    subprocess.run([str(executable)], check=True)
