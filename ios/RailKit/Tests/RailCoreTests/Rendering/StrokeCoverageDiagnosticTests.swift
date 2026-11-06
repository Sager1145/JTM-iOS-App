import Foundation
import Testing
@testable import RailCore

/// Diagnostic only: which step of Main's stroke pipeline drops part of
/// jp-南海電気鉄道-多奈川線 (110-vertex part). Prints; asserts nothing about coverage.
@Suite struct StrokeCoverageDiagnosticTests {
    typealias P = ContinuousStroke.Point
    static let source: [(Double, Double)] = [
        (135.137295, 34.3167499),
        (135.1374553, 34.3167616),
        (135.1375354, 34.3167679),
        (135.137615, 34.3167776),
        (135.1376945, 34.3167879),
        (135.1377736, 34.3167999),
        (135.1378526, 34.3168125),
        (135.1379317, 34.3168251),
        (135.1380107, 34.3168374),
        (135.1380901, 34.3168484),
        (135.138169, 34.3168605),
        (135.1382476, 34.3168748),
        (135.1383265, 34.316888),
        (135.1384056, 34.3169005),
        (135.1390715, 34.3170103),
        (135.1392393, 34.3170374),
        (135.1395772, 34.3170905),
        (135.1399159, 34.3171303),
        (135.1399954, 34.3171403),
        (135.1400749, 34.3171506),
        (135.1401543, 34.3171617),
        (135.1402338, 34.3171717),
        (135.1403133, 34.3171823),
        (135.1403924, 34.3171945),
        (135.1404717, 34.3172057),
        (135.1405509, 34.3172169),
        (135.14063, 34.3172293),
        (135.1407093, 34.3172405),
        (135.1407892, 34.3172497),
        (135.1408684, 34.3172613),
        (135.1409471, 34.3172738),
        (135.1410266, 34.3172842),
        (135.1411059, 34.3172953),
        (135.1412909, 34.3173243),
        (135.1414232, 34.3173401),
        (135.1415027, 34.3173504),
        (135.1415821, 34.3173614),
        (135.1416614, 34.3173726),
        (135.1417408, 34.3173833),
        (135.14182, 34.3173953),
        (135.141899, 34.317408),
        (135.1419782, 34.31742),
        (135.1420572, 34.3174324),
        (135.1421364, 34.3174445),
        (135.1422155, 34.3174568),
        (135.1422945, 34.3174693),
        (135.1423736, 34.3174817),
        (135.1424524, 34.317495),
        (135.142531, 34.3175074),
        (135.1426104, 34.3175182),
        (135.1426897, 34.3175304),
        (135.1431541, 34.3176008),
        (135.1434921, 34.3176584),
        (135.1438825, 34.317718),
        (135.1441762, 34.3177716),
        (135.1443894, 34.3177977),
        (135.1445973, 34.3178336),
        (135.1449379, 34.3178823),
        (135.1451482, 34.3179168),
        (135.1454864, 34.3179683),
        (135.1456551, 34.3179966),
        (135.1459877, 34.3180497),
        (135.1462735, 34.3180926),
        (135.1464507, 34.3181304),
        (135.1474809, 34.318213),
        (135.1475609, 34.3182198),
        (135.1476409, 34.3182274),
        (135.1477209, 34.3182343),
        (135.1478008, 34.3182417),
        (135.1478808, 34.3182496),
        (135.1480604, 34.3182667),
        (135.14864, 34.31832),
        (135.14877, 34.31833),
        (135.14961, 34.3184),
        (135.15031, 34.31846),
        (135.15048, 34.31848),
        (135.15078, 34.31851),
        (135.15107, 34.31853),
        (135.15156, 34.31858),
        (135.15173, 34.31859),
        (135.15189, 34.31861),
        (135.15198, 34.31862),
        (135.15295, 34.3187),
        (135.15396, 34.31879),
        (135.15438, 34.31885),
        (135.15462, 34.31893),
        (135.15489, 34.31903),
        (135.15524, 34.31918),
        (135.15543, 34.31929),
        (135.15569, 34.31948),
        (135.15622, 34.31991),
        (135.15631, 34.32004),
        (135.15638, 34.32011),
        (135.15671, 34.32055),
        (135.157, 34.32096),
        (135.1572, 34.3212),
        (135.15742, 34.32145),
        (135.15789, 34.32186),
        (135.15794, 34.32189),
        (135.15803, 34.32196),
        (135.15868, 34.32242),
        (135.15874, 34.32246),
        (135.1588, 34.3225),
        (135.15932, 34.32286),
        (135.15957, 34.32304),
        (135.15982, 34.32321),
        (135.16007, 34.32338),
        (135.16078, 34.32383),
        (135.161, 34.32398),
        (135.161016, 34.323992)
    ]
    static let stations: [(Double, Double)] = [(135.13729496623995, 34.31674989757304), (135.14129088780206, 34.31732426273342), (135.14806044682518, 34.31826665450579), (135.161016, 34.323992)]
    static let totalMetres = 2438.1

    static func haversine(_ a: (Double, Double), _ b: (Double, Double)) -> Double {
        let r = 6371008.8, d2r = Double.pi / 180
        let dLat = (b.1 - a.1) * d2r, dLon = (b.0 - a.0) * d2r
        let h = sin(dLat / 2) * sin(dLat / 2) + cos(a.1 * d2r) * cos(b.1 * d2r) * sin(dLon / 2) * sin(dLon / 2)
        return 2 * r * asin(min(1, sqrt(h)))
    }

    static func distToSegment(_ p: P, _ a: P, _ b: P) -> Double {
        let dx = b.x - a.x, dy = b.y - a.y
        let len2 = dx * dx + dy * dy
        var t = len2 > 0 ? ((p.x - a.x) * dx + (p.y - a.y) * dy) / len2 : 0
        t = max(0, min(1, t))
        return hypot(p.x - (a.x + t * dx), p.y - (a.y + t * dy))
    }

    @Test func diagnose() {
        var measures: [Double] = [0]
        for i in 1..<Self.source.count { measures.append(measures[i - 1] + Self.haversine(Self.source[i - 1], Self.source[i])) }
        print("DIAG source vertices=\(Self.source.count) haversineTotal=\(measures.last!) declaredTotal=\(Self.totalMetres)")
        // z20 is where 24 m = 122 screen pt at this latitude; z18/z16 are 2/4 levels coarser. RailStyle.scale = 1 for all (zoom >= 8).
        let lat = Self.source[0].1
        let mppZ20 = 24.0 / 122.0
        let zoom20 = log2(40075016.686 * cos(lat * Double.pi / 180) / (512 * mppZ20))
        let anchors = Self.stations.map { s in
            Self.source.indices.min { Self.haversine(Self.source[$0], s) < Self.haversine(Self.source[$1], s) }!
        }
        print("DIAG anchors(vertex idx)=\(anchors) zoom20mercator=\(zoom20)")
        for (label, zoom) in [("z20", zoom20), ("z18", zoom20 - 2), ("z16", zoom20 - 4)] {
            for enforce in [true, false] {
                let pixels = Self.source.map { ContinuousStroke.project(lon: $0.0, lat: $0.1, zoom: zoom) }
                let scale = 1.0
                let stroke = ContinuousStroke.buildStroke(pixels, options: .init(
                    measures: measures, rows: [], totalMetres: Self.totalMetres,
                    laneGapPx: 0, minRampPx: 24,
                    cornerRadiusPx: 3.6 * scale,
                    minCornerRadiusPx: max(1, 1.5 * 2 * scale),
                    anchors: anchors, follows: [], shapeBoundaryMeasures: [],
                    joinStart: nil, joinEnd: nil, enforceMinimumCornerRadius: enforce))
                report(label: label, enforce: enforce, pixels: pixels, stroke: stroke)
            }
        }
    }

    func report(label: String, enforce: Bool, pixels: [P], stroke: ContinuousStroke.Stroke) {
        let pts = stroke.points, ms = stroke.measures
        let tag = "DIAG[\(label) enforce=\(enforce)]"
        let nan = pts.indices.filter { !pts[$0].x.isFinite || !pts[$0].y.isFinite }
        let monotone = zip(ms, ms.dropFirst()).allSatisfy { $0 <= $1 }
        print("\(tag) strokePoints=\(pts.count) measures=\(ms.count) monotone=\(monotone) first=\(ms.first ?? .nan) last=\(ms.last ?? .nan) total=\(Self.totalMetres) nanPoints=\(nan)")
        guard pts.count >= 2 else { print("\(tag) EMPTY STROKE"); return }
        var maxD = 0.0, far: [(Int, Double)] = []
        for (i, v) in pixels.enumerated() {
            var best = Double.infinity
            for s in 0..<(pts.count - 1) { best = min(best, Self.distToSegment(v, pts[s], pts[s + 1])) }
            maxD = max(maxD, best)
            if best > 2 { far.append((i, best)) }
        }
        print("\(tag) maxVertexToStrokePx=\(maxD) vertices>2px(\(far.count))=\(far.map { "\($0.0):\(String(format: "%.2f", $0.1))" })")
        let v63 = pixels[63]
        let near63 = pts.indices.min { hypot(pts[$0].x - v63.x, pts[$0].y - v63.y) < hypot(pts[$1].x - v63.x, pts[$1].y - v63.y) }!
        print("\(tag) nearestStrokeIdxToV63=\(near63) dist=\(hypot(pts[near63].x - v63.x, pts[near63].y - v63.y)) mod128=\(near63 % 128) isMultipleOf128=\(near63 % 128 == 0) measure=\(ms[near63])")
        // Stroke extent west (lower x) and by measure.
        let minX = pts.map(\.x).min()!, maxX = pts.map(\.x).max()!
        print("\(tag) strokeX=[\(minX), \(maxX)] srcX=[\(pixels.map(\.x).min()!), \(pixels.map(\.x).max()!)] v0=(\(pixels[0].x),\(pixels[0].y)) s0=(\(pts[0].x),\(pts[0].y)) sLast=(\(pts[pts.count-1].x),\(pts[pts.count-1].y)) vLast=(\(pixels[pixels.count-1].x),\(pixels[pixels.count-1].y))")
        let west = pts.indices.filter { pts[$0].x < v63.x - 1 }
        print("\(tag) strokePointsWestOfV63=\(west.count) idxRange=\(west.first.map { "\($0)..\(west.last!)" } ?? "none")")
        // mapCoordinateChunks replica: stride 128, 129 points, shared terminal vertex.
        var chunkNo = 0
        for start in stride(from: 0, to: pts.count - 1, by: 128) {
            let end = min(start + 129, pts.count)
            let c = pts[start..<end]
            let x0 = c.map(\.x).min()!, x1 = c.map(\.x).max()!, y0 = c.map(\.y).min()!, y1 = c.map(\.y).max()!
            let westInChunk = west.filter { $0 >= start && $0 < end }
            let excluded = westInChunk.filter { pts[$0].x < x0 || pts[$0].x > x1 || pts[$0].y < y0 || pts[$0].y > y1 }
            print("\(tag) chunk\(chunkNo) idx=\(start)..<\(end) bbox x[\(x0),\(x1)] y[\(y0),\(y1)] westPointsInChunk=\(westInChunk.count) excludedByBBox=\(excluded.count)")
            chunkNo += 1
        }
    }
}
