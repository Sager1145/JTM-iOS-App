import Foundation

/// A position in Apple's projected map space (MapKit's `MKMapPoint`), without MapKit.
public struct StrokePoint: Sendable, Hashable {
    public var x: Double
    public var y: Double

    public init(x: Double, y: Double) {
        self.x = x
        self.y = y
    }
}

/// An axis-aligned box in map points, the host-side stand-in for `MKMapRect`.
public struct StrokeBounds: Sendable, Hashable {
    public var minX: Double
    public var minY: Double
    public var maxX: Double
    public var maxY: Double

    public static let null = StrokeBounds(
        minX: .infinity, minY: .infinity, maxX: -.infinity, maxY: -.infinity)

    public init(minX: Double, minY: Double, maxX: Double, maxY: Double) {
        self.minX = minX
        self.minY = minY
        self.maxX = maxX
        self.maxY = maxY
    }

    public var isNull: Bool { minX > maxX || minY > maxY }
    public var midX: Double { (minX + maxX) / 2 }
    public var midY: Double { (minY + maxY) / 2 }

    public func union(_ point: StrokePoint) -> StrokeBounds {
        StrokeBounds(
            minX: min(minX, point.x), minY: min(minY, point.y),
            maxX: max(maxX, point.x), maxY: max(maxY, point.y))
    }

    /// `MKMapRect.intersects`, measured against MapKit on a grid of shared edges and degenerate
    /// boxes: rectangles that merely share an edge do not intersect, and a box with no extent on
    /// an axis is treated as a point on that axis (half-open: it intersects when it lies in
    /// `other.min ..< other.max`). The rule is asymmetric, as MapKit's is.
    public func intersects(_ other: StrokeBounds) -> Bool {
        guard !isNull, !other.isNull else { return false }
        func axis(_ aMin: Double, _ aMax: Double, _ bMin: Double, _ bMax: Double) -> Bool {
            aMin == aMax ? (bMin <= aMin && aMin < bMax) : (aMin < bMax && bMin < aMax)
        }
        return axis(minX, maxX, other.minX, other.maxX) && axis(minY, maxY, other.minY, other.maxY)
    }
}

/// Web-Mercator maths for the 2^28-point world MapKit uses, equal to `MKMapPoint(coordinate)`,
/// `MKMapPoint.coordinate` and `MKMetersPerMapPointAtLatitude` to well under 1e-6 map point
/// (`StrokeProjectionParityTests` compares them against MapKit on the host).
public enum StrokeProjection {
    /// The world's width and height in map points (`MKMapSize.world`).
    public static let worldSize: Double = 268_435_456

    public static func point(_ coordinate: Coordinate) -> StrokePoint {
        let radians = coordinate.lat * .pi / 180
        let x = (coordinate.lon + 180) / 360 * worldSize
        let y = (1 - log(tan(.pi / 4 + radians / 2)) / .pi) / 2 * worldSize
        return StrokePoint(x: x, y: y)
    }

    public static func coordinate(_ point: StrokePoint) -> Coordinate {
        let lon = point.x / worldSize * 360 - 180
        let lat = atan(sinh(.pi * (1 - 2 * point.y / worldSize))) * 180 / .pi
        return Coordinate(lon: lon, lat: lat)
    }

    /// Ground metres in one map point at `latitude`, equal to `MKMetersPerMapPointAtLatitude`
    /// for |latitude| up to 80 degrees (beyond that the value of the nearest valid latitude).
    ///
    /// MapKit's value is not the spherical `2πR cos φ / W` (0.7% too large at the equator) and not
    /// the WGS-84 meridian arc either (1.3e-5 off at the equator, growing with latitude), and no
    /// closed form was found that reproduces it. The divisor of `cos φ` is smooth in φ, so it is
    /// carried as the 40-term Chebyshev series below, fitted to MapKit's own answers on [0, 80]
    /// degrees (nodes at 40(1 + cos(π(k + ½)/40)), tail below 2e-15).
    /// `StrokeProjectionParityTests` compares the result with MapKit every 0.05 degree and fails
    /// at 1e-9 relative. The value matters because it sets the Douglas–Peucker tolerance, and a
    /// tolerance off by 1e-5 is enough to flip a vertex that sits on it.
    public static func metresPerMapPoint(atLatitude latitude: Double) -> Double {
        let degrees = min(abs(latitude), 80)
        let t = degrees / 40 - 1
        // Clenshaw evaluation of c0/2 + Σ cⱼ Tⱼ(t).
        var b1 = 0.0
        var b2 = 0.0
        for coefficient in metresPerMapPointSeries.dropFirst().reversed() {
            let next = 2 * t * b1 - b2 + coefficient
            b2 = b1
            b1 = next
        }
        let divisor = t * b1 - b2 + metresPerMapPointSeries[0] / 2
        return divisor * cos(latitude * .pi / 180)
    }

    private static let metresPerMapPointSeries: [Double] = [
        0.2978882893536536,
        0.0007634340609017992,
        2.9656200320450632e-05,
        -9.000132937810463e-05,
        -1.249038755562898e-05,
        -3.936441277753444e-06,
        -3.2658686714773233e-06,
        -1.9017236767102099e-06,
        -1.050662821630577e-06,
        -5.791044625266806e-07,
        -3.168375932671719e-07,
        -1.7207006335617783e-07,
        -9.286373397615623e-08,
        -4.9849701065640686e-08,
        -2.6635881873737778e-08,
        -1.4174560141605453e-08,
        -7.516171331156674e-09,
        -3.972836861571016e-09,
        -2.093956823906451e-09,
        -1.1008318166749743e-09,
        -5.773870478953391e-10,
        -3.0220229582655913e-10,
        -1.578679853508902e-10,
        -8.232388590267981e-11,
        -4.285948818072427e-11,
        -2.2280752243197812e-11,
        -1.1566493596237849e-11,
        -5.996683705156159e-12,
        -3.105266738190338e-12,
        -1.606740435144971e-12,
        -8.303954746047282e-13,
        -4.287570298799892e-13,
        -2.217778044544261e-13,
        -1.1469471206115855e-13,
        -5.959677196187841e-14,
        -3.0781800719470453e-14,
        -1.600559962344761e-14,
        -8.319213373741973e-15,
        -4.364564265557647e-15,
        -1.5191407159997894e-15
    ]
}
