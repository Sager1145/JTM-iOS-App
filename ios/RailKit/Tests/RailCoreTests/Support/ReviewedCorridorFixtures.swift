import Foundation
import Testing
import RailCore

/// One resource read shared by the reviewed corridor suites. Raw and
/// history-applied views preserve the source scope each proof used originally.
enum ReviewedCorridorFixtures {
    struct Snapshot: Sendable {
        let sections: [RouteGraph.SectionFeature]
        let stations: Stations.FeatureCollection
        let junctions: [RouteGraph.PhysicalJunction]
    }
    private static let loaded: Result<(Snapshot, Snapshot), Error> = Result {
        let data = try PortFixtures.repositoryRoot().appendingPathComponent("app/data")
        let sections = try RouteGraph.SectionFeatureCollection.load(
            contentsOf: data.appendingPathComponent("rail-sections.json")).features
        let stations = try Stations.FeatureCollection.load(
            contentsOf: data.appendingPathComponent("stations.json"))
        let registry = try PhysicalRailJunctionRegistry(data: Data(
            contentsOf: data.appendingPathComponent("physical-rail-junctions.json")))
        let junctions = registry.junctions(for: "jp")
        let raw = Snapshot(sections: sections, stations: stations, junctions: junctions)
        var historicalSections = sections, historicalStations = stations.features
        let overlay = try RailHistoryOverlay.load(from: data.appendingPathComponent("rail-history.json"))
        _ = RailHistory.apply(overlay, sections: &historicalSections, stations: &historicalStations)
        return (raw, Snapshot(sections: historicalSections,
            stations: .init(features: historicalStations), junctions: junctions))
    }
    static func snapshot(history: Bool) throws -> Snapshot {
        let snapshots = try loaded.get()
        return history ? snapshots.1 : snapshots.0
    }
}

/// Calls the production worker. The graph remains only for independent source
/// and registry assertions; no RouteSolver implementation step is invoked.
struct ReviewedCorridorWorker {
    struct Proof {
        let coordinates: [Coordinate]
        let rawPathKeys: [String]
        var physicalLength: Double {
            zip(coordinates, coordinates.dropFirst()).reduce(0) {
                $0 + Geometry.distanceMeters($1.0, $1.1)
            }
        }
    }
    private var independent: RideRouteResolution
    private var joined: RideRouteResolution
    init(sections: [RouteGraph.SectionFeature], stations: Stations.FeatureCollection,
         junctions: [RouteGraph.PhysicalJunction]) {
        independent = .init(inputs: .init(sections: sections, stationCollection: stations), country: "jp")
        joined = .init(inputs: .init(sections: sections, stationCollection: stations,
            physicalJunctions: junctions), country: "jp")
    }
    mutating func solve(reviewed: Bool, section: RouteSection, company: String,
                        date: String) throws -> Proof? {
        let train = Train(id: "reviewed-corridor", date: date, number: "Reviewed",
            company: company, origin: section.from ?? "", destination: section.to ?? "",
            routeSections: [section], stops: [
                Stop(name: section.from ?? "", n02StationCode: section.fromN02StationCode),
                Stop(name: section.to ?? "", n02StationCode: section.toN02StationCode)], region: "jp")
        let request = RideRouteResolution.Request(train: train)
        let result = try reviewed ? joined.resolve(request) : independent.resolve(request)
        guard result.disposition == .geometry else {
            #expect(result.segments.isEmpty)
            return nil
        }
        #expect(result.physicalGaps.isEmpty)
        let segment = try #require(result.segments.first)
        #expect(result.segments.count == 1)
        #expect(segment.sourceCoordinates == segment.drawnCoordinates)
        let keys = try #require(result.sourcePhysicalPathKeys[0])
        return Proof(coordinates: segment.sourceCoordinates, rawPathKeys: keys)
    }
}
