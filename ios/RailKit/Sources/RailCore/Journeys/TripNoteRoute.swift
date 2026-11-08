import Foundation

/// A trip's drawn route measured by arc length, with each stop's place on it,
/// so a trip note can go from (stop interval, fraction) to a point and back.
///
/// The strokes are the ride's drawn pieces in ride order. Breaks between
/// strokes (physical gaps, multi-part sections) add no length: a fraction is a
/// share of track actually drawn. `stopArcs[i]` is how far along the route
/// stop `i` sits, or nil when the route says nothing about it; known values
/// never decrease.
public struct TripNoteRoute: Sendable {
    public let strokes: [[Coordinate]]
    public let stopArcs: [Double?]
    /// Cumulative arc at each vertex, per stroke.
    private let vertexArcs: [[Double]]
    public let length: Double

    public init(strokes: [[Coordinate]], stopArcs: [Double?]) {
        let kept = strokes.filter { $0.count >= 2 }
        var arcs: [[Double]] = []
        var total = 0.0
        for stroke in kept {
            var row = [total]
            for index in 1..<stroke.count {
                total += Geometry.distanceMeters(stroke[index - 1], stroke[index])
                row.append(total)
            }
            arcs.append(row)
        }
        self.strokes = kept
        self.vertexArcs = arcs
        self.length = total
        var last = 0.0
        self.stopArcs = stopArcs.map { arc in
            guard let arc, arc.isFinite else { return nil }
            last = max(last, min(arc, total))
            return last
        }
    }

    /// Stop places from strokes tagged with the stop interval they belong to
    /// (`RecordedRouteMapping.stopInterval(forSectionIndex:)`): stop `i` sits
    /// where interval `i` begins, the last stop at the end of the last
    /// interval before it.
    public init(intervalStrokes: [(stopInterval: Int, coordinates: [Coordinate])], stopCount: Int) {
        var arcs = [Double?](repeating: nil, count: max(stopCount, 0))
        var total = 0.0
        for piece in intervalStrokes where piece.coordinates.count >= 2 {
            let interval = piece.stopInterval
            if arcs.indices.contains(interval), arcs[interval] == nil { arcs[interval] = total }
            for index in 1..<piece.coordinates.count {
                total += Geometry.distanceMeters(piece.coordinates[index - 1], piece.coordinates[index])
            }
            if arcs.indices.contains(interval + 1) { arcs[interval + 1] = total }
        }
        self.init(strokes: intervalStrokes.map(\.coordinates), stopArcs: arcs)
    }

    /// Stop places by projecting each stop's own point onto the route, in
    /// order, never moving backwards. Used when the route carries no
    /// stop-interval mapping.
    public init(strokes: [[Coordinate]], projectingStops stopPoints: [Coordinate?],
                maxStopMeters: Double = 3_000) {
        let route = TripNoteRoute(strokes: strokes, stopArcs: [])
        var floor = 0.0
        var arcs: [Double?] = []
        for (index, point) in stopPoints.enumerated() {
            if index == 0, point == nil { arcs.append(0); continue }
            guard let point, let hit = route.nearest(to: point, notBefore: floor),
                  hit.distance <= maxStopMeters else { arcs.append(nil); continue }
            floor = hit.arc
            arcs.append(hit.arc)
        }
        if let lastIndex = arcs.indices.last, arcs[lastIndex] == nil, stopPoints[lastIndex] == nil {
            arcs[lastIndex] = route.length
        }
        self.init(strokes: strokes, stopArcs: arcs)
    }

    // MARK: arc ↔ point

    /// The point `arc` metres along the route.
    public func point(atArc arc: Double) -> Coordinate? {
        guard let firstStroke = strokes.first else { return nil }
        let target = min(max(arc, 0), length)
        for (strokeIndex, stroke) in strokes.enumerated() {
            let arcs = vertexArcs[strokeIndex]
            guard let end = arcs.last, target <= end else { continue }
            for index in 1..<stroke.count where target <= arcs[index] {
                let span = arcs[index] - arcs[index - 1]
                let t = span > 0 ? (target - arcs[index - 1]) / span : 0
                return Self.lerp(stroke[index - 1], stroke[index], t)
            }
        }
        return strokes.last?.last ?? firstStroke.first
    }

    /// The nearest point of the route to `point` at or after `notBefore`.
    public func nearest(to point: Coordinate, notBefore: Double = 0)
        -> (arc: Double, coordinate: Coordinate, distance: Double)?
    {
        var best: (arc: Double, coordinate: Coordinate, distance: Double)?
        for (strokeIndex, stroke) in strokes.enumerated() {
            let arcs = vertexArcs[strokeIndex]
            if let end = arcs.last, end < notBefore { continue }
            for index in 1..<stroke.count {
                let a = stroke[index - 1], b = stroke[index]
                var t = Self.projection(of: point, onto: a, b)
                let segmentArc = arcs[index - 1] + t * (arcs[index] - arcs[index - 1])
                if segmentArc < notBefore {
                    let span = arcs[index] - arcs[index - 1]
                    guard span > 0, arcs[index] >= notBefore else { continue }
                    t = (notBefore - arcs[index - 1]) / span
                }
                let candidate = Self.lerp(a, b, t)
                let distance = Geometry.distanceMeters(candidate, point)
                if best == nil || distance < best!.distance {
                    best = (arcs[index - 1] + t * (arcs[index] - arcs[index - 1]), candidate, distance)
                }
            }
        }
        return best
    }

    // MARK: stop intervals

    /// The arc span from stop `from` to stop `to`, when both are placed and
    /// in order.
    public func span(fromStop: Int, toStop: Int) -> ClosedRange<Double>? {
        guard stopArcs.indices.contains(fromStop), stopArcs.indices.contains(toStop), fromStop < toStop,
              let start = stopArcs[fromStop], let end = stopArcs[toStop], start <= end else { return nil }
        return start...end
    }

    public func point(fromStop: Int, toStop: Int, fraction: Double) -> Coordinate? {
        guard let span = span(fromStop: fromStop, toStop: toStop) else { return nil }
        let f = fraction.isFinite ? min(max(fraction, 0), 1) : 0.5
        return point(atArc: span.lowerBound + f * (span.upperBound - span.lowerBound))
    }

    public func point(atStop index: Int) -> Coordinate? {
        guard stopArcs.indices.contains(index), let arc = stopArcs[index] else { return nil }
        return point(atArc: arc)
    }

    /// Half way along the drawn route.
    public func midpoint() -> Coordinate? { length > 0 ? point(atArc: length / 2) : strokes.first?.first }

    public struct Projection: Equatable, Sendable {
        public var fromStop: Int
        public var toStop: Int
        public var fraction: Double
        public var point: Coordinate
        public var distanceMeters: Double
        /// The stop the point lies on, when within the station snap radius.
        public var nearStop: Int?
    }

    /// Where `point` falls between two placed stops, if the route passes
    /// within `maxMeters` of it.
    public func project(_ point: Coordinate, maxMeters: Double, stationSnapMeters: Double = 0)
        -> Projection?
    {
        guard let hit = nearest(to: point), hit.distance <= maxMeters else { return nil }
        let placed = stopArcs.enumerated().compactMap { index, arc in arc.map { (index, $0) } }
        guard placed.count >= 2 else { return nil }
        // The last placed stop at or before the point, and the next one after
        // it; a point past the final stop belongs to the final interval.
        var lowerOffset = placed.lastIndex(where: { $0.1 <= hit.arc }) ?? 0
        // Stops sharing one place (zero-length interval): take the later span.
        lowerOffset = min(lowerOffset, placed.count - 2)
        let lower = placed[lowerOffset], upper = placed[lowerOffset + 1]
        let width = upper.1 - lower.1
        let fraction = width > 0 ? min(max((hit.arc - lower.1) / width, 0), 1) : 0.5
        var nearStop: Int?
        if stationSnapMeters > 0 {
            let distances = [lower, upper].map { ($0.0, abs(hit.arc - $0.1)) }
            if let closest = distances.min(by: { $0.1 < $1.1 }), closest.1 <= stationSnapMeters {
                nearStop = closest.0
            }
        }
        return Projection(fromStop: lower.0, toStop: upper.0, fraction: fraction,
                          point: hit.coordinate, distanceMeters: hit.distance, nearStop: nearStop)
    }

    // MARK: planar helpers (local equirectangular; spans here are short)

    private static func lerp(_ a: Coordinate, _ b: Coordinate, _ t: Double) -> Coordinate {
        Coordinate(lon: a.lon + (b.lon - a.lon) * t, lat: a.lat + (b.lat - a.lat) * t)
    }

    private static func projection(of p: Coordinate, onto a: Coordinate, _ b: Coordinate) -> Double {
        let scale = cos(((a.lat + b.lat) / 2) * .pi / 180)
        let dx = (b.lon - a.lon) * scale, dy = b.lat - a.lat
        let length2 = dx * dx + dy * dy
        guard length2 > 0 else { return 0 }
        let t = ((p.lon - a.lon) * scale * dx + (p.lat - a.lat) * dy) / length2
        return min(max(t, 0), 1)
    }
}

extension TripNoteRoute {
    /// The anchor a picked point on this trip's route becomes. Station when
    /// within the snap radius of a stop, otherwise the interval and fraction;
    /// the picked point itself is kept as the fallback either way.
    public func anchor(for projection: Projection, stops: [Stop], fallback: Coordinate?) -> TripNoteAnchor? {
        if let index = projection.nearStop, stops.indices.contains(index) {
            return .station(TripNoteStation(stop: stops[index]), fallback: fallback)
        }
        guard stops.indices.contains(projection.fromStop), stops.indices.contains(projection.toStop) else {
            return nil
        }
        return .interval(from: TripNoteStation(stop: stops[projection.fromStop]),
                         to: TripNoteStation(stop: stops[projection.toStop]),
                         fraction: (projection.fraction * 1000).rounded() / 1000, fallback: fallback)
    }

    /// Where a note sits on this route today, or nil to fall back.
    public func coordinate(for placement: TripNotePlacement) -> Coordinate? {
        switch placement {
        case .station(let index): point(atStop: index)
        case .interval(let from, let to, let fraction): point(fromStop: from, toStop: to, fraction: fraction)
        case .coordinate(let coordinate): coordinate
        case .unplaced: nil
        }
    }
}
