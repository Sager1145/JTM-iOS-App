import Foundation
import Testing
@testable import RailCore

struct TsurumiPassengerArmsTests {
    private let identity = "jp-東日本旅客鉄道-鶴見線"

    @Test("Asano retains distinct surveyed passenger platform anchors on its two arms")
    func asanoPlatformAnchors() throws {
        let package = try PortFixtures.package(country: "jp")
        let trunk = try #require(package.lines.first { $0.id == identity })
        let umi = try #require(package.lines.first { $0.id == identity + "-2" })
        let mainPlatform = try #require(trunk.stations.first { $0.id == "004531" })
        let branchPlatform = try #require(umi.stations.first { $0.id == "004531" })
        let branchPoint = Coordinate(lon: 139.695745, lat: 35.497285)
        #expect(mainPlatform.coordinate == Coordinate(lon: 139.695675, lat: 35.497605))
        #expect(branchPlatform.coordinate == branchPoint)
        #expect(mainPlatform.coordinate != branchPlatform.coordinate)
        #expect(umi.stations.map(\.id) == ["004531", "004547", "004564"])
        let firstInterval = try #require(RailIntervalCodes.intervals(for: umi).first)
        #expect(firstInterval.fromStationCode == "004531")
        #expect(firstInterval.toStationCode == "004547")
        #expect(firstInterval.coordinates.first == branchPoint)
        let display = DisplayParts.parts(for: umi).flatMap { $0 }
        #expect(display.first == branchPoint)
    }

    @Test("Okawa passenger interval binds Anzen in both directions without a Musashi-Shiraishi stop",
          arguments: [false, true])
    func okawaPassengerBinding(reverse: Bool) throws {
        let package = try PortFixtures.package(country: "jp")
        let okawa = try #require(package.lines.first { $0.id == identity + "-3" })
        #expect(okawa.stations.map(\.id) == ["004522", "004540"])
        let interval = try #require(RailIntervalCodes.intervals(for: okawa).first)
        #expect(interval.fromStationCode == "004522")
        #expect(interval.toStationCode == "004540")
        #expect(interval.coordinates.first == Coordinate(lon: 139.701245, lat: 35.49984))
        #expect(interval.coordinates.contains(Coordinate(lon: 139.70555, lat: 35.50155)))
        #expect(!interval.coordinates.contains(Coordinate(lon: 139.70653, lat: 35.50193)))
        let lines = package.lines.filter { $0.id == identity || $0.id == okawa.id }
        let network = RouteNetwork(lines: lines.map { line in
            RouteNetwork.Line(lineId: line.id, name: line.name, operator: line.operator,
                isLoop: line.isLoop, alignmentDirection: line.alignmentDirection,
                parts: DisplayParts.parts(for: line), intervals: RailIntervalCodes.intervals(for: line),
                compactLine: line)
        })
        let resolver = StationIntervalResolver(network: network)
        let visits = reverse ? ["004540", "004522"] : ["004522", "004540"]
        let result = resolver.resolve(stationCodes: visits, requiredLineIDs: [okawa.id])
        guard case .resolved(let selection) = result else {
            Issue.record("The sourced Anzen–Okawa passenger arm did not resolve: \(result)")
            return
        }
        #expect(selection.stationCodes == visits)
        #expect(selection.intervals.count == 1)
        #expect(selection.lineIDs == [okawa.id])
        #expect(selection.intervals.first?.direction == (reverse ? -1 : 1))
        #expect(resolver.resolve(stationCodes: ["004517", "004540"], requiredLineIDs: [okawa.id]) == .unsupported)
    }
}
