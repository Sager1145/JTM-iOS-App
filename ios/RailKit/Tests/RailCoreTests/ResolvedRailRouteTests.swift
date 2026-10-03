import Foundation
import Testing
@testable import RailCore

struct ResolvedRailRouteTests {
    private func fixture(surfaceTraversal: String = "both") throws -> RouteNetwork {
        let data = Data("""
        {"format":"compact-v1","version":"2025","country":"jp","lines":[
          {"id":"surface","name":"Administrative Surface","nameNorm":"Surface","operator":"Rail Co","rank":1,"permittedTraversal":"\(surfaceTraversal)",
           "stations":[["A","A",139,35],["B","B",139.01,35],["C","C",139.02,35]],
           "segments":[[1,0,[[139,35],[139.01,35]]],[1,0,[[139.01,35],[139.02,35]]]]},
          {"id":"tunnel","name":"Tunnel","rank":1,"stations":[["B","B",139.01,35],["D","D",139.01,35.01]],
           "segments":[[1,0,[[139.01,35],[139.01,35.01]]]]}
        ]}
        """.utf8)
        let package = try JSONDecoder().decode(CompactPackage.self, from: data)
        return RouteNetwork(lines: package.lines.map { line in
            RouteNetwork.Line(
                lineId: line.id, name: line.name, operator: line.operator,
                isLoop: line.isLoop, alignmentDirection: line.alignmentDirection,
                parts: CompactPackage.decodeDisplayIntervals(line),
                intervals: RailIntervalCodes.intervals(for: line), compactLine: line)
        })
    }

    @Test("Resolved metadata follows selected physical identities and first-occurrence order")
    func identitiesAndOrder() throws {
        let network = try fixture()
        let selected = ["tunnel@B:D", "surface@A:B", "surface@B:C"]
        let result = try #require(network.resolvedLines(sectionCodes: selected))
        #expect(result.map(\.lineID) == ["tunnel", "surface"])
        #expect(result.map(\.name) == ["Tunnel", "Surface"])
        #expect(result.map(\.operatorName) == [nil, "Rail Co"])
        let source = try #require(network.sourceGeometry(for: RouteHints(
            sectionCodes: ["surface@A:B", "surface@B:C"], fromStationCode: "A", toStationCode: "C")))
        #expect(abs(result[1].km - RouteNetwork.Metric.pathLength(source.lines[0]) / 1000) < 1e-10)
    }

    @Test("Repeated physical intervals retain their complete mileage contribution")
    func repeatedOccurrenceDistance() throws {
        let network = try fixture()
        let once = try #require(network.resolvedLines(sectionCodes: ["surface@A:B"]))
        let repeated = try #require(network.resolvedLines(sectionCodes: [
            "surface@A:B", "tunnel@B:D", "surface@A:B"]))
        #expect(repeated.map(\.lineID) == ["surface", "tunnel"])
        #expect(repeated[0].km == once[0].km * 2)
    }

    @Test("Empty, unknown and underspecified selected intervals reject partial metadata")
    func rejectsIncompleteSelection() throws {
        let network = try fixture()
        #expect(network.resolvedLines(sectionCodes: []) == nil)
        #expect(network.resolvedLines(sectionCodes: ["surface@A:B", "unknown"]) == nil)
        let line = network.lines[0]
        let unnamed = RouteNetwork(lines: [RouteNetwork.Line(
            lineId: line.lineId, name: nil, operator: nil, isLoop: false,
            alignmentDirection: nil, parts: line.parts, intervals: line.intervals)])
        #expect(unnamed.resolvedLines(sectionCodes: ["surface@A:B"]) == nil)
    }

    @Test("Resolved line metadata preserves identity, names and distances through Codable")
    func codableRoundTrip() throws {
        let network = try fixture()
        let result = try #require(network.resolvedLines(sectionCodes: ["surface@A:B", "tunnel@B:D"]))
        let encoded = try JSONEncoder().encode(result)
        #expect(try JSONDecoder().decode([ResolvedRailLine].self, from: encoded) == result)
    }

    @Test("Symmetric interval identities retain their selected forward and reverse travel order")
    func directedTravelOrder() throws {
        let network = try fixture()
        let forward = try #require(network.directedIntervals(
            sectionCodes: ["surface@A:B", "surface@B:C"], fromStationCode: "A", toStationCode: "C"))
        let reverse = try #require(network.directedIntervals(
            sectionCodes: ["surface@B:C", "surface@A:B"], fromStationCode: "C", toStationCode: "A"))
        #expect(forward.map(\.code) == ["surface@A:B", "surface@B:C"])
        #expect(forward.map(\.direction) == [1, 1])
        #expect(reverse.map(\.code) == ["surface@B:C", "surface@A:B"])
        #expect(reverse.map(\.direction) == [-1, -1])
        #expect(reverse.map(\.lineID) == ["surface", "surface"])
    }

    @Test("Disconnected, unknown, wrong-destination and prohibited-direction selections reject")
    func directedSelectionRejectsMismatch() throws {
        let network = try fixture(surfaceTraversal: "forward")
        #expect(network.directedIntervals(sectionCodes: [], fromStationCode: "A", toStationCode: "A") == nil)
        #expect(network.directedIntervals(sectionCodes: ["unknown"], fromStationCode: "A", toStationCode: "B") == nil)
        #expect(network.directedIntervals(sectionCodes: ["surface@B:C"], fromStationCode: "A", toStationCode: "C") == nil)
        #expect(network.directedIntervals(sectionCodes: ["surface@A:B"], fromStationCode: "A", toStationCode: "C") == nil)
        #expect(network.directedIntervals(sectionCodes: ["surface@A:B"], fromStationCode: "B", toStationCode: "A") == nil)
        #expect(network.directedIntervals(sectionCodes: ["surface@A:B"], fromStationCode: "A", toStationCode: "B")?.first?.direction == 1)
    }

    @Test("Repeated occurrences freeze each direction and retain repeated surveyed distance")
    func repeatedDirectedIntervals() throws {
        let network = try fixture()
        let codes = ["surface@A:B", "surface@A:B", "surface@A:B"]
        let selected = try #require(network.directedIntervals(
            sectionCodes: codes, fromStationCode: "A", toStationCode: "B"))
        #expect(selected.map(\.code) == codes)
        #expect(selected.map(\.direction) == [1, -1, 1])
        let once = try #require(network.resolvedLines(sectionCodes: [codes[0]]))
        let repeated = try #require(network.resolvedLines(sectionCodes: selected.map(\.code)))
        #expect(abs(repeated[0].km - once[0].km * 3) < 1e-10)
    }
}
