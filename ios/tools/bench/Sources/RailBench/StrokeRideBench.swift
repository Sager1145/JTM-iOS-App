import Foundation
import RailCore

/// Real package intervals exercise the matching index without MapKit. These
/// are not the app's display chains, so timings describe matching arithmetic.
func benchmarkStrokeRide(root: URL) {
    let url = root.appending(path: "app/public/rail/jp-2025.json")
    guard let package = try? CompactPackage.load(contentsOf: url) else { return }
    var chains: [ChainRef] = []
    for line in package.lines {
        for (part, points) in CompactPackage.decodeIntervals(line).enumerated() where points.count >= 2 {
            var measures = [Double](repeating: 0, count: points.count)
            for i in 1..<points.count {
                measures[i] = measures[i - 1] + Geometry.distanceMeters(points[i - 1], points[i])
            }
            chains.append(ChainRef(id: "\(line.id)#\(part)", points: points,
                measures: measures, anchors: [0, points.count - 1]))
        }
    }
    guard !chains.isEmpty else { return }
    let step = max(1, chains.count / 100)
    var queries: [[Coordinate]] = []
    for i in stride(from: 0, to: chains.count, by: step) {
        let points = chains[i].points
        queries.append(points)
        queries.append(Array(points.reversed()))
        queries.append(points.map { .init(lon: $0.lon + 0.1, lat: $0.lat + 0.1) })
    }
    print("\nstroke matching — \(chains.count) jp intervals, \(queries.count) queries")
    var prepared: StrokeRide.Index?
    measure("prepare stroke index", repeats: 5) {
        prepared = StrokeRide.Index(chains: chains)
        return chains.count
    }
    guard let prepared else { return }
    let expected = queries.map { StrokeRide.resolve(segment: $0, chains: chains) }
    precondition(queries.map { prepared.resolve(segment: $0) } == expected,
        "prepared matcher differs from exhaustive matching")
    measure("resolve all queries with prepared index", repeats: 7) {
        queries.reduce(0) { $0 + (prepared.resolve(segment: $1) == nil ? 0 : 1) }
    }
    measure("resolve all queries exhaustively", repeats: 3, warmup: 0) {
        queries.reduce(0) { $0 + (StrokeRide.resolve(segment: $1, chains: chains) == nil ? 0 : 1) }
    }
}
