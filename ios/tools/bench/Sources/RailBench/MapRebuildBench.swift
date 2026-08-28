import Foundation
import RailCore

/// The pure half of a map rebuild.
///
/// `RailMapView.Coordinator.rebuild(on:)` is documented at 150–460 ms for the
/// Japanese network, and it is two different jobs in one function: arithmetic
/// that needs no MapKit — level of detail, Douglas–Peucker, the vertex budget —
/// and the MapKit calls that must be on the main actor. Only the first half can
/// be measured here, and knowing how much of the total it is decides whether
/// moving it off the main actor is worth the machinery.
func benchmarkMapRebuild(root: URL) {
    let url = root.appending(path: "app/public/rail/jp-2025.json")
    guard let package = try? CompactPackage.load(contentsOf: url) else {
        print("rebuild: jp-2025.json unavailable")
        return
    }
    var intervals: [[Coordinate]] = []
    for line in package.lines {
        intervals.append(contentsOf: CompactPackage.decodeIntervals(line))
    }
    let vertices = intervals.reduce(0) { $0 + $1.count }
    print("\nmap rebuild — jp: \(package.lines.count) lines, "
        + "\(intervals.count) intervals, \(vertices) vertices")

    // `epsilon = metresPerPixel(zoom, latitude) * RailStyle.simplifyTolerance`,
    // with the tolerance the gate pins to the web app's 0.0625 pt.
    func metresPerPixel(zoom: Double, latitude: Double) -> Double {
        156_543.03392 * Foundation.cos(latitude * Double.pi / 180) / pow(2, zoom)
    }
    let tolerance = 0.0625

    for (label, zoom) in [("national z4.7", 4.7), ("regional z9", 9.0), ("city z13.3", 13.3)] {
        let epsilon = metresPerPixel(zoom: zoom, latitude: 35.68) * tolerance
        var kept = 0
        measure("douglasPeucker over every jp interval (\(label))", repeats: 5) {
            var total = 0
            for interval in intervals where interval.count >= 2 {
                total += Geometry.douglasPeuckerIndices(
                    interval, epsilonMeters: epsilon).count
            }
            kept = total
            return total
        }
        print("    \(kept) of \(vertices) vertices survive at \(label)")
    }

    // The LOD pass culls most of those before decimation at a wide zoom, so the
    // number above is the ceiling rather than the typical case. What it bounds
    // is the cost of the geometry half of a rebuild that decimates everything —
    // the city view, where the visible-rect cull keeps the count down instead.
}
