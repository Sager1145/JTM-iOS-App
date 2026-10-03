import Foundation
import Testing
@testable import RailCore

struct HakodateRouteConnectionTests {
    private let main = "jp-北海道旅客鉄道-函館線"

    private func network() throws -> RouteNetwork {
        RouteNetwork(lines: try PortFixtures.package(country: "jp").lines
            .filter { $0.id.hasPrefix(main) }.map { line in
                RouteNetwork.Line(
                    lineId: line.id, name: line.name, operator: line.operator,
                    isLoop: line.isLoop, alignmentDirection: line.alignmentDirection,
                    parts: DisplayParts.parts(for: line), intervals: RailIntervalCodes.intervals(for: line),
                    compactLine: line)
            })
    }

    @Test("Legacy branch hops match a complete physical chain and correct illegal one-way travel",
          arguments: [("函館", "000455"), ("大沼公園", "000426")])
    func legacyBranch(destination: (String, String)) throws {
        let root = try PortFixtures.repositoryRoot()
        let sections = try RouteGraph.SectionFeatureCollection.load(
            contentsOf: root.appending(path: "app/data/rail-sections.json")).features.filter {
                $0.properties.lineName == "函館線" && $0.properties.operator == "北海道旅客鉄道"
            }
        let collection = try Stations.FeatureCollection.load(
            contentsOf: root.appending(path: "app/data/stations.json"))
        let stations = Stations.Index(collection)
        let graph = RouteGraph.build(from: sections)
        let routeNetwork = try network()
        RouteSolver.addStationTransferConnectorEdges(graph: graph, stations: collection.features) { feature, point in
            routeNetwork.permitsStationConnectorNode(stationCode: Stations.stationCode(feature), point: point)
        }
        let section = RouteSection(
            from: "鹿部", to: destination.0,
            fromN02StationCode: "000423", toN02StationCode: destination.1,
            lineNames: ["函館線"], operatorNames: ["北海道旅客鉄道"])
        let solved = try #require(RouteSolver.solveSection(
            section, segmentIndex: 0,
            train: .init(trainType: "local", company: "JR北海道", rideDate: "2026-09-30"),
            country: "jp", graph: graph, stations: stations))
        #expect(solved.coordinates.count > 100)
        let feature = RouteFeature(
            geometry: .lineString(solved.coordinates),
            hints: .init(requiredLineNames: ["函館線"], requiredOperatorNames: ["北海道旅客鉄道"],
                         fromStationCode: "000423", toStationCode: destination.1))
        let canonical = try #require(routeNetwork.canonicalizeRouteFeature(feature))
        #expect(canonical.displayLineIds == [main + "-2", main])
        let endpoint = try #require(try PortFixtures.package(country: "jp").lines
            .first { $0.id == main }?.stations.first { $0.id == destination.1 })
        #expect(canonical.geometry.lines.last?.last == endpoint.coordinate)
        if destination.1 == "000455" {
            let shinHakodate = try #require(try PortFixtures.package(country: "jp").lines
                .first { $0.id == main }?.stations.first { $0.id == "000429" })
            #expect(canonical.geometry.lines.flatMap { $0 }.contains(shinHakodate.coordinate))
        }
    }

    @Test("Coded trunk–branch–trunk chains meet at exact junctions in both directions")
    func selectedBranchGeometry() throws {
        let package = try PortFixtures.package(country: "jp")
        // Render an authored interval chain, without deriving junction
        // connectivity from the compact station identities.
        let rows = [main, main + "-2", main]
        let endpoints = ["000424", "000420", "000427", "000426"]
        var codes: [String] = []
        for index in rows.indices {
            let row = CompactPackage(format: package.format, version: package.version, country: package.country,
                                     lines: package.lines.filter { $0.id == rows[index] })
            let leg = try #require(RailwayRouteChoices.choices(package: row, originCode: endpoints[index],
                                                               destinationCode: endpoints[index + 1]).first)
            codes += leg.sectionCodes
        }
        let hints = RouteHints(requiredLineIDs: rows, sectionCodes: codes,
                               fromStationCode: "000424", toStationCode: "000426")
        let network = try network()
        let source = try #require(network.sourceGeometry(for: hints))
        let display = try #require(network.canonicalizeRouteFeature(RouteFeature(geometry: nil, hints: hints)))
        #expect(source.lines.count == 1)
        #expect(display.geometry.lines.count == 1)
        #expect(display.displayLineIds == [main, main + "-2"])
        for code in ["000420", "000427"] {
            let station = try #require(package.lines.first { $0.id == main }?.stations.first { $0.id == code })
            #expect(source.lines[0].contains(station.coordinate))
            #expect(display.geometry.lines[0].contains(station.coordinate))
        }
        let reverseHints = RouteHints(
            requiredLineIDs: rows, sectionCodes: codes.reversed(),
            fromStationCode: "000426", toStationCode: "000424")
        let reverseSource = try #require(network.sourceGeometry(for: reverseHints))
        let reverseDisplay = try #require(network.canonicalizeRouteFeature(
            RouteFeature(geometry: nil, hints: reverseHints)))
        #expect(reverseSource.lines[0] == Array(source.lines[0].reversed()))
        #expect(reverseDisplay.geometry.lines[0] == Array(display.geometry.lines[0].reversed()))
    }
}
