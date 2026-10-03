import Foundation
import Testing
@testable import RailCore

struct RailIntervalCodeTests {
    @Test func physicalLineChangeKeepsBothPlatformPathsInBothDirections() throws {
        let package = try PortFixtures.package(country: "jp")
        let yamate = try #require(package.lines.first { $0.id == "jp-東日本旅客鉄道-山手線" })
        let sobu = try #require(package.lines.first { $0.id == "jp-東日本旅客鉄道-総武線-3" })
        let shinjukuIndex = try #require(yamate.stations.firstIndex { $0.name == "新宿" })
        let yamateIntervals = RailIntervalCodes.intervals(for: yamate)
        let sobuIntervals = RailIntervalCodes.intervals(for: sobu)
        let codes = Array(yamateIntervals.prefix(shinjukuIndex).reversed().map(\.code))
            + Array(sobuIntervals.prefix(2).reversed().map(\.code))
        let network = RouteNetwork(lines: [yamate, sobu].map { line in
            RouteNetwork.Line(lineId: line.id, name: line.name, operator: line.operator,
                              isLoop: line.isLoop, alignmentDirection: nil,
                              parts: DisplayParts.parts(for: line), intervals: RailIntervalCodes.intervals(for: line))
        })
        var forwardSource: RouteGeometry?
        var forwardDisplay: RouteGeometry?
        for reverse in [false, true] {
            let hints = RouteHints(requiredLineIDs: [yamate.id, sobu.id],
                                   sectionCodes: reverse ? Array(codes.reversed()) : codes,
                                   fromStationCode: reverse ? "003766" : yamate.stations[shinjukuIndex].id,
                                   toStationCode: reverse ? yamate.stations[shinjukuIndex].id : "003766")
            let source = try #require(network.sourceGeometry(for: hints))
            let display = try #require(network.canonicalizeRouteFeature(RouteFeature(geometry: nil, hints: hints)))
            #expect(source.lines.count == 2)
            #expect(display.geometry.lines.count == 2)
            #expect(Set(display.displayLineIds) == Set([yamate.id, sobu.id]))
            if reverse {
                #expect(source.lines == forwardSource?.lines.reversed().map { Array($0.reversed()) })
                #expect(display.geometry.lines == forwardDisplay?.lines.reversed().map { Array($0.reversed()) })
            } else {
                forwardSource = source
                forwardDisplay = display.geometry
            }
        }
        #expect(network.sourceGeometry(for: RouteHints(sectionCodes: ["missing"], fromStationCode: "003766")) == nil)
    }

    @Test func nexSelectsTunnelByIdentityInBothDirections() throws {
        let package = try PortFixtures.package(country: "jp")
        let compact = try #require(package.lines.first { $0.id == "jp-東日本旅客鉄道-総武線-3" })
        let intervals = RailIntervalCodes.intervals(for: compact)
        let network = RouteNetwork(lines: [RouteNetwork.Line(
            lineId: compact.id, name: compact.name, operator: compact.operator,
            isLoop: false, alignmentDirection: nil,
            parts: DisplayParts.parts(for: compact), intervals: intervals, compactLine: compact)])
        let codes = Array(intervals.prefix(2).map(\.code))
        #expect(codes == ["jp-東日本旅客鉄道-総武線-3@003766:003872",
                         "jp-東日本旅客鉄道-総武線-3@003872:004095"])
        let tokyo = compact.stations[0].coordinate
        let shinagawa = compact.stations[2].coordinate
        let forward = try #require(network.canonicalizeRouteFeature(RouteFeature(
            geometry: .lineString([tokyo, shinagawa]),
            hints: RouteHints(requiredLineIDs: [compact.id], sectionCodes: codes,
                              fromStationCode: "003766", toStationCode: "004095"))))
        let reverse = try #require(network.canonicalizeRouteFeature(RouteFeature(
            geometry: .lineString([shinagawa, tokyo]),
            hints: RouteHints(requiredLineIDs: [compact.id], sectionCodes: codes.reversed(),
                              fromStationCode: "004095", toStationCode: "003766"))))
        #expect(forward.geometry.lines[0].first == tokyo)
        #expect(forward.geometry.lines[0].last == compact.displayCoordinate(for: compact.stations[2]))
        #expect(reverse.geometry.lines[0] == forward.geometry.lines[0].reversed())
        let invalid = network.canonicalizeRouteFeature(RouteFeature(
            geometry: .lineString([tokyo, shinagawa]),
            hints: RouteHints(sectionCodes: [codes[0], "unknown"], fromStationCode: "003766")))
        #expect(invalid == nil)
    }

    @Test func allPackageIntervalsHaveUniqueCodes() throws {
        let package = try PortFixtures.package(country: "jp")
        let codes = package.lines.flatMap { RailIntervalCodes.intervals(for: $0).map(\.code) }
        #expect(codes.count == package.lines.reduce(0) { $0 + $1.segments.count })
        #expect(Set(codes).count == codes.count)
    }

    @Test func timetableNexCarriesPhysicalIntervalsThroughProjection() throws {
        let database = try #require(TrainTimetableDatabase.bundled())
        let query = try database.trip(id: "jr-east.narita-express.1.2001m.exact-2026-09-30", on: "2026-09-30")
        let trip = try #require(query)
        let draft = Train(id: "nex-projection", date: nil, number: "", origin: "", destination: "", stops: [])
        let projected = try #require(trip.publishedStopsDraft(to: draft))
        let tunnel = try #require(projected.routeSections?.first {
            $0.fromN02StationCode == "004095" && $0.toN02StationCode == "003766"
        })
        #expect(tunnel.lineIDs == ["jp-東日本旅客鉄道-総武線-3"])
        #expect(tunnel.sectionCodes == ["jp-東日本旅客鉄道-総武線-3@003872:004095",
                                       "jp-東日本旅客鉄道-総武線-3@003766:003872"])
        let decoded = try JSONDecoder().decode(Train.self, from: JSONEncoder().encode(projected))
        #expect(decoded.routeSections == projected.routeSections)
    }
}
