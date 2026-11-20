import Foundation
import RailCore
import RailPresentation
import Testing

@testable import RailMap

/// Real bundled sample trips in, tier marks out. Every earlier test of the
/// selected-trip tiers started from hand-made stations or from source text,
/// so none noticed that a stored trip's stops never received a drawn
/// position: `DrawnSegment.from`/`to` carry station NAMES, and the position
/// check compared them with station identifiers.
@MainActor
struct SelectedTripMarksIntegrationTests {
    private struct Part: Decodable {
        struct Route: Decodable { let features: [Feature] }
        struct Feature: Decodable {
            struct Props: Decodable { let segment_index: Int; let from: String?; let to: String? }
            struct Geometry: Decodable { let coordinates: [[Double]] }
            let properties: Props
            let geometry: Geometry
        }
        let train: Train
        let route: Route
    }

    private static let settings = MapRideMarkers.Settings(
        terminalRadius: 6, passRadius: 3, stopCentreRadius: 3, markerStrokeScale: 1, focusBoost: 1)

    private static func ride(part file: String) throws -> RiddenRouteStore.DrawnRide {
        var url = URL(fileURLWithPath: #filePath)
        for _ in 0..<4 { url.deleteLastPathComponent() }
        url.appendPathComponent("app/data/sample-data/\(file)")
        let part = try JSONDecoder().decode(Part.self, from: Data(contentsOf: url))
        let segments = part.route.features.map { feature in
            RiddenRouteStore.DrawnSegment(
                segmentIndex: feature.properties.segment_index,
                from: feature.properties.from, to: feature.properties.to,
                coordinates: feature.geometry.coordinates.map { Coordinate(lon: $0[0], lat: $0[1]) },
                country: part.train.region ?? "jp")
        }
        return RiddenRouteStore.drawnRide(
            part.train, country: part.train.region ?? "jp", segments: segments,
            expectedSections: part.train.routeSections ?? [])
    }

    private static func ranking(of ride: RiddenRouteStore.DrawnRide)
        -> (positions: Int, stations: Int, ranking: SelectedTripStationTiers.Ranking)
    {
        let drawn = MapRideMarkers.drawn(rides: [ride], settings: settings)
        let stations = MapRideMarkers.tierStations(of: ride, drawn: drawn)
        return (MapRideMarkers.stopPositions(of: ride).count, stations.count, SelectedTripStationTiers.rank(stations))
    }

    private static func dots(_ ranking: SelectedTripStationTiers.Ranking, _ mpp: Double)
        -> [SelectedTripStationTiers.StationClass: Int]
    {
        ranking.counts(metresPerPoint: mpp).mapValues(\.dots)
    }

    @Test("a stored metro trip's stops all take drawn positions and reach the tiers")
    func marunouchi() throws {
        let ride = try Self.ride(part: "part-008.json")
        #expect(ride.stops.count == 8)
        let result = Self.ranking(of: ride)
        #expect(result.positions == 8)
        let counts = result.ranking.counts(metresPerPoint: 3)
        #expect(counts[.terminal]?.dots == 2 && counts[.terminal]?.names == 2)
        #expect(counts[.stop]?.dots == 6 && counts[.stop]?.names == 6)
    }

    @Test("a stored Shinkansen trip shows terminals, stops and recorded passes by zoom")
    func hayabusa27() throws {
        let ride = try Self.ride(part: "part-067.json")
        #expect(ride.stops.count == 26)
        let result = Self.ranking(of: ride)
        #expect(result.positions == 26)
        let close = Self.dots(result.ranking, 20)
        #expect(close[.terminal] == 2)
        // Line-change stops are their own class but still stopping stations.
        #expect((close[.stop] ?? 0) + (close[.transfer] ?? 0) == 6)
        #expect(close[.pass] == 18)
        // On an overview passing stations never show.
        #expect((Self.dots(result.ranking, 400)[.pass] ?? 0) == 0)
        // Zooming in never removes a mark.
        let nearer = Self.dots(result.ranking, 5)
        for (stationClass, count) in close { #expect((nearer[stationClass] ?? 0) >= count) }
    }

    @Test("another stored Shinkansen trip positions every stop")
    func hayabusa59() throws {
        let ride = try Self.ride(part: "part-024.json")
        let result = Self.ranking(of: ride)
        #expect(result.positions == ride.stops.count)
        let close = Self.dots(result.ranking, 20)
        #expect(close[.terminal] == 2)
        #expect(close[.stop] == 1)
        #expect(close[.pass] == 7)
    }
}
