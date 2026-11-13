import Foundation
import Testing
@testable import RailCore

/// The pack's thinning stage (`NetworkStrokeBake.thinned`): each stroke is within the tolerance of the
/// engine's, forced vertices survive exactly, and the thinned bake is small.
@Suite("NetworkStrokeBake thinning")
struct NetworkStrokeBakeThinTests {

    static let tolerance = RailStrokeTokens.packThinTolerance
    /// App zoom, standing for ladder z5, z9, z13 and z16.
    static let zooms: [Double] = [6, 10, 14, 17]

    static func network() throws -> NetworkStrokeBake.Network {
        StrokeBakeFixtures.network(try StrokeBakeFixtures.load())
    }

    static func distance(_ p: StrokePoint, toPolyline line: [StrokePoint]) -> Double {
        var nearest = Double.infinity
        for (s, e) in zip(line, line.dropFirst()) {
            let dx = e.x - s.x, dy = e.y - s.y
            let l2 = dx * dx + dy * dy
            let t = l2 > 0 ? min(max(((p.x - s.x) * dx + (p.y - s.y) * dy) / l2, 0), 1) : 0
            nearest = min(nearest, hypot(s.x + dx * t - p.x, s.y + dy * t - p.y))
        }
        return nearest
    }

    /// Windowed distance of the points of `line` to `to`: most points sit on a vertex of `to`, so a
    /// full scan only for the few that do not.
    static func far(_ points: [StrokePoint], from line: [StrokePoint], limit: Double) -> Int {
        var count = 0
        for p in points where distance(p, toPolyline: line) > limit { count += 1 }
        return count
    }

    static func point(on points: [StrokePoint], _ measures: [Double], at m: Double) -> StrokePoint {
        var i = 1
        while i < measures.count - 1, measures[i] < m { i += 1 }
        let t = measures[i] > measures[i - 1] ? (m - measures[i - 1]) / (measures[i] - measures[i - 1]) : 0
        return StrokePoint(
            x: points[i - 1].x + (points[i].x - points[i - 1].x) * t,
            y: points[i - 1].y + (points[i].y - points[i - 1].y) * t)
    }

    @Test("every dropped vertex is within the tolerance of the thinned stroke")
    func droppedVerticesStayWithinTolerance() throws {
        let network = try Self.network()
        var checked = 0
        for zoom in Self.zooms {
            let full = try NetworkStrokeBake.bake(network, level: .init(appZoom: zoom))
            let thin = NetworkStrokeBake.thinned(full, tolerance: Self.tolerance)
            let limit = Self.tolerance * full.level.mapPointsPerPoint * (1 + 1e-9)
            for (a, b) in zip(full.chains, thin.chains) {
                if a.continuous {
                    #expect(Self.far(a.strokePoints, from: b.strokePoints, limit: limit) == 0, "\(a.id) at \(zoom)")
                    checked += a.strokePoints.count
                } else {
                    for (ra, rb) in zip(a.runs, b.runs) {
                        #expect(Self.far(ra.vertices, from: rb.vertices, limit: limit) == 0, "\(a.id) at \(zoom)")
                        checked += ra.vertices.count
                    }
                }
            }
        }
        #expect(checked > 10_000)
    }

    @Test("forced vertices are bit equal to the stroke, measures ascend, closed chains stay closed")
    func forcedVerticesSurvive() throws {
        let network = try Self.network()
        var forcedChecked = 0, closed = 0
        for zoom in Self.zooms {
            let full = try NetworkStrokeBake.bake(network, level: .init(appZoom: zoom))
            // Ask to keep three metres inside every continuous stroke.
            var keep: [NetworkStrokeBake.PartKey: [Double]] = [:]
            for chain in full.chains where chain.continuous && chain.strokePoints.count > 3 {
                let low = chain.strokeMeasures.first!, high = chain.strokeMeasures.last!
                keep[.init(chainID: chain.id, part: 0)] = [0.21, 0.5, 0.77].map { low + (high - low) * $0 }
            }
            let thin = NetworkStrokeBake.thinned(full, tolerance: Self.tolerance, keep: keep)
            for (a, b) in zip(full.chains, thin.chains) where a.continuous && a.strokePoints.count > 3 {
                #expect(b.strokePoints.count == b.strokeMeasures.count)
                #expect(b.strokePoints.count <= a.strokePoints.count + 3 + 2 * (a.runs.count + a.withheld.count
                    + a.landlord.count + a.tenantFallback.count), "thinning never adds more than its forced vertices")
                #expect(zip(b.strokeMeasures, b.strokeMeasures.dropFirst()).allSatisfy { $0 <= $1 }, "\(a.id) at \(zoom)")
                #expect(b.strokePoints.first == a.strokePoints.first && b.strokePoints.last == a.strokePoints.last)
                for m in keep[.init(chainID: a.id, part: 0)]! {
                    let at = try #require(b.strokeMeasures.firstIndex(of: m), "\(a.id): metre \(m) is a vertex")
                    #expect(b.strokePoints[at] == Self.point(on: a.strokePoints, a.strokeMeasures, at: m), "\(a.id) at \(zoom)")
                    forcedChecked += 1
                }
                // Every window boundary is a vertex too.
                let windows = a.runs.map { ($0.from, $0.to) }
                    + (a.withheld + a.landlord + a.tenantFallback).map { ($0.from, $0.to) }
                for (from, to) in windows where to > from {
                    #expect(b.strokeMeasures.contains(from) && b.strokeMeasures.contains(to), "\(a.id) window ends")
                }
                if a.strokePoints.first == a.strokePoints.last { closed += 1 }
            }
        }
        #expect(forcedChecked > 100)
        #expect(closed >= 1, "the fixture holds a closed chain")
    }

    @Test("non-continuous runs keep their ends and the metres asked for on their own ruler")
    func partsKeepTheirRuler() throws {
        let network = try Self.network()
        var checked = 0
        for zoom in Self.zooms {
            let full = try NetworkStrokeBake.bake(network, level: .init(appZoom: zoom))
            var keep: [NetworkStrokeBake.PartKey: [Double]] = [:]
            for chain in full.chains where !chain.continuous {
                for run in chain.runs where run.measures.count > 3 {
                    keep[.init(chainID: chain.id, part: run.part)] = [run.measures.last! * 0.4]
                }
            }
            let thin = NetworkStrokeBake.thinned(full, tolerance: Self.tolerance, keep: keep)
            for (a, b) in zip(full.chains, thin.chains) where !a.continuous {
                for (ra, rb) in zip(a.runs, b.runs) {
                    #expect(rb.vertices.count == rb.measures.count)
                    guard ra.vertices.count >= 2 else { continue }
                    #expect(rb.vertices.first == ra.vertices.first && rb.vertices.last == ra.vertices.last)
                    #expect(rb.measures.first == ra.measures.first && rb.measures.last == ra.measures.last)
                    if let m = keep[.init(chainID: a.id, part: ra.part)]?.first, ra.measures.count > 3 {
                        let at = try #require(rb.measures.firstIndex(of: m), "\(a.id): metre \(m) is a vertex")
                        #expect(rb.vertices[at] == Self.point(on: ra.vertices, ra.measures, at: m))
                        checked += 1
                    }
                }
            }
        }
        #expect(checked > 20)
    }

    // MARK: Synthetic strokes

    /// One continuous chain over `points` (map points) with measures equal to the polyline length.
    static func chain(_ id: String, _ points: [StrokePoint], level: NetworkStrokeBake.Level) -> NetworkStrokeBake.Chain {
        var measures = [0.0]
        for (a, b) in zip(points, points.dropFirst()) { measures.append(measures.last! + hypot(b.x - a.x, b.y - a.y)) }
        return NetworkStrokeBake.Chain(
            id: id, lineID: id, region: "xx", continuous: true, lane: 0, colorHex: "#000000", colorDarkHex: "#ffffff",
            runs: [], withheld: [], landlord: [], tenantFallback: [], nodes: [],
            strokePoints: points, strokeMeasures: measures)
    }

    @Test("a bend above the tolerance keeps its vertex, one below collapses")
    func bendsAgainstTolerance() {
        let level = NetworkStrokeBake.Level(appZoom: 12)
        let unit = level.mapPointsPerPoint
        func bent(_ offset: Double) -> NetworkStrokeBake.Baked {
            let p = [StrokePoint(x: 0, y: 0), StrokePoint(x: 10 * unit, y: offset * unit), StrokePoint(x: 20 * unit, y: 0)]
            return NetworkStrokeBake.Baked(level: level, chains: [Self.chain("a", p, level: level)])
        }
        #expect(NetworkStrokeBake.thinned(bent(Self.tolerance * 2), tolerance: Self.tolerance).chains[0].strokePoints.count == 3)
        #expect(NetworkStrokeBake.thinned(bent(Self.tolerance * 0.5), tolerance: Self.tolerance).chains[0].strokePoints.count == 2)
    }

    @Test("thinning twice equals thinning once, and the same input gives the same output")
    func idempotentAndDeterministic() throws {
        let network = try Self.network()
        for zoom in Self.zooms {
            let full = try NetworkStrokeBake.bake(network, level: .init(appZoom: zoom))
            let once = NetworkStrokeBake.thinned(full, tolerance: Self.tolerance)
            #expect(once == NetworkStrokeBake.thinned(full, tolerance: Self.tolerance), "deterministic at \(zoom)")
            let twice = NetworkStrokeBake.thinned(once, tolerance: Self.tolerance)
            #expect(twice == once, "idempotent at \(zoom)")
        }
    }

    @Test("two strokes that lie on each other keep the same vertices on the shared run")
    func coincidentStrokesStayCoincident() {
        let level = NetworkStrokeBake.Level(appZoom: 12)
        let unit = level.mapPointsPerPoint
        // A gentle arc sampled finely; the second stroke is its middle stretch with different ends, so
        // Douglas-Peucker alone would choose different vertices for the two.
        let arc = (0...120).map { i -> StrokePoint in
            let x = Double(i) * unit * 0.5
            return StrokePoint(x: x, y: 40 * unit * sin(Double(i) / 120 * .pi * 1.3))
        }
        let a = Self.chain("a", arc, level: level)
        let b = Self.chain("b", Array(arc[23...91]), level: level)
        let thin = NetworkStrokeBake.thinned(.init(level: level, chains: [a, b]), tolerance: Self.tolerance)
        let cell = unit * RailStrokeTokens.simplifyTolerance
        func cells(_ chain: NetworkStrokeBake.Chain) -> Set<[Int]> {
            Set(chain.strokePoints.map { [Int(($0.x / cell).rounded()), Int(($0.y / cell).rounded())] })
        }
        let inside = Set(arc[23...91].map { [Int(($0.x / cell).rounded()), Int(($0.y / cell).rounded())] })
        #expect(cells(thin.chains[0]).intersection(inside) == cells(thin.chains[1]).intersection(inside))
        #expect(thin.chains[1].strokePoints.count > 2, "the arc is not a straight line")
    }

    // MARK: Size

    /// Measured on the committed fixture with the tolerance above, rounded up by 10%.
    static let ceilings: [Double: Int] = [6: 1_520, 10: 3_480, 14: 12_500, 17: 38_200]

    @Test("the thinned fixture is small: vertex and byte ceilings, and a tenth of the engine's at z5")
    func fixtureBudget() throws {
        let network = try Self.network()
        for zoom in Self.zooms {
            let full = try NetworkStrokeBake.bake(network, level: .init(appZoom: zoom))
            let thin = NetworkStrokeBake.thinned(full, tolerance: Self.tolerance)
            func count(_ baked: NetworkStrokeBake.Baked) -> Int {
                baked.chains.reduce(0) { $0 + ($1.continuous ? $1.strokePoints.count : $1.runs.reduce(0) { $0 + $1.vertices.count }) }
            }
            #expect(count(thin) <= Self.ceilings[zoom]!, "vertices at app zoom \(zoom)")
            #expect(4 * count(thin) <= 4 * Self.ceilings[zoom]!, "bytes at app zoom \(zoom)")
            if zoom == 6 { #expect(count(thin) * 10 < count(full), "z5 keeps under a tenth of the engine's vertices") }
        }
    }
}
