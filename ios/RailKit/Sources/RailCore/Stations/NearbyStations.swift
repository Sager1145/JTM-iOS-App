import Foundation

/// Nearest-station lookup by haversine distance. Pure; the caller supplies
/// the location.
public enum NearbyStations {
    public struct Result: Sendable, Equatable {
        public let place: StationIndex.Place
        public let distanceMeters: Double

        public init(place: StationIndex.Place, distanceMeters: Double) {
            self.place = place
            self.distanceMeters = distanceMeters
        }
    }

    /// The `limit` stations closest to (`lat`, `lon`), nearest first. Equal
    /// distances keep the order of `stations`. Non-finite input yields none.
    public static func nearest(
        to lat: Double, lon: Double, in stations: [StationIndex.Place], limit: Int = 3
    ) -> [Result] {
        guard limit > 0, lat.isFinite, lon.isFinite, abs(lat) <= 90, abs(lon) <= 180 else { return [] }
        let origin = Coordinate(lon: lon, lat: lat)
        let ranked = stations.enumerated().map { offset, place in
            (offset, Result(place: place,
                            distanceMeters: Geometry.distanceMeters(origin, place.coordinate)))
        }
        return ranked
            .sorted { ($0.1.distanceMeters, $0.0) < ($1.1.distanceMeters, $1.0) }
            .prefix(limit)
            .map(\.1)
    }
}
