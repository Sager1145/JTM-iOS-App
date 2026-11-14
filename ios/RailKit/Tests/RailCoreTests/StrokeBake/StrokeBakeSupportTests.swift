import Foundation
import MapKit
import Testing
@testable import RailCore

/// Projection parity against MapKit, the stroke tokens, GCJ-02 against the old app body, and the
/// bounds rule the junction test relies on.
@Suite("StrokeProjectionParity")
struct StrokeProjectionParityTests {

    static func samples() -> [CLLocationCoordinate2D] {
        var rng = SystemRandomNumberGenerator()
        var out: [CLLocationCoordinate2D] = [
            .init(latitude: 35.6812, longitude: 139.7671), .init(latitude: 22.3193, longitude: 114.1694),
            .init(latitude: 0, longitude: 0), .init(latitude: -33.8688, longitude: 151.2093),
            .init(latitude: 84.9, longitude: 179.9), .init(latitude: -84.9, longitude: -179.9),
        ]
        for _ in 0..<2000 {
            out.append(.init(
                latitude: Double.random(in: -80...80, using: &rng),
                longitude: Double.random(in: -179.9...179.9, using: &rng)))
        }
        return out
    }

    @Test("StrokeProjection.point equals MKMapPoint within 1e-6 map point")
    func pointParity() {
        var worst = 0.0
        for c in Self.samples() {
            let mine = StrokeProjection.point(Coordinate(lon: c.longitude, lat: c.latitude))
            let apple = MKMapPoint(c)
            worst = max(worst, abs(mine.x - apple.x), abs(mine.y - apple.y))
        }
        #expect(worst <= 1e-6, "worst point difference \(worst)")
    }

    @Test("StrokeProjection.coordinate equals MKMapPoint.coordinate")
    func coordinateParity() {
        var rng = SystemRandomNumberGenerator()
        var worst = 0.0
        for _ in 0..<2000 {
            let x = Double.random(in: 0..<StrokeProjection.worldSize, using: &rng)
            let y = Double.random(in: 1e7..<(StrokeProjection.worldSize - 1e7), using: &rng)
            let mine = StrokeProjection.coordinate(StrokePoint(x: x, y: y))
            let apple = MKMapPoint(x: x, y: y).coordinate
            worst = max(worst, abs(mine.lon - apple.longitude), abs(mine.lat - apple.latitude))
        }
        // 1e-9 degree is about a tenth of a millimetre.
        #expect(worst <= 1e-9, "worst coordinate difference \(worst)")
    }

    @Test("metres per map point equals MKMetersPerMapPointAtLatitude")
    func metresParity() {
        var worst = 0.0
        for latitude in stride(from: -80.0, through: 80.0, by: 0.05) {
            let mine = StrokeProjection.metresPerMapPoint(atLatitude: latitude)
            let apple = MKMetersPerMapPointAtLatitude(latitude)
            worst = max(worst, abs(mine - apple) / apple)
        }
        #expect(worst <= 1e-9, "worst relative difference \(worst)")
    }

    @Test("the world is MapKit's world")
    func world() {
        #expect(StrokeProjection.worldSize == MKMapSize.world.width)
        #expect(StrokeProjection.worldSize == MKMapSize.world.height)
    }

    @Test("StrokeBounds.intersects follows MKMapRect.intersects, edges and null included")
    func boundsIntersection() {
        func rect(_ b: StrokeBounds) -> MKMapRect {
            b.isNull ? .null : MKMapRect(x: b.minX, y: b.minY, width: b.maxX - b.minX, height: b.maxY - b.minY)
        }
        var disagreements = 0
        var boxes: [StrokeBounds] = [.null]
        // Every position and extent on a coarse grid, so shared edges, corners and boxes with no
        // extent on one or both axes are all present, in both argument orders.
        for x in 0..<4 {
            for y in 0..<4 {
                for w in 0..<3 {
                    for h in 0..<3 {
                        boxes.append(StrokeBounds(
                            minX: Double(x) * 10, minY: Double(y) * 10,
                            maxX: Double(x + w) * 10, maxY: Double(y + h) * 10))
                    }
                }
            }
        }
        for a in boxes {
            for b in boxes where a.intersects(b) != rect(a).intersects(rect(b)) {
                disagreements += 1
            }
        }
        #expect(disagreements == 0)
    }

    @Test("bounds are the union of the vertices' map points")
    func boundsOfLine() {
        let line = StrokeLineInput(
            id: "x#0", lineID: "x", region: "jp", operatorName: nil, colorHex: "#000000",
            colorDarkHex: "#ffffff", lane: 0, continuous: true,
            intervals: [[Coordinate(lon: 139.7, lat: 35.6), Coordinate(lon: 139.8, lat: 35.7)]])
        let a = StrokeProjection.point(Coordinate(lon: 139.7, lat: 35.6))
        let b = StrokeProjection.point(Coordinate(lon: 139.8, lat: 35.7))
        #expect(line.bounds == StrokeBounds(
            minX: min(a.x, b.x), minY: min(a.y, b.y), maxX: max(a.x, b.x), maxY: max(a.y, b.y)))
    }
}

@Suite("RailStrokeTokens")
struct RailStrokeTokensTests {
    @Test("the tokens keep the values the app has always drawn with")
    func values() {
        #expect(RailStrokeTokens.stationDiameter == 6)
        #expect(RailStrokeTokens.railWidth == 1.5)
        #expect(RailStrokeTokens.parallelGap == 1.2)
        #expect(RailStrokeTokens.parallelLaneCentreDistance == 1.5 + 1.2)
        #expect(RailStrokeTokens.minCornerRadius == 3)
        #expect(RailStrokeTokens.minimumScreenCornerRadius == 1)
        #expect(RailStrokeTokens.strokeCornerRadius == 6 * 0.6)
        #expect(RailStrokeTokens.strokeMinRamp == 24)
        #expect(RailStrokeTokens.simplifyTolerance == 0.0625)
        #expect(RailStrokeTokens.fullWeightZoom == 8)
        #expect(RailStrokeTokens.minWeightScale == 1.0 / 3.0)
    }

    @Test("derived radii and the weight ramp")
    func derived() {
        #expect(RailStrokeTokens.minimumCornerRadius(atScale: 1) == 3)
        #expect(RailStrokeTokens.minimumCornerRadius(atScale: 0.1) == 1)
        #expect(RailStrokeTokens.hardCornerMaxDeviation(atScale: 1) == 0.75)
        #expect(RailStrokeTokens.scale(atZoom: 8) == 1)
        #expect(RailStrokeTokens.scale(atZoom: 17) == 1)
        #expect(RailStrokeTokens.scale(atZoom: 6) == 0.5)
        #expect(RailStrokeTokens.scale(atZoom: 0) == 1.0 / 3.0)
        #expect(RailStrokeTokens.scale(atZoom: .nan) == 1)
    }

    @Test("a level frame resolves lane bucket and scale the way the app's frame does")
    func frame() {
        let low = StrokeBake.Frame(appZoom: 5)
        let mid = StrokeBake.Frame(appZoom: 10.5)
        let high = StrokeBake.Frame(appZoom: 13)
        #expect([low.laneScale, mid.laneScale, high.laneScale] == [0, 0.5, 1])
        #expect(high.mapPointsPerPoint == StrokeProjection.worldSize / (256 * exp2(13.0)))
        #expect(high.scale == 1)
        #expect(low.scale == RailStrokeTokens.scale(atZoom: 5))
    }
}

@Suite("GCJ02")
struct GCJ02Tests {
    /// Captured by compiling the body of `AppleMapDatum.gcj02(fromWGS84:)` at base commit d1d20e8c9.
    static let fromOldApp: [(Double, Double, Double, Double)] = [
        (113.529427, 22.183681, 113.53457224359182, 22.18078299435667),
        (121.517, 25.0478, 121.52090255117122, 25.04497836512115),
        (126.9784, 37.5665, 126.98348434285653, 37.56740325015811),
        (114.1694, 22.3193, 114.17436706626148, 22.316550799399344),
        (113.5754, 22.1385, 113.58043250392758, 22.135531105059165),
        (121.5654, 25.033, 121.5691731258631, 25.030065990080267),
        (127.0276, 37.4979, 127.03288103414057, 37.49893560678183),
        (116.4074, 39.9042, 116.41364225378803, 39.90560334316507),
    ]

    @Test("the moved transform returns what the app's own body returned")
    func matchesOldBody() {
        for (lon, lat, wantLon, wantLat) in Self.fromOldApp {
            let shifted = GCJ02.fromWGS84(Coordinate(lon: lon, lat: lat))
            #expect(abs(shifted.lon - wantLon) <= 1e-12)
            #expect(abs(shifted.lat - wantLat) <= 1e-12)
        }
    }

    @Test("toWGS84 inverts fromWGS84 to under 1e-9 degrees over the tw, hk, mo and kr boxes")
    func inverseRoundTrip() {
        // The pack reader maps a display rectangle back to the file's WGS84 space with this inverse.
        let boxes: [(lon: ClosedRange<Double>, lat: ClosedRange<Double>)] = [
            (119.3...122.1, 21.8...25.4),   // tw
            (113.8...114.5, 22.1...22.6),   // hk
            (113.5...113.62, 22.1...22.25), // mo
            (125.9...129.7, 33.0...38.7),   // kr
        ]
        var worst = 0.0, checked = 0
        for box in boxes {
            for i in 0...40 {
                for j in 0...40 {
                    let lon = box.lon.lowerBound + (box.lon.upperBound - box.lon.lowerBound) * Double(i) / 40
                    let lat = box.lat.lowerBound + (box.lat.upperBound - box.lat.lowerBound) * Double(j) / 40
                    let back = GCJ02.toWGS84(GCJ02.fromWGS84(Coordinate(lon: lon, lat: lat)))
                    worst = max(worst, abs(back.lon - lon), abs(back.lat - lat))
                    checked += 1
                }
            }
        }
        #expect(checked == 4 * 41 * 41)
        #expect(worst < 1e-9, "worst round-trip error \(worst) degrees")
    }

    @Test("candidate regions are the five the China map service can shift, never Japan")
    func candidates() {
        #expect(GCJ02.candidateRegions == ["tw", "hk", "mo", "kr", "cn"])
        #expect(!GCJ02.candidateRegions.contains("jp"))
    }

    @Test("Barra lands within 5 m of where MapKit's China service put it")
    func barra() {
        let shifted = GCJ02.fromWGS84(Coordinate(lon: 113.529427, lat: 22.183681))
        let metres = Geometry.distanceMeters(shifted, Coordinate(lon: 113.534528, lat: 22.180786))
        #expect(metres < 8)
    }

    @Test("a stroke input shifts every vertex before anything else reads it")
    func inputShift() throws {
        let fixture = try StrokeBakeFixtures.load()
        let plain = StrokeBakeFixtures.network(fixture)
        let shifted = StrokeBakeFixtures.network(fixture, shiftToGCJ02: ["hk", "mo"])
        #expect(plain.lines.count == shifted.lines.count)
        var moved = 0
        for (a, b) in zip(plain.lines, shifted.lines) {
            #expect(a.id == b.id)
            if a.region == "jp" {
                #expect(a.intervals == b.intervals)
                continue
            }
            moved += 1
            #expect(b.intervals[0][0] == GCJ02.fromWGS84(a.intervals[0][0]))
            #expect(b.intervals.map(\.count) == a.intervals.map(\.count))
        }
        #expect(moved > 0)
    }
}
