import MapKit
import RailCore
import RailPresentation

/// Owns interaction-only indexes and the claim shared by MapKit's two tap paths.
/// The coordinator supplies current drawn geometry; this object never selects a
/// journey or stores an authoritative selection of its own.
@MainActor
final class MapInteractionCoordinator {
    typealias Naming = (String, String?) -> (display: String, readings: [String]?)

    private var stations: [RailNetworkStore.DrawnStation] = []
    private var cachedTapIndex: RideTapIndex?
    private var rideAnsweredTap: ContinuousClock.Instant?

    /// Geometry/filter/matching changes discard the index without rebuilding
    /// inside a SwiftUI update. The first subsequent tap pays for its snapshot.
    func invalidateRideGeometry() { cachedTapIndex = nil }

    func beginTouch() { rideAnsweredTap = nil }

    var suppressesStationSelection: Bool {
        rideAnsweredTap.map { ContinuousClock.now - $0 < .seconds(1) } ?? false
    }

    func rideHits(
        at point: CGPoint, on mapView: MKMapView,
        rides: [RiddenRouteStore.DrawnRide],
        drawnStrokes: (RiddenRouteStore.DrawnRide) -> [[Coordinate]]
    ) -> [String] {
        let index: RideTapIndex
        if let cachedTapIndex {
            index = cachedTapIndex
        } else {
            let interval = RailSignpost.map.begin("map.tapIndex.build")
            index = RideTapIndex(rides: rides, drawnStrokes: drawnStrokes)
            self.cachedTapIndex = index
            RailSignpost.map.end("map.tapIndex.build", interval)
        }
        // The pitch fallback still projects the complete drawn geometry.
        let candidates =
            index.candidates(at: point, on: mapView)
            ?? index.allCandidates(on: mapView)
        RailSignpost.map.mark(
            "map.tap.projected",
            candidates.reduce(0) { $0 + $1.strokes.reduce(0) { $0 + $1.count } }, index.vertexCount)
        let hits = RideTapResolver.hits(
            at: RideTapResolver.Point(x: point.x, y: point.y), among: candidates)
        if !hits.isEmpty { rideAnsweredTap = .now }
        return hits
    }

    /// Mounted selected beads, including MapKit's margin beyond their own view
    /// target, preserve selection when the tap misses the route at an endpoint.
    func containsSelectedStation(
        at point: CGPoint, on mapView: MKMapView,
        hasSelection: Bool, annotations: [MKAnnotation]
    ) -> Bool {
        guard hasSelection else { return false }
        let reach = RailStyle.minimumTouchTarget * 0.75
        for annotation in annotations {
            guard let dot = annotation as? RideStationAnnotation, dot.selected else { continue }
            let centre = mapView.convert(dot.coordinate, toPointTo: mapView)
            let dx = centre.x - point.x
            let dy = centre.y - point.y
            if dx * dx + dy * dy <= reach * reach { return true }
        }
        return false
    }

    func tearDown() {
        cachedTapIndex = nil
        rideAnsweredTap = nil
        stations = []
        stationsByCode.removeAll()
        stationsByName.removeAll()
    }

    /// The card one tapped annotation opens, or `nil` when the thing
    /// tapped was not a station at all.
    func stationCard(for annotation: any MKAnnotation, named: Naming) -> StationCard? {
        if let station = annotation as? StationAnnotation {
            return StationCard(
                station: station.station,
                displayName: station.displayName,
                readings: station.readings)
        }
        if let dot = annotation as? RideStationAnnotation {
            return rideStationCard(
                name: dot.rawName, code: dot.stationCode, region: dot.region,
                at: Coordinate(lon: dot.coordinate.longitude, lat: dot.coordinate.latitude), named: named)
        }
        if let caption = annotation as? RideLabelAnnotation {
            return rideStationCard(
                name: caption.rawName, code: caption.stationCode, region: caption.region,
                at: Coordinate(lon: caption.coordinate.longitude, lat: caption.coordinate.latitude),
                named: named)
        }
        return nil
    }

    /// The card behind one of a ride's own dots.
    ///
    /// A ride's stop knows its name, its station-group code and where
    /// the route drew it; what it does NOT know is which railways run
    /// through the place, which is the whole body of the card. That
    /// lives on the network's side, so the stop is resolved back to a
    /// platform there and the platform's popup model is used — which is
    /// also what makes the card identical to the one the network's own
    /// bead at that station opens, down to the name and the readings.
    ///
    /// When nothing resolves, the card is still opened, with the stop's
    /// own name and no line rows. The reader tapped a station and a
    /// station is what they get; the alternative is a mark that answers
    /// a tap with silence, which is the fault this replaced.
    private func rideStationCard(
        name: String, code: String?, region: Region?, at position: Coordinate, named: Naming
    ) -> StationCard {
        if let station = networkStation(
            code: code, name: name, region: region, near: position)
        {
            // Named and read exactly as `StationAnnotation` names and
            // reads the same platform — the readings table is keyed on
            // the platform's own id first and its name second.
            let named = named(station.name, station.id)
            return StationCard(
                station: station, displayName: named.display,
                readings: named.readings)
        }
        let named = named(name, code)
        return StationCard(
            id: "stop:\(Stations.normalizeStationName(name))"
                + "@\(position.lat),\(position.lon)",
            coordinate: position,
            displayName: named.display,
            rawName: name,
            // A stop that resolved to no platform still names a
            // region well enough to search in: the store's own
            // station code says which package it came from, and a
            // hand-typed ride with no code at all is Japanese for the
            // same reason `naming` reads it as Japanese.
            region: region ?? Region.fromStationCode(code) ?? .jp,
            readings: named.readings,
            nameRoma: "",
            lines: [],
            stationCode: code)
    }

    /// The network platform a ride's stop stands on.
    ///
    /// By CODE first, and it is the answer that can be trusted: a
    /// station group is an identity the ride's stop and the network's
    /// station both carry (`n02_station_code`), so a match is the same
    /// station rather than a station that reads the same. The nearest
    /// of the group's platforms is taken, which is also what settles a
    /// code that two countries' packages both happen to use — a ride in
    /// Japan cannot resolve to a Korean platform 1,000 km away.
    ///
    /// By NAME second, for the stores that carry no code — a journey
    /// typed in by hand, or one imported from a source that had none.
    /// A name is a guess and is capped accordingly: 同名 stations are
    /// common enough (中山, 大手町) that an uncapped one would hand the
    /// reader another prefecture's railways.
    private func networkStation(
        code: String?, name: String, region: Region?, near position: Coordinate
    ) -> RailNetworkStore.DrawnStation? {
        // Same-region candidates are preferred whenever the ride
        // knows its region — a station code or name shared with
        // another country's package must not steal the match. Only
        // when nothing in the ride's own region resolves does the
        // search fall back across every region, which keeps a ride
        // with no known region (`region == nil`) behaving exactly
        // as it always has.
        func nearest(_ indexes: [Int], within metres: Double) -> RailNetworkStore.DrawnStation? {
            let candidates =
                indexes
                .map {
                    (
                        station: stations[$0],
                        distance:
                            Geometry.distanceMeters(stations[$0].coordinate, position)
                    )
                }
                .filter { $0.distance <= metres }
            if let region {
                let sameRegion = candidates.filter { $0.station.region == region }
                if let hit = sameRegion.min(by: { $0.distance < $1.distance }) {
                    return hit.station
                }
            }
            return candidates.min { $0.distance < $1.distance }?.station
        }
        if let code, !code.isEmpty, let group = stationsByCode[code],
            let hit = nearest(group, within: .infinity)
        {
            return hit
        }
        let key = Stations.normalizeStationName(name)
        guard !key.isEmpty, let sameName = stationsByName[key] else { return nil }
        return nearest(sameName, within: Self.nameMatchMeters)
    }

    /// How far a NAME may reach for a platform. Generous next to the
    /// ~600 m the label election merges on, because a stop's drawn
    /// position is the route's own geometry rather than the station
    /// table's point, and a complex like 梅田/大阪 spreads its platforms
    /// over half a kilometre before either number applies.
    static let nameMatchMeters: Double = 2_000

    /// The network's platforms, indexed by the two keys a ride's stop
    /// can offer. Rebuilt when the station list itself changes, which
    /// is once per region as the packages land.
    ///
    /// Indices rather than rows: every `DrawnStation` carries its whole
    /// popup model, and Japan alone ships some 12,000 of them.
    private var stationsByCode: [String: [Int]] = [:]
    private var stationsByName: [String: [Int]] = [:]

    func replaceStations(_ stations: [RailNetworkStore.DrawnStation]) {
        self.stations = stations
        stationsByCode.removeAll(keepingCapacity: true)
        stationsByName.removeAll(keepingCapacity: true)
        for (index, station) in stations.enumerated() {
            if !station.stationCode.isEmpty {
                stationsByCode[station.stationCode, default: []].append(index)
            }
            let key = Stations.normalizeStationName(station.name)
            if !key.isEmpty { stationsByName[key, default: []].append(index) }
        }
    }

}
