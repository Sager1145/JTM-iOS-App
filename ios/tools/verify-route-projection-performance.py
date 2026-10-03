#!/usr/bin/env python3
"""Check production route projection parity and time its bounded-path search.

Run with Python 3 on a host with swiftc. Extracts the current production
projector and metric; compiles only a temporary standalone Swift executable.
The original full scan is fixed below so the comparison survives future edits.
Timings are diagnostic, not pass/fail thresholds or app-wide measurements.
"""
import json
from pathlib import Path
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[2]
CORE = ROOT / "ios/RailKit/Sources/RailCore"


def declaration(source, marker):
    """Read one balanced Swift declaration (these bodies contain no brace strings)."""
    start = source.index(marker)
    opening = source.index("{", start)
    depth = 1
    end = opening + 1
    while depth:
        depth += (source[end] == "{") - (source[end] == "}")
        end += 1
    return source[start:end]


BASELINE = r"""static func baseline(
        _ point: Coordinate, onto path: [Coordinate], measures: [Double],
        low: Double? = nil, high: Double? = nil
    ) -> PathProjection? {
        guard path.count >= 2 else { return nil }
        var best: PathProjection?
        for index in 0..<(path.count - 1) {
            let length = measures[index + 1] - measures[index]
            let minimum = low == nil || length == 0 ? 0 : max(0, (low! - measures[index]) / length)
            let maximum = high == nil || length == 0 ? 1 : min(1, (high! - measures[index]) / length)
            if minimum > maximum { continue }
            let p = Metric.local(point, latitude: point.lat)
            let a = Metric.local(path[index], latitude: point.lat)
            let b = Metric.local(path[index + 1], latitude: point.lat)
            let dx = b.x - a.x, dy = b.y - a.y
            let squared = dx * dx + dy * dy
            let ratio = squared == 0 ? 0 : max(minimum, min(maximum, ((p.x - a.x) * dx + (p.y - a.y) * dy) / squared))
            let coordinate = Coordinate(
                lon: path[index].lon + (path[index + 1].lon - path[index].lon) * ratio,
                lat: path[index].lat + (path[index + 1].lat - path[index].lat) * ratio)
            let distance = Metric.distanceMeters(point, coordinate)
            if best == nil || distance < best!.distance {
                best = PathProjection(measure: measures[index] + length * ratio, distance: distance)
            }
        }
        return best
    }"""

CHECKS = r"""
struct PathProjection { var measure: Double; var distance: Double }

func cumulative(_ path: [Coordinate]) -> [Double] {
    var values = [0.0]
    for index in 1..<max(path.count, 1) {
        values.append(values[index - 1] + Metric.distanceMeters(path[index - 1], path[index]))
    }
    return values
}
func identical(_ a: PathProjection?, _ b: PathProjection?) -> Bool {
    switch (a, b) {
    case (nil, nil): return true
    case (.some(let a), .some(let b)):
        return a.measure.bitPattern == b.measure.bitPattern && a.distance.bitPattern == b.distance.bitPattern
    default: return false
    }
}
var checks = 0
func compare(_ path: [Coordinate], _ point: Coordinate, _ measures: [Double], _ zeros: [Int],
             low: Double?, high: Double?) {
    let expected = Projector.baseline(point, onto: path, measures: measures, low: low, high: high)
    let prepared = Projector.project(point, onto: path, measures: measures, low: low, high: high,
                                     zeroLengthSegments: zeros)
    let unprepared = Projector.project(point, onto: path, measures: measures, low: low, high: high)
    precondition(identical(expected, prepared), "Prepared production projection changed numerical result")
    precondition(identical(expected, unprepared), "Unprepared production projection changed numerical result")
    checks += 2
}
func validate(_ path: [Coordinate]) {
    let measures = cumulative(path)
    let zeros = path.count < 2 ? [] : (0..<(path.count - 1)).filter { measures[$0] == measures[$0 + 1] }
    let count = max(path.count, 1)
    for query in 0..<min(count, 500) {
        let index = path.isEmpty ? 0 : query * path.count / min(count, 500)
        let base = path.isEmpty ? Coordinate(lon: 139, lat: 35) : path[index]
        let point = Coordinate(lon: base.lon, lat: base.lat + 0.00003)
        let low: Double? = query % 7 == 0 ? nil : measures[index] - Double(query % 13)
        let high: Double? = query % 11 == 0 ? nil : measures[index] + Double(query % 17)
        compare(path, point, measures, zeros, low: low, high: high)
    }
    let last = measures.last!
    let bounds: [Double?] = [nil, -.infinity, -.greatestFiniteMagnitude, -1000, 0,
                             measures[measures.count / 2], last, last + 1000,
                             .greatestFiniteMagnitude, .infinity]
    for low in bounds {
        for high in bounds {
            compare(path, path.first ?? Coordinate(lon: 139, lat: 35), measures, zeros, low: low, high: high)
        }
    }
}
let basic = (0..<501).map { Coordinate(lon: 139 + Double($0) * 0.00001,
                                     lat: 35 + sin(Double($0) * 0.04) * 0.00004) }
validate(basic)
var repeated = basic
for index in stride(from: 3, to: repeated.count, by: 17) { repeated[index] = repeated[index - 1] }
validate(repeated)
validate(Array(basic.reversed()))
validate(Array(repeating: basic[0], count: 501))
validate([])
validate([basic[0]])
validate([basic[0], basic[1]])
// A path visiting the same approach in both directions preserves the first tie.
validate(basic + basic.reversed() + basic)
let bytes = try Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[1]))
let pairs = try JSONDecoder().decode([[Double]].self, from: bytes)
let sourced = pairs.map { Coordinate(lon: $0[0], lat: $0[1]) }
validate(sourced)
validate(Array(sourced.reversed()))
print("PASS: \(checks) exact floating-point parity checks (prepared and fallback); real interval \(sourced.count) vertices")

func benchmark(_ path: [Coordinate], label: String) {
    let measures = cumulative(path)
    let zeros = (0..<(path.count - 1)).filter { measures[$0] == measures[$0 + 1] }
    let queries = (0..<1000).map { 1 + $0 * (path.count - 2) / 1000 }
    var originalTime = Double.infinity, productionTime = Double.infinity
    var checksum = 0.0
    // Best of three reduces compilation/first-run noise. Never assert a speed ratio.
    for round in 0..<3 {
        for optimized in (round % 2 == 0 ? [false, true] : [true, false]) {
            let start = DispatchTime.now().uptimeNanoseconds
            for index in queries {
                let point = Coordinate(lon: path[index].lon, lat: path[index].lat + 0.00003)
                let low = measures[index] - 600, high = measures[index] + 600
                let result = optimized
                    ? Projector.project(point, onto: path, measures: measures, low: low, high: high,
                                        zeroLengthSegments: zeros)
                    : Projector.baseline(point, onto: path, measures: measures, low: low, high: high)
                checksum += result!.measure + result!.distance
            }
            let seconds = Double(DispatchTime.now().uptimeNanoseconds - start) / 1e9
            if optimized { productionTime = min(productionTime, seconds) }
            else { originalTime = min(originalTime, seconds) }
        }
    }
    let originalVisits = (path.count - 1) * queries.count
    var productionVisits = 0
    for index in queries {
        let low = measures[index] - 600, high = measures[index] + 600
        for segment in 0..<(path.count - 1) where measures[segment] == measures[segment + 1]
            || (measures[segment + 1] >= low && measures[segment] <= high) { productionVisits += 1 }
    }
    print(String(format: "%@: %d vertices × 1000 queries, original %.6fs, production %.6fs, %.2f×", label,
                 path.count, originalTime, productionTime, originalTime / productionTime))
    print("  Segment visits: \(originalVisits) → \(productionVisits); checksum \(checksum)")
}
benchmark((0..<50000).map { Coordinate(lon: 139 + Double($0) * 0.00001,
                                     lat: 35 + sin(Double($0) * 0.04) * 0.00004) }, label: "Synthetic long path")
benchmark(sourced, label: "Sourced Japanese station interval")
"""


def main():
    physical = (CORE / "PhysicalRouteMatcher.swift").read_text()
    route = (CORE / "RouteFeature.swift").read_text()
    coordinates = (CORE / "Coordinates.swift").read_text()
    production = declaration(physical, "    static func project(")
    metric = "enum Metric {\n" + declaration(route, "        static func local(") + "\n"
    metric += declaration(route, "        static func distanceMeters(") + "\n}\n"
    coordinate = declaration(coordinates, "public struct Coordinate:")
    source = "import Foundation\nimport Dispatch\n" + coordinate + "\n" + metric
    source += "enum Projector {\n" + production + "\n" + BASELINE + "\n}\n" + CHECKS
    package = json.loads((ROOT / "app/public/rail/jp-2025.json").read_text())
    candidates = [(len(segment[2]), line["id"], segment[2])
                  for line in package["lines"] for segment in line.get("segments", [])
                  if len(segment) >= 3 and isinstance(segment[2], list) and len(segment[2]) >= 2]
    _, line_id, longest = max(candidates, key=lambda candidate: candidate[0])
    print(f"Real interval source: {line_id}", flush=True)
    with tempfile.TemporaryDirectory(prefix="jtm-projection-check-") as temporary:
        directory = Path(temporary)
        swift = directory / "checks.swift"
        executable = directory / "checks"
        fixture = directory / "interval.json"
        swift.write_text(source)
        fixture.write_text(json.dumps(longest))
        subprocess.run(["swiftc", "-O", "-module-cache-path", str(directory / "module-cache"),
                        str(swift), "-o", str(executable)], check=True)
        subprocess.run([str(executable), str(fixture)], check=True)


if __name__ == "__main__":
    main()
