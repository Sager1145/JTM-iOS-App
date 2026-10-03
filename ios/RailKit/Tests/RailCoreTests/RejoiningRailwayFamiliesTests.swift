import Foundation
import Testing
@testable import RailCore

struct RejoiningRailwayFamiliesTests {
    struct Case: Sendable {
        let trunk: String
        let branch: String
        let origin: String
        let destination: String
        let rows: [String]
        let bidirectional: Bool
    }

    static let cases: [Case] = {
        let hakodate = "jp-北海道旅客鉄道-函館線"
        let nagasaki = "jp-九州旅客鉄道-長崎線"
        let chuo = "jp-東日本旅客鉄道-中央線"
        let tohoku = "jp-東日本旅客鉄道-東北線"
        let meijo = "jp-名古屋市-2号線名城線"
        let ring = "jp-名古屋市-4号線名城線"
        let port = "jp-神戸新交通-ポートアイランド線"
        return [
            .init(trunk: hakodate, branch: hakodate + "-2", origin: "000429", destination: "000416",
                  rows: [hakodate, hakodate + "-2", hakodate], bidirectional: true),
            .init(trunk: nagasaki, branch: nagasaki + "-2", origin: "009708", destination: "009822",
                  rows: [nagasaki, nagasaki + "-2", nagasaki], bidirectional: true),
            .init(trunk: chuo, branch: chuo + "-2", origin: "002616", destination: "002676",
                  rows: [chuo + "-2", chuo], bidirectional: true),
            .init(trunk: tohoku, branch: tohoku + "-5", origin: "003155", destination: "002859",
                  rows: [tohoku + "-5", tohoku], bidirectional: true),
            .init(trunk: tohoku + "-2", branch: tohoku + "-4", origin: "003155", destination: "003460",
                  rows: [tohoku + "-2", tohoku + "-4", tohoku + "-2"], bidirectional: true),
            .init(trunk: meijo, branch: ring, origin: "005525", destination: "005366",
                  rows: [meijo, ring, meijo], bidirectional: true),
            .init(trunk: port, branch: port + "-2", origin: "007340", destination: "007203",
                  rows: [port + "-2", port], bidirectional: false),
        ]
    }()

    private func network(package: CompactPackage, item: Case) -> RouteNetwork {
        RouteNetwork(lines: package.lines.filter { $0.id == item.trunk || $0.id == item.branch }.map { line in
            RouteNetwork.Line(
                lineId: line.id, name: line.name, operator: line.operator,
                isLoop: line.isLoop, alignmentDirection: line.alignmentDirection,
                parts: DisplayParts.parts(for: line), intervals: RailIntervalCodes.intervals(for: line),
                compactLine: line)
        })
    }

    @Test("Seven real rejoining families keep complete physical choices and valid travel orders",
          arguments: cases)
    func physicalChoices(item: Case) throws {
        let package = try PortFixtures.package(country: "jp")
        let choice = try #require(RailwayRouteChoices.choices(
            package: package, originCode: item.origin, destinationCode: item.destination)
            .first { $0.lineIDs == item.rows })
        #expect(choice.lineIDs.count > 1)
        #expect(choice.stations.first?.code == item.origin)
        #expect(choice.stations.last?.code == item.destination)
        #expect(Set(choice.stations.map(\.code)).count == choice.stations.count)
        #expect(choice.routeSections.count == choice.stations.count - 1)
        let reverseChoices = RailwayRouteChoices.choices(
            package: package, originCode: item.destination, destinationCode: item.origin)
        if item.bidirectional {
            let reverse = try #require(reverseChoices.first {
                $0.sectionCodes == Array(choice.sectionCodes.reversed())
            })
            #expect(reverse.lineIDs == Array(choice.lineIDs.reversed()))
            #expect(reverse.stations == Array(choice.stations.reversed()))
        } else {
            #expect(reverseChoices.allSatisfy { !$0.lineIDs.contains(item.branch) })
            #expect(!reverseChoices.isEmpty)
        }
    }

    @Test("Legacy full-span source geometry resolves the same selected multi-row path in both orders",
          arguments: cases)
    func automaticPhysicalMatch(item: Case) throws {
        let package = try PortFixtures.package(country: "jp")
        let choice = try #require(RailwayRouteChoices.choices(
            package: package, originCode: item.origin, destinationCode: item.destination)
            .first { $0.lineIDs == item.rows })
        let network = network(package: package, item: item)
        let trunk = try #require(package.lines.first { $0.id == item.trunk })
        for forward in item.bidirectional ? [true, false] : [true] {
            let from = forward ? item.origin : item.destination
            let to = forward ? item.destination : item.origin
            let codes = forward ? choice.sectionCodes : Array(choice.sectionCodes.reversed())
            let codedHints = RouteHints(
                requiredLineIDs: choice.lineIDs, sectionCodes: codes,
                fromStationCode: from, toStationCode: to)
            let source = try #require(network.sourceGeometry(for: codedHints))
            let coded = try #require(network.canonicalizeRouteFeature(
                RouteFeature(geometry: nil, hints: codedHints)))
            // The solver gives one continuous hop, including a connector
            // between the two Omiya platform anchors sharing its station code.
            // Source/canonical paths retain that gap as separate strokes.
            let automatic = try #require(network.canonicalizeRouteFeature(RouteFeature(
                geometry: .lineString(source.lines.flatMap { $0 }),
                hints: .init(requiredLineNames: [trunk.name], requiredOperatorNames: [trunk.operator],
                             fromStationCode: from, toStationCode: to))))
            #expect(Set(automatic.displayLineIds) == Set([item.trunk, item.branch]))
            #expect(automatic.displayLineIds == coded.displayLineIds)
            let identicalGeometry = automatic.geometry == coded.geometry
            #expect(identicalGeometry, "\(item.branch): forward=\(forward), source path must determine every interval")
            let origin = try #require(choice.stations.first { $0.code == from })
            let destination = try #require(choice.stations.first { $0.code == to })
            // One code can identify separate conventional/Shinkansen platform
            // coordinates at Nagasaki. Use this selected physical row's anchor.
            let fromCoordinate = try #require(trunk.stations.first { $0.id == origin.code })
                .coordinate
            let toCoordinate = try #require(trunk.stations.first { $0.id == destination.code })
                .coordinate
            #expect(source.lines.first?.first == fromCoordinate)
            #expect(source.lines.last?.last == toCoordinate)
            #expect(automatic.geometry.lines.first?.first == fromCoordinate)
            #expect(automatic.geometry.lines.last?.last == toCoordinate)
        }
    }
}
