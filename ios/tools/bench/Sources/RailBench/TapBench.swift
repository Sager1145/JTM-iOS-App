import Foundation
import RailCore
import RailPresentation

/// A tap on the map, with and without the chunk cull.
///
/// The projection here stands in for `MKMapView.convert(_:toPointTo:)`: a
/// spherical-Mercator map point followed by one scale and one translation,
/// which is exactly what MapKit's is on an unpitched map and is very much
/// CHEAPER than MapKit's — the real one crosses into VectorKit and takes the
/// map view's own lock per call. So the ratio this prints understates the
/// device, and the count of projections it prints is the number that carries
/// over unchanged.
func benchmarkTap(root: URL) {
    let rides = loadBenchRides(root: root)
    guard !rides.isEmpty else {
        print("tap: sample-data parts unavailable")
        return
    }
    let vertices = rides.reduce(0) { $0 + $1.strokes.reduce(0) { $0 + $1.count } }
    let strokes = rides.reduce(0) { $0 + $1.strokes.count }
    print("\ntap — \(rides.count) rides, \(strokes) strokes, \(vertices) vertices")

    // A city view of Tokyo: the zoom a reader taps a line at.
    let projection = BenchProjection(
        centre: Coordinate(lon: 139.767, lat: 35.681),
        pointsPerMetre: 1 / 4.0,          // ~z15 on a 3x screen
        viewSize: CGSizeLike(width: 393, height: 852))
    // And a national view, where nothing is culled by being off screen.
    let wide = BenchProjection(
        centre: Coordinate(lon: 137.5, lat: 36.5),
        pointsPerMetre: 1 / 900.0,
        viewSize: CGSizeLike(width: 393, height: 852))

    for (label, projection) in [("city z15", projection), ("national z5", wide)] {
        // Nine taps spread over the view, so the number is not one lucky miss.
        let taps = (0..<9).map { index in
            RideTapResolver.Point(
                x: 40 + Double(index % 3) * 150,
                y: 120 + Double(index / 3) * 220)
        }

        let index = BenchTapIndex(rides: rides, projection: projection)

        // Correctness first: the cull may not change a single answer.
        for tap in taps {
            let full = RideTapResolver.hits(
                at: tap, among: fullCandidates(rides, projection))
            let culled = RideTapResolver.hits(at: tap, among: index.candidates(near: tap))
            precondition(
                full == culled,
                "cull changed the answer at \(tap): \(full) vs \(culled)")
        }

        print("  \(label): projections per tap — "
            + "today \(vertices), culled \(index.projectionCount(near: taps[0]))"
            + " … \(taps.map { index.projectionCount(near: $0) }.max() ?? 0) (worst of 9)")

        measure("tap \(label): project everything, then hits (9 taps)") {
            var total = 0
            for tap in taps {
                total += RideTapResolver.hits(
                    at: tap, among: fullCandidates(rides, projection)).count
            }
            return total
        }
        measure("tap \(label): cull, project survivors, hits (9 taps)") {
            var total = 0
            for tap in taps {
                total += RideTapResolver.hits(
                    at: tap, among: index.candidates(near: tap)).count
            }
            return total
        }
        measure("tap \(label): build the chunk index once", repeats: 5) {
            BenchTapIndex(rides: rides, projection: projection).chunkCount
        }
    }
}

// MARK: - the two paths

private func fullCandidates(
    _ rides: [BenchRide], _ projection: BenchProjection
) -> [RideTapResolver.Candidate] {
    rides.map { ride in
        RideTapResolver.Candidate(
            id: ride.id,
            strokes: ride.strokes.map { stroke in
                stroke.map { projection.project($0) }
            })
    }
}

/// The chunk index, built once per ride generation and reused by every tap.
struct BenchTapIndex {
    struct Chunk {
        let rideIndex: Int
        let stroke: Int
        let range: Range<Int>
        let bounds: RideTapResolver.Bounds
    }
    let rides: [BenchRide]
    let projection: BenchProjection
    let chunks: [Chunk]

    var chunkCount: Int { chunks.count }

    init(rides: [BenchRide], projection: BenchProjection) {
        self.rides = rides
        self.projection = projection
        var chunks: [Chunk] = []
        for (rideIndex, ride) in rides.enumerated() {
            for (strokeIndex, stroke) in ride.strokes.enumerated() {
                for range in RideTapResolver.chunkRanges(count: stroke.count) {
                    // The box is in MAP space, computed once and independent of
                    // where the camera is; the app builds it the same way —
                    // from the run's lon/lat extremes rather than by projecting
                    // every vertex, which the monotonicity of Mercator on each
                    // axis makes exact.
                    guard let bounds = projection.bounds(of: stroke, in: range)
                    else { continue }
                    chunks.append(Chunk(
                        rideIndex: rideIndex, stroke: strokeIndex,
                        range: range, bounds: bounds))
                }
            }
        }
        self.chunks = chunks
    }

    func candidates(near tap: RideTapResolver.Point) -> [RideTapResolver.Candidate] {
        let tapMap = projection.mapPoint(of: tap)
        let tolerance = RideTapResolver.defaultTolerance / projection.pointsPerMapUnit
        var strokesByRide: [Int: [[RideTapResolver.Point]]] = [:]
        for chunk in chunks where chunk.bounds.mayContain(tapMap, within: tolerance) {
            let stroke = rides[chunk.rideIndex].strokes[chunk.stroke]
            strokesByRide[chunk.rideIndex, default: []].append(
                stroke[chunk.range].map { projection.project($0) })
        }
        return strokesByRide.map { index, strokes in
            RideTapResolver.Candidate(id: rides[index].id, strokes: strokes)
        }
    }

    func projectionCount(near tap: RideTapResolver.Point) -> Int {
        let tapMap = projection.mapPoint(of: tap)
        let tolerance = RideTapResolver.defaultTolerance / projection.pointsPerMapUnit
        return chunks.reduce(0) {
            $1.bounds.mayContain(tapMap, within: tolerance) ? $0 + $1.range.count : $0
        }
    }
}

// MARK: - a stand-in for MapKit's projection

struct CGSizeLike { var width: Double; var height: Double }

/// Spherical Mercator into a world of `worldSize` units, then a scale and a
/// translation — MapKit's own arrangement.
struct BenchProjection {
    static let worldSize = 268_435_456.0
    let centre: Coordinate
    let viewSize: CGSizeLike
    /// View points per map unit.
    let pointsPerMapUnit: Double
    private let centreMap: RideTapResolver.Point

    init(centre: Coordinate, pointsPerMetre: Double, viewSize: CGSizeLike) {
        self.centre = centre
        self.viewSize = viewSize
        // One map unit is `metresPerMapPoint` metres at the equator, scaled by
        // the latitude's cosine — the same relation `MKMetersPerMapPointAtLatitude`
        // states.
        let metresPerMapUnit =
            (2 * Double.pi * 6_378_137.0 / Self.worldSize)
            * Foundation.cos(centre.lat * Double.pi / 180)
        pointsPerMapUnit = pointsPerMetre * metresPerMapUnit
        centreMap = Self.mercator(centre)
    }

    static func mercator(_ coordinate: Coordinate) -> RideTapResolver.Point {
        let x = (coordinate.lon + 180) / 360 * worldSize
        let latitude = Swift.min(Swift.max(coordinate.lat, -85.05112878), 85.05112878)
        let radians = latitude * Double.pi / 180
        let y = (0.5
            - Foundation.log((1 + Foundation.sin(radians)) / (1 - Foundation.sin(radians)))
                / (4 * Double.pi)) * worldSize
        return RideTapResolver.Point(x: x, y: y)
    }

    func mapPoint(_ coordinate: Coordinate) -> RideTapResolver.Point {
        Self.mercator(coordinate)
    }

    /// A view point back into map space.
    func mapPoint(of point: RideTapResolver.Point) -> RideTapResolver.Point {
        RideTapResolver.Point(
            x: centreMap.x + (point.x - viewSize.width / 2) / pointsPerMapUnit,
            y: centreMap.y + (point.y - viewSize.height / 2) / pointsPerMapUnit)
    }

    /// The map-space box of a run, from its lon/lat extremes.
    func bounds(
        of stroke: [Coordinate], in range: Range<Int>
    ) -> RideTapResolver.Bounds? {
        guard range.count >= 2 else { return nil }
        var minLon = Double.infinity, maxLon = -Double.infinity
        var minLat = Double.infinity, maxLat = -Double.infinity
        for index in range {
            let coordinate = stroke[index]
            minLon = Swift.min(minLon, coordinate.lon)
            maxLon = Swift.max(maxLon, coordinate.lon)
            minLat = Swift.min(minLat, coordinate.lat)
            maxLat = Swift.max(maxLat, coordinate.lat)
        }
        let topLeft = Self.mercator(Coordinate(lon: minLon, lat: maxLat))
        let bottomRight = Self.mercator(Coordinate(lon: maxLon, lat: minLat))
        return RideTapResolver.Bounds(
            minX: Swift.min(topLeft.x, bottomRight.x),
            minY: Swift.min(topLeft.y, bottomRight.y),
            maxX: Swift.max(topLeft.x, bottomRight.x),
            maxY: Swift.max(topLeft.y, bottomRight.y))
    }

    func project(_ coordinate: Coordinate) -> RideTapResolver.Point {
        let map = Self.mercator(coordinate)
        return RideTapResolver.Point(
            x: (map.x - centreMap.x) * pointsPerMapUnit + viewSize.width / 2,
            y: (map.y - centreMap.y) * pointsPerMapUnit + viewSize.height / 2)
    }
}

// MARK: - the real geometry

struct BenchRide {
    let id: String
    let strokes: [[Coordinate]]
}

private struct BenchPart: Decodable {
    struct Train: Decodable { let id: String }
    struct Route: Decodable {
        struct Feature: Decodable {
            struct Geometry: Decodable {
                let type: String
                let coordinates: [[[Double]]]

                init(from decoder: Decoder) throws {
                    let container = try decoder.container(keyedBy: CodingKeys.self)
                    type = try container.decode(String.self, forKey: .type)
                    if type == "LineString" {
                        coordinates = [try container.decode([[Double]].self, forKey: .coordinates)]
                    } else {
                        coordinates = try container.decode([[[Double]]].self, forKey: .coordinates)
                    }
                }
                enum CodingKeys: String, CodingKey { case type, coordinates }
            }
            let geometry: Geometry?
        }
        let features: [Feature]
    }
    let train: Train
    let route: Route?
}

func loadBenchRides(root: URL) -> [BenchRide] {
    let directory = root.appending(path: "app/data/sample-data")
    guard let names = try? FileManager.default.contentsOfDirectory(atPath: directory.path)
    else { return [] }
    var rides: [BenchRide] = []
    for name in names.sorted() where name.hasPrefix("part-") && name.hasSuffix(".json") {
        guard let data = try? Data(contentsOf: directory.appending(path: name)),
              let part = try? JSONDecoder().decode(BenchPart.self, from: data)
        else { continue }
        var strokes: [[Coordinate]] = []
        for feature in part.route?.features ?? [] {
            for line in feature.geometry?.coordinates ?? [] {
                let stroke = line.compactMap { pair -> Coordinate? in
                    pair.count >= 2
                        ? Coordinate(lon: pair[0], lat: pair[1]) : nil
                }
                if stroke.count >= 2 { strokes.append(stroke) }
            }
        }
        if !strokes.isEmpty { rides.append(BenchRide(id: part.train.id, strokes: strokes)) }
    }
    return rides
}
