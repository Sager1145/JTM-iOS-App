import Foundation
import MapKit
import RailCore

/// Asks MapKit which datum its basemap uses in each candidate region.
///
/// A place search answers in the same datum as the tiles it is served with,
/// so a station MapKit knows well, looked up next to its package anchor,
/// lands either on the WGS84 anchor or on its GCJ-02 image about 500 m away.
/// Several stations per region vote; one POI never decides a region (a lookup
/// can return a station building, an entrance, or another station of the
/// same name), and a region whose votes are missing or mixed keeps its
/// previous verdict rather than guessing.
@MainActor
enum AppleMapDatumProbe {
    private struct Reference {
        let country: String
        let query: String
        /// The station's WGS84 anchor in the region's package.
        let anchor: Coordinate
    }

    private enum Vote { case wgs84, gcj02 }

    /// Stations whose MapKit result sat within 80 m of their anchor on the
    /// global service on 2026-09-17, spread across each region.
    private static let references: [Reference] = [
        Reference(country: "tw", query: "臺中車站", anchor: Coordinate(lon: 120.686991, lat: 24.137117)),
        Reference(country: "tw", query: "新竹車站", anchor: Coordinate(lon: 120.971691, lat: 24.801403)),
        Reference(country: "tw", query: "屏東車站", anchor: Coordinate(lon: 120.486143, lat: 22.668859)),
        Reference(country: "tw", query: "羅東車站", anchor: Coordinate(lon: 121.7746, lat: 24.677899)),
        Reference(country: "hk", query: "Kowloon Tong Station", anchor: Coordinate(lon: 114.175843, lat: 22.336974)),
        Reference(country: "hk", query: "Tung Chung Station", anchor: Coordinate(lon: 113.941692, lat: 22.289366)),
        Reference(country: "hk", query: "Sha Tin Station", anchor: Coordinate(lon: 114.18739, lat: 22.382538)),
        Reference(country: "mo", query: "Barra Station", anchor: Coordinate(lon: 113.529403, lat: 22.183615)),
        Reference(country: "mo", query: "Cotai East Station", anchor: Coordinate(lon: 113.569082, lat: 22.14827)),
        Reference(country: "kr", query: "수원역", anchor: Coordinate(lon: 126.999704, lat: 37.266118)),
        Reference(country: "kr", query: "광주송정역", anchor: Coordinate(lon: 126.790887, lat: 35.138142)),
        Reference(country: "kr", query: "대전역", anchor: Coordinate(lon: 127.435002, lat: 36.332538)),
    ]

    /// A result counts only when it is this close to one candidate…
    private static let acceptMetres = 250.0
    /// …and at least this much further from the other.
    private static let marginMetres = 200.0

    /// Runs every lookup and saves the verdict for the next build of the map
    /// (`AppleMapDatum.adopt`). Lookups still outstanding after `limit` are
    /// cancelled and do not vote; it returns as soon as all have answered.
    static func run(within limit: Duration) async {
        var votes: [String: [Vote]] = [:]
        await withTaskGroup(of: (String, Vote?)?.self) { group in
            for reference in references {
                group.addTask { (reference.country, await vote(for: reference)) }
            }
            group.addTask {
                try? await Task.sleep(for: limit)
                return nil
            }
            var outstanding = references.count
            for await answer in group {
                // `nil` is the timer: whatever has not answered does not vote.
                guard let (country, vote) = answer else { break }
                if let vote { votes[country, default: []].append(vote) }
                outstanding -= 1
                if outstanding == 0 { break }
            }
            group.cancelAll()
        }
        var next = AppleMapDatum.gcj02Countries
        var decided = false
        for country in AppleMapDatum.candidateCountries {
            let cast = votes[country] ?? []
            guard cast.count >= 2, Set(cast).count == 1 else { continue }
            decided = true
            if cast[0] == .gcj02 { next.insert(country) } else { next.remove(country) }
        }
        // Offline, or MapKit refusing every lookup: keep the saved verdict.
        AppleMapDatum.adopt(gcj02Countries: decided ? next : nil)
    }

    private static func vote(for reference: Reference) async -> Vote? {
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = reference.query
        request.pointOfInterestFilter = MKPointOfInterestFilter(including: [.publicTransport])
        request.region = MKCoordinateRegion(
            center: CLLocationCoordinate2D(
                latitude: reference.anchor.lat, longitude: reference.anchor.lon),
            latitudinalMeters: 4_000, longitudinalMeters: 4_000)
        let search = MKLocalSearch(request: request)
        let response = await withTaskCancellationHandler {
            try? await search.start()
        } onCancel: {
            search.cancel()
        }
        guard let item = response?.mapItems.first else { return nil }
        let found = coordinate(of: item)
        let wgs84 = metres(found, reference.anchor)
        let gcj02 = metres(found, AppleMapDatum.gcj02(fromWGS84: reference.anchor))
        if wgs84 <= acceptMetres, gcj02 - wgs84 >= marginMetres { return .wgs84 }
        if gcj02 <= acceptMetres, wgs84 - gcj02 >= marginMetres { return .gcj02 }
        return nil
    }

    private static func coordinate(of item: MKMapItem) -> CLLocationCoordinate2D {
        if #available(iOS 26.0, *) { return item.location.coordinate }
        return legacyCoordinate(of: item)
    }

    @available(iOS, deprecated: 26.0)
    private static func legacyCoordinate(of item: MKMapItem) -> CLLocationCoordinate2D {
        item.placemark.coordinate
    }

    private static func metres(_ found: CLLocationCoordinate2D, _ anchor: Coordinate) -> Double {
        CLLocation(latitude: found.latitude, longitude: found.longitude)
            .distance(from: CLLocation(latitude: anchor.lat, longitude: anchor.lon))
    }
}
