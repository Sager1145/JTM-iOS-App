import Foundation
import RailCore

/// Where a trip note's "!" sits on a drawn ride, and which anchor a picked
/// point becomes. The bridge between `RailCore`'s ``TripNoteRoute`` (stops and
/// fractions) and the map's ``RiddenRouteStore/DrawnRide`` (drawn strokes in
/// two datums).
///
/// Two datums, never mixed: `.display` is what MapKit draws (GCJ-02 where
/// Apple's basemap is displaced), `.wgs84` is what a note stores as its
/// fallback and what CoreLocation reports.
enum TripNoteGeometry {
    enum Datum { case display, wgs84 }

    /// The ride's drawn route in ride order. Each piece is tagged with its stop
    /// interval when the ride carries a recorded route mapping for every
    /// section; otherwise the stops are found by projecting their beads.
    static func route(of ride: RiddenRouteStore.DrawnRide, datum: Datum) -> TripNoteRoute {
        let pieces = ride.segments.sorted {
            ($0.segmentIndex, $0.partIndex) < ($1.segmentIndex, $1.partIndex)
        }
        let strokes = pieces.map { datum == .display ? $0.coordinates : $0.drawnCoordinates }
        let intervals = pieces.map { ride.stopInterval(forSectionIndex: $0.segmentIndex) }
        if ride.recordedRouteMapping != nil, !intervals.contains(where: { $0 == nil }) {
            return TripNoteRoute(
                intervalStrokes: zip(intervals, strokes).map { (stopInterval: $0!, coordinates: $1) },
                stopCount: ride.stops.count)
        }
        // No mapping: stop places come from the display beads. The WGS84
        // route reuses the display route's stop arcs, scaled to its own
        // length — the displacement is locally a near-translation, so the
        // share of the route before each stop is the same in both datums.
        let beads = MapRideMarkers.stopPositions(of: ride)
        let display = TripNoteRoute(
            strokes: pieces.map(\.coordinates),
            projectingStops: ride.stops.indices.map { beads[$0] })
        guard datum == .wgs84 else { return display }
        let plain = TripNoteRoute(strokes: strokes, stopArcs: [])
        let scale = display.length > 0 ? plain.length / display.length : 0
        return TripNoteRoute(strokes: strokes, stopArcs: display.stopArcs.map { $0.map { $0 * scale } })
    }

    struct Placed: Equatable {
        var noteID: String
        var coordinate: Coordinate
        var isStation: Bool
        /// 0 for the first note at a station, 1 for the next, and so on.
        var stackPosition: Int
    }

    /// Display-datum points for `notes` on `ride`, in note order. A note whose
    /// place cannot be found is left out.
    static func place(_ notes: [TripNote], on ride: RiddenRouteStore.DrawnRide) -> [Placed] {
        guard !notes.isEmpty else { return [] }
        let route = route(of: ride, datum: .display)
        let beads = MapRideMarkers.stopPositions(of: ride)
        var perStop: [Int: Int] = [:]
        return notes.compactMap { note in
            let placement = TripNotePlacement.resolve(note.anchor, stops: ride.stops)
            switch placement {
            case .station(let index):
                guard let point = beads[index] ?? route.point(atStop: index) else {
                    return fallback(note, ride: ride)
                }
                let stack = perStop[index, default: 0]
                perStop[index] = stack + 1
                return Placed(noteID: note.id, coordinate: point, isStation: true, stackPosition: stack)
            case .interval:
                guard let point = route.coordinate(for: placement) else { return fallback(note, ride: ride) }
                return Placed(noteID: note.id, coordinate: point, isStation: false, stackPosition: 0)
            case .coordinate, .unplaced:
                return fallback(note, ride: ride)
            }
        }
    }

    private static func fallback(_ note: TripNote, ride: RiddenRouteStore.DrawnRide) -> Placed? {
        guard let stored = note.anchor.fallbackCoordinate else { return nil }
        return Placed(noteID: note.id, coordinate: AppleMapDatum.display(stored, country: ride.country),
                      isStation: false, stackPosition: 0)
    }

    /// Where a ride's count badge sits on the overview map: half way along
    /// its drawn route.
    static func badgeCoordinate(of ride: RiddenRouteStore.DrawnRide) -> Coordinate? {
        let strokes = ride.segments.sorted {
            ($0.segmentIndex, $0.partIndex) < ($1.segmentIndex, $1.partIndex)
        }.map(\.coordinates)
        return TripNoteRoute(strokes: strokes, stopArcs: []).midpoint()
    }

    // MARK: - picking

    /// A place picked on the ride: where on the route it fell, and the
    /// anchor it would be saved as.
    struct Pick: Equatable {
        var projection: TripNoteRoute.Projection
        var anchor: TripNoteAnchor
    }

    /// The pick for a display-datum point (the map centre under the pick
    /// pin). Nil when the point is further than `maxMeters` from the route.
    static func pick(at point: Coordinate, on ride: RiddenRouteStore.DrawnRide,
                     maxMeters: Double, stationSnapMeters: Double) -> Pick? {
        let display = route(of: ride, datum: .display)
        guard let projection = display.project(point, maxMeters: maxMeters,
                                               stationSnapMeters: stationSnapMeters) else { return nil }
        // The fallback is WGS84: read it off the WGS84 route at the same
        // place. Where both datums agree the projected point is already it.
        let wgs84 = route(of: ride, datum: .wgs84)
        let fallback: Coordinate? = {
            if let stop = projection.nearStop { return wgs84.point(atStop: stop) }
            if let point = wgs84.point(fromStop: projection.fromStop, toStop: projection.toStop,
                                       fraction: projection.fraction) { return point }
            return AppleMapDatum.gcj02Countries.contains(ride.country) ? nil : projection.point
        }()
        guard let anchor = display.anchor(for: projection, stops: ride.stops, fallback: fallback) else {
            return nil
        }
        return Pick(projection: projection, anchor: anchor)
    }

    /// Where `anchor` sits on the map today (display datum).
    static func displayCoordinate(of anchor: TripNoteAnchor, on ride: RiddenRouteStore.DrawnRide) -> Coordinate? {
        place([TripNote(id: "", category: "", text: "", anchor: anchor)], on: ride).first?.coordinate
    }

    /// The anchor for a device location (WGS84), snapped onto the ride's
    /// route. Nil when the reader is more than `maxMeters` from it.
    static func anchor(forLocation location: Coordinate, on ride: RiddenRouteStore.DrawnRide,
                       maxMeters: Double = 2_000, stationSnapMeters: Double = 150) -> TripNoteAnchor? {
        let wgs84 = route(of: ride, datum: .wgs84)
        guard let projection = wgs84.project(location, maxMeters: maxMeters,
                                             stationSnapMeters: stationSnapMeters) else { return nil }
        return wgs84.anchor(for: projection, stops: ride.stops, fallback: projection.point)
    }

    /// A station anchor for stop `index` of the trip's own `stops`. The
    /// fallback is the stop's WGS84 place on `ride`'s route, when there is a
    /// drawn ride and its stop at that index is the same station; without a
    /// ride the anchor simply has no fallback.
    static func stationAnchor(stopIndex index: Int, stops: [Stop],
                              ride: RiddenRouteStore.DrawnRide?) -> TripNoteAnchor? {
        guard stops.indices.contains(index) else { return nil }
        let station = TripNoteStation(stop: stops[index])
        var fallback: Coordinate?
        if let ride, ride.stops.indices.contains(index), station.matches(ride.stops[index]) {
            fallback = route(of: ride, datum: .wgs84).point(atStop: index)
        }
        return .station(station, fallback: fallback)
    }
}
