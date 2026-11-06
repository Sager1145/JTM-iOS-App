import Foundation
import Testing
@testable import RailCore

/// ADR 0007 amendment 1, option B: a guard-rejected endpoint is drawn but
/// tagged `.unproven`, flagged as a non-boundary physical gap, and records
/// no far-endpoint identity.
struct RouteSolverEndpointGuardTests {
    private let o = Coordinate(lon: 139, lat: 35)
    private let farT = Coordinate(lon: 139.495, lat: 35)        // ~45 km east of O
    private let nearT = Coordinate(lon: 139.01, lat: 35.08)     // ~9 km from O, isolated track
    private let nearTEnd = Coordinate(lon: 139.0, lat: 35.08)
    private let mid = Coordinate(lon: 139.25, lat: 35)

    private func rail(_ points: [Coordinate], line: String) -> RouteGraph.SectionFeature {
        .init(properties: .init(lineName: line, operator: "Operator", institutionTypeCode: "1"), lines: [points])
    }
    private func station(_ point: Coordinate, code: String, name: String, line: String) -> Stations.Feature {
        .init(properties: ["n02_station_code": .string(code), "station_name": .string(name),
            "line_name": .string(line), "operator": .string("Operator"),
            "institution_type_code": .string("1")], geometry: .init(type: "Point", coordinates: .array([
                .number(point.lon), .number(point.lat)])))
    }
    private var sections: [RouteGraph.SectionFeature] {
        [rail([o, mid, farT], line: "Main"), rail([nearTEnd, nearT], line: "Iso")]
    }
    private var stationFeatures: [Stations.Feature] {
        [station(o, code: "O", name: "O", line: "Main"),
         station(farT, code: "TFAR", name: "T", line: "Main"),
         station(nearT, code: "TNEAR", name: "T", line: "Iso")]
    }
    private func graph() -> RouteGraph.Graph { RouteGraph.build(from: sections) }

    private func solve(_ section: RouteSection, graph: RouteGraph.Graph) -> RouteSolver.SolvedSection? {
        RouteSolver.solveSection(section, segmentIndex: 0, train: .init(), country: "jp",
            graph: graph, stations: Stations.Index(stationFeatures))
    }

    @Test("Name-only far endpoint rejected by the guard comes back unproven but drawn")
    func nameOnlyFarEndpointIsUnproven() throws {
        let section = RouteSection(from: "O", to: "T", fromN02StationCode: "O")
        let solved = try #require(solve(section, graph: graph()))
        #expect(solved.outcome == .unproven)
        #expect(solved.coordinates.first == o)
        #expect(solved.coordinates.last == farT)
    }

    @Test("Naming the far station by N02 code is proven")
    func codedFarEndpointIsProven() throws {
        let section = RouteSection(from: "O", to: "T", fromN02StationCode: "O", toN02StationCode: "TFAR")
        let solved = try #require(solve(section, graph: graph()))
        #expect(solved.outcome == .proven)
        #expect(solved.coordinates.last == farT)
    }

    @Test("A short name-only route is proven")
    func shortNameOnlyIsProven() throws {
        let short = [rail([o, Coordinate(lon: 139.05, lat: 35)], line: "Main")]
        let index = Stations.Index([station(o, code: "O", name: "O", line: "Main"),
            station(Coordinate(lon: 139.05, lat: 35), code: "TFAR", name: "T", line: "Main")])
        let section = RouteSection(from: "O", to: "T", fromN02StationCode: "O")
        let solved = try #require(RouteSolver.solveSection(section, segmentIndex: 0, train: .init(),
            country: "jp", graph: RouteGraph.build(from: short), stations: index))
        #expect(solved.outcome == .proven)
    }

    @Test("Resolution draws the unproven section, flags it, and records no path keys or physical route")
    func resolutionFlagsUnprovenSection() throws {
        let section = RouteSection(from: "O", to: "T", fromN02StationCode: "O")
        let train = Train(id: "guard-fixture", date: "2026-07-01", number: "Local", company: "Operator",
            origin: "O", destination: "T", routeSections: [section],
            stops: [Stop(name: "O", n02StationCode: "O", rideSegment: true),
                    Stop(name: "T", rideSegment: false)], region: "jp")
        var resolution = RideRouteResolution(
            inputs: .init(sections: sections, stationCollection: .init(features: stationFeatures)),
            country: "jp")
        let result = try resolution.resolve(.init(train: train))
        #expect(result.disposition == .geometry)
        let segment = try #require(result.segments.first)
        #expect(segment.segmentIndex == 0)
        #expect(segment.physicalRoute == nil)
        #expect(segment.drawnCoordinates.last == farT)
        #expect(result.sourcePhysicalPathKeys[0] == nil)
        let gap = try #require(result.physicalGaps.first)
        #expect(gap.segmentIndex == 0)
        #expect(gap.isUnproven)
        #expect(!gap.isBoundary)
        // Excluded from km: `MileageStatisticsStore` drops exactly the
        // sections `uncertifiedSections` names before mileage matching.
        #expect(RideRouteResolution.PhysicalGap.uncertifiedSections(result.physicalGaps) == [0])
    }

    @Test("PhysicalGap decodes legacy JSON as proven and round-trips isUnproven")
    func physicalGapCodable() throws {
        let legacy = try JSONDecoder().decode(RideRouteResolution.PhysicalGap.self,
            from: Data(#"{"segmentIndex":2,"isBoundary":false}"#.utf8))
        #expect(!legacy.isUnproven)
        let original = RideRouteResolution.PhysicalGap(segmentIndex: 3, isBoundary: false, isUnproven: true)
        let decoded = try JSONDecoder().decode(RideRouteResolution.PhysicalGap.self,
            from: JSONEncoder().encode(original))
        #expect(decoded.isUnproven && !decoded.isBoundary && decoded.segmentIndex == 3)
        #expect(!RideRouteResolution.PhysicalGap(segmentIndex: 1, isBoundary: true, isUnproven: true).isUnproven)
    }
}
