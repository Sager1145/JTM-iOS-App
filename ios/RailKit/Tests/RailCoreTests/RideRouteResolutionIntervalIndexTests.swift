import Foundation
import Testing
@testable import RailCore

/// The official-interval index only serves `RouteSolver.solveOfficialInterval`,
/// which answers for tw/hk/mo/cn alone. Japan must never pay to build it.
struct RideRouteResolutionIntervalIndexTests {
    private let a = Coordinate(lon: 139, lat: 35)
    private let bend = Coordinate(lon: 139.01, lat: 35.0008)
    private let b = Coordinate(lon: 139.02, lat: 35)

    @Test("A Japanese legacy solve never builds the official-interval index")
    func japanSkipsIntervalIndex() throws {
        let source = inputs()
        var resolution = RideRouteResolution(inputs: source, country: "jp")
        let result = try resolution.resolve(.init(train: train(region: "jp")))

        #expect(result.disposition == .geometry)
        #expect(result.segments.first?.sourceCoordinates == [a, bend, b])
        #expect(!source.officialIntervals.isBuilt)
    }

    @Test("Official-interval countries still build the index on the legacy path",
          arguments: ["tw", "hk", "mo", "cn"])
    func officialCountriesBuildIntervalIndex(country: String) throws {
        let source = inputs()
        var resolution = RideRouteResolution(inputs: source, country: country)
        _ = try resolution.resolve(.init(train: train(region: country)))

        #expect(source.officialIntervals.isBuilt)
    }

    @Test("The gated set matches the country guard of solveOfficialInterval")
    func gateMatchesSolverGuard() throws {
        // Skipping the build is behavior-neutral only while the solver rejects
        // every other country before reading the index. Tripwire on its guard.
        let url = try PortFixtures.repositoryRoot()
            .appendingPathComponent("ios/RailKit/Sources/RailCore/Routing/RouteSolver.swift")
        let text = try String(contentsOf: url, encoding: .utf8)
        let function = try #require(text.range(of: "static func solveOfficialInterval("))
        let body = text[function.upperBound...]
        let guardLine = try #require(body.split(separator: "\n").first { $0.contains("guard [") })
        let open = try #require(guardLine.firstIndex(of: "["))
        let close = try #require(guardLine.firstIndex(of: "]"))
        let countries = guardLine[guardLine.index(after: open)..<close]
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: CharacterSet(charactersIn: " \"")) }
        #expect(guardLine.contains(".contains(country)"))
        #expect(Set(countries) == RideRouteResolution.officialIntervalCountries)
    }

    @Test("Clearing the resolution memo keeps decoded inputs and answers")
    func clearResolutionMemo() throws {
        let source = inputs()
        var resolution = RideRouteResolution(inputs: source, country: "jp")
        let first = try resolution.resolve(.init(train: train(region: "jp")))
        #expect(source.resolutionMemo.retainedEntryCount > 0)

        source.clearResolutionMemo()
        #expect(source.resolutionMemo.retainedEntryCount == 0)
        #expect(source.resolutionMemo.retainedCost == 0)

        let second = try resolution.resolve(.init(train: train(region: "jp")))
        #expect(second.segments.map(\.sourceCoordinates) == first.segments.map(\.sourceCoordinates))
        #expect(source.resolutionMemo.retainedEntryCount > 0)
    }

    private func inputs() -> RideRouteResolution.SourceInputs {
        let rail = RouteGraph.SectionFeature(
            properties: .init(lineName: "Rail", operator: "Operator", institutionTypeCode: "1"),
            lines: [[a, bend, b]])
        return .init(sections: [rail], stationCollection: .init(features: [station(a, "A"), station(b, "B")]))
    }

    private func station(_ coordinate: Coordinate, _ code: String) -> Stations.Feature {
        .init(properties: ["n02_station_code": .string(code), "station_name": .string(code),
            "line_name": .string("Rail"), "operator": .string("Operator"),
            "institution_type_code": .string("1")], geometry: .init(type: "Point",
                coordinates: .array([.number(coordinate.lon), .number(coordinate.lat)])))
    }

    private func leg() -> RouteSection {
        .init(from: "A", to: "B", fromN02StationCode: "A", toN02StationCode: "B",
            lineNames: ["Rail"], operatorNames: ["Operator"])
    }

    private func train(region: String) -> Train {
        .init(id: "interval-index-fixture", date: "2026-07-01", number: "Local", company: "Operator",
            origin: "A", destination: "B", routeSections: [leg()],
            stops: [Stop(name: "A", n02StationCode: "A", rideSegment: true),
                    Stop(name: "B", n02StationCode: "B", rideSegment: false)],
            region: region)
    }
}
