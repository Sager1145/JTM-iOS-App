import Foundation
import RailCore

/// A WGS84 point in evidence and patches (`{"lon":..,"lat":..}`).
public struct AreaPoint: Codable, Equatable, Hashable, Sendable {
    public var lon: Double
    public var lat: Double
    public init(lon: Double, lat: Double) { self.lon = lon; self.lat = lat }
    public init(_ coordinate: Coordinate) { self.init(lon: coordinate.lon, lat: coordinate.lat) }
    public var coordinate: Coordinate { Coordinate(lon: lon, lat: lat) }
}

/// An axis-aligned lon/lat box.
public struct AreaBBox: Codable, Equatable, Sendable {
    public var minLon: Double
    public var minLat: Double
    public var maxLon: Double
    public var maxLat: Double

    public init(minLon: Double, minLat: Double, maxLon: Double, maxLat: Double) {
        self.minLon = minLon; self.minLat = minLat; self.maxLon = maxLon; self.maxLat = maxLat
    }

    /// The smallest box holding every point; nil for no points.
    public init?<S: Sequence>(points: S) where S.Element == Coordinate {
        var box: AreaBBox?
        for p in points where p.lon.isFinite && p.lat.isFinite {
            if box == nil { box = .init(minLon: p.lon, minLat: p.lat, maxLon: p.lon, maxLat: p.lat) }
            else { box!.include(p) }
        }
        guard let box else { return nil }
        self = box
    }

    public mutating func include(_ p: Coordinate) {
        minLon = min(minLon, p.lon); maxLon = max(maxLon, p.lon)
        minLat = min(minLat, p.lat); maxLat = max(maxLat, p.lat)
    }

    public func union(_ other: AreaBBox) -> AreaBBox {
        .init(minLon: min(minLon, other.minLon), minLat: min(minLat, other.minLat),
              maxLon: max(maxLon, other.maxLon), maxLat: max(maxLat, other.maxLat))
    }

    /// Grown by `metres` on every side (equirectangular at the box's centre latitude).
    public func padded(metres: Double) -> AreaBBox {
        let dLat = metres / AreaGeometry.metresPerDegree
        let dLon = metres / (AreaGeometry.metresPerDegree * max(0.01, cos(((minLat + maxLat) / 2) * .pi / 180)))
        return .init(minLon: minLon - dLon, minLat: minLat - dLat, maxLon: maxLon + dLon, maxLat: maxLat + dLat)
    }

    public func contains(_ p: Coordinate) -> Bool {
        p.lon >= minLon && p.lon <= maxLon && p.lat >= minLat && p.lat <= maxLat
    }

    public func intersects(_ other: AreaBBox) -> Bool {
        !(other.minLon > maxLon || other.maxLon < minLon || other.minLat > maxLat || other.maxLat < minLat)
    }

    /// True when any vertex lies inside or any edge crosses the box.
    public func intersects(polyline: [Coordinate]) -> Bool {
        guard let first = polyline.first else { return false }
        if contains(first) { return true }
        for (a, b) in zip(polyline, polyline.dropFirst()) {
            if contains(b) || segmentCrosses(a, b) { return true }
        }
        return false
    }

    private func segmentCrosses(_ a: Coordinate, _ b: Coordinate) -> Bool {
        // Liang–Barsky clip in lon/lat.
        var t0 = 0.0, t1 = 1.0
        let dx = b.lon - a.lon, dy = b.lat - a.lat
        for (p, q) in [(-dx, a.lon - minLon), (dx, maxLon - a.lon), (-dy, a.lat - minLat), (dy, maxLat - a.lat)] {
            if p == 0 { if q < 0 { return false }; continue }
            let r = q / p
            if p < 0 { if r > t1 { return false }; t0 = max(t0, r) }
            else { if r < t0 { return false }; t1 = min(t1, r) }
        }
        return t0 <= t1
    }

    public var routeGraphBBox: RouteGraph.BBox { .init(minX: minLon, minY: minLat, maxX: maxLon, maxY: maxLat) }
    public var centre: Coordinate { .init(lon: (minLon + maxLon) / 2, lat: (minLat + maxLat) / 2) }
}

/// Small local-metric helpers. Distances use an equirectangular projection
/// at the reference latitude, adequate at area scale (a few km).
public enum AreaGeometry {
    public static let metresPerDegree = 111_320.0

    static func project(_ p: Coordinate, origin: Coordinate) -> (Double, Double) {
        let k = cos(origin.lat * .pi / 180)
        return ((p.lon - origin.lon) * metresPerDegree * k, (p.lat - origin.lat) * metresPerDegree)
    }

    static func unproject(_ x: Double, _ y: Double, origin: Coordinate) -> Coordinate {
        let k = cos(origin.lat * .pi / 180)
        return Coordinate(lon: origin.lon + x / (metresPerDegree * k), lat: origin.lat + y / metresPerDegree)
    }

    public static func distance(_ a: Coordinate, _ b: Coordinate) -> Double {
        let (x, y) = project(b, origin: a)
        return hypot(x, y)
    }

    /// Nearest point on a polyline to `p`, with its distance in metres.
    public static func nearest(on polyline: [Coordinate], to p: Coordinate) -> (point: Coordinate, metres: Double)? {
        guard let first = polyline.first else { return nil }
        if polyline.count == 1 { return (first, distance(p, first)) }
        var best: (Coordinate, Double)?
        for (a, b) in zip(polyline, polyline.dropFirst()) {
            let (ax, ay) = project(a, origin: p), (bx, by) = project(b, origin: p)
            let dx = bx - ax, dy = by - ay
            let length2 = dx * dx + dy * dy
            let t = length2 > 0 ? max(0, min(1, -(ax * dx + ay * dy) / length2)) : 0
            let x = ax + t * dx, y = ay + t * dy
            let d = hypot(x, y)
            if best == nil || d < best!.1 { best = (unproject(x, y, origin: p), d) }
        }
        return best
    }

    /// Nearest distance from `p` to any of `polylines`.
    public static func nearestDistance(to polylines: [[Coordinate]], from p: Coordinate) -> Double? {
        polylines.compactMap { nearest(on: $0, to: p)?.metres }.min()
    }

    /// Points every `step` metres along the polyline, both ends included.
    public static func densify(_ polyline: [Coordinate], step: Double) -> [Coordinate] {
        guard polyline.count > 1, step > 0 else { return polyline }
        var out = [polyline[0]]
        for (a, b) in zip(polyline, polyline.dropFirst()) {
            let length = distance(a, b)
            let n = max(1, Int((length / step).rounded(.up)))
            for i in 1...n {
                let t = Double(i) / Double(n)
                out.append(Coordinate(lon: a.lon + (b.lon - a.lon) * t, lat: a.lat + (b.lat - a.lat) * t))
            }
        }
        return out
    }

    /// Rounds to 7 decimals (≈1 cm), the precision patches propose.
    public static func rounded(_ p: Coordinate) -> Coordinate {
        Coordinate(lon: (p.lon * 1e7).rounded() / 1e7, lat: (p.lat * 1e7).rounded() / 1e7)
    }
}
