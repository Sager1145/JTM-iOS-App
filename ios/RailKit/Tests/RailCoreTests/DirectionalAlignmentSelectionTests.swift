import Foundation
import Testing
@testable import RailCore

struct DirectionalAlignmentSelectionTests {
    struct Case: Sendable {
        let base: String
        let pair: String
        let forward: Bool
    }

    static let cases: [Case] = [
        .init(base: "jp-九州旅客鉄道-日豊線", pair: "p1", forward: false),
        .init(base: "jp-九州旅客鉄道-鹿児島線", pair: "p1", forward: false),
        .init(base: "jp-北海道旅客鉄道-函館線", pair: "p1", forward: true),
        .init(base: "jp-東日本旅客鉄道-上越線", pair: "p1", forward: false),
        .init(base: "jp-東日本旅客鉄道-上越線", pair: "p2", forward: false),
        .init(base: "jp-東日本旅客鉄道-奥羽線", pair: "p1", forward: true),
        .init(base: "jp-東日本旅客鉄道-東北線", pair: "p2", forward: false),
        .init(base: "jp-東海旅客鉄道-東海道線-2", pair: "p1", forward: true),
        .init(base: "jp-西日本旅客鉄道-北陸線", pair: "p1", forward: false),
    ]

    private func network(_ lines: [CompactPackage.Line]) -> RouteNetwork {
        RouteNetwork(lines: lines.map { line in
            RouteNetwork.Line(
                lineId: line.id, name: line.name, operator: line.operator,
                isLoop: line.isLoop, alignmentDirection: line.alignmentDirection,
                parts: DisplayParts.parts(for: line), intervals: RailIntervalCodes.intervals(for: line),
                compactLine: line)
        })
    }

    @Test("Endpoint order selects directional tracks inside a longer journey", arguments: cases)
    func endpointOnlyFullSpan(item: Case) throws {
        let package = try PortFixtures.package(country: "jp")
        let base = try #require(package.lines.first { $0.id == item.base })
        let pairID = item.base + "-" + item.pair
        let pair = try #require(package.lines.first { $0.id == pairID })
        guard base.alignmentPairs.first(where: { $0.with == pairID })?.direction != "unassigned" else { return }
        let start = try #require(base.stations.firstIndex { $0.id == pair.stations.first?.id })
        let end = try #require(base.stations.firstIndex { $0.id == pair.stations.last?.id })
        let first = base.stations[max(0, start - 1)]
        let last = base.stations[min(base.stations.count - 1, end + 1)]
        let family = package.lines.filter { $0.id == item.base || $0.alignmentOf == item.base }
        for forward in [true, false] {
            let from = forward ? first : last
            let to = forward ? last : first
            let result = try #require(network(family).canonicalizeRouteFeature(RouteFeature(
                geometry: .lineString([from.coordinate, to.coordinate]),
                hints: .init(requiredLineNames: [base.name], requiredOperatorNames: [base.operator],
                             fromStationCode: from.id, toStationCode: to.id))))
            #expect(result.displayLineIds.contains(pairID) == (forward == item.forward))
            #expect(!result.matchedSectionCodes.isEmpty)
            let fromPlatforms = family.flatMap(\.stations).filter { $0.id == from.id }.map(\.coordinate)
            let toPlatforms = family.flatMap(\.stations).filter { $0.id == to.id }.map(\.coordinate)
            #expect(result.geometry.lines.first?.first.map(fromPlatforms.contains) == true)
            #expect(result.geometry.lines.last?.last.map(toPlatforms.contains) == true)
        }
    }

    @Test("All nine sourced pairs follow official direction independently of stored station order",
          arguments: cases)
    func packageChoices(item: Case) throws {
        let package = try PortFixtures.package(country: "jp")
        let pairID = item.base + "-" + item.pair
        let pair = try #require(package.lines.first { $0.id == pairID })
        let first = try #require(pair.stations.first)
        let last = try #require(pair.stations.last)
        for forward in [true, false] {
            let choices = RailwayRouteChoices.choices(
                package: package, originCode: forward ? first.id : last.id,
                destinationCode: forward ? last.id : first.id)
            #expect(choices.contains { $0.lineIDs.contains(pairID) } == (forward == item.forward),
                    "\(pairID): stored forward=\(forward), permitted forward=\(item.forward)")
        }
    }

    @Test("Legacy geometry selects the correct paired track from origin and destination station codes",
          arguments: cases)
    func automaticDirection(item: Case) throws {
        let package = try PortFixtures.package(country: "jp")
        let base = try #require(package.lines.first { $0.id == item.base })
        let pairID = item.base + "-" + item.pair
        let pair = try #require(package.lines.first { $0.id == pairID })
        let first = try #require(pair.stations.first)
        let last = try #require(pair.stations.last)
        let start = try #require(base.stations.firstIndex { $0.id == first.id })
        let end = try #require(base.stations.firstIndex { $0.id == last.id })
        // Nanae and Tarui retain an ordinary bidirectional trunk as well as
        // their one-way bypass. Direction alone cannot choose between two
        // permitted paths; use the selected source shape for those bypasses.
        let mainWindow = base.alignmentPairs.first { $0.with == pairID }
        let rows = mainWindow?.direction == "unassigned"
            ? RailIntervalCodes.intervals(for: pair)[...]
            : RailIntervalCodes.intervals(for: base)[start..<end]
        var trunk: [Coordinate] = []
        for row in rows {
            trunk += trunk.last == row.coordinates.first ? row.coordinates.dropFirst() : row.coordinates[...]
        }
        let forward = item.forward
        let family = package.lines.filter {
            $0.id == item.base || $0.alignmentOf == item.base
        }
        let route = try #require(network(family).canonicalizeRouteFeature(RouteFeature(
            geometry: .lineString(forward ? trunk : Array(trunk.reversed())),
            hints: .init(requiredLineNames: [base.name], requiredOperatorNames: [base.operator],
                         fromStationCode: forward ? first.id : last.id,
                         toStationCode: forward ? last.id : first.id))))
        #expect(route.displayLineIds.contains(pairID), "\(pairID) must follow permitted direction and source shape")
        #expect(route.geometry.lines.first?.first == (forward ? first.coordinate : last.coordinate))
        #expect(route.geometry.lines.last?.last == (forward ? last.coordinate : first.coordinate))
    }

    @Test("An explicitly selected paired interval cannot be traversed against its sourced direction",
          arguments: cases)
    func invalidExplicitDirection(item: Case) throws {
        let pairID = item.base + "-" + item.pair
        let pair = try #require(try PortFixtures.package(country: "jp").lines.first { $0.id == pairID })
        let first = try #require(pair.stations.first)
        let last = try #require(pair.stations.last)
        let intervals = RailIntervalCodes.intervals(for: pair)
        let invalidForward = !item.forward
        let hints = RouteHints(
            requiredLineIDs: [pairID],
            sectionCodes: invalidForward ? intervals.map(\.code) : intervals.reversed().map(\.code),
            fromStationCode: invalidForward ? first.id : last.id,
            toStationCode: invalidForward ? last.id : first.id)
        let rejected = network([pair]).canonicalizeRouteFeature(RouteFeature(geometry: nil, hints: hints)) == nil
        #expect(rejected, "\(pairID) must reject traversal against the sourced direction")
    }

    @Test("An uncoded paired shape used in the forbidden direction corrects onto the main track",
          arguments: cases)
    func forbiddenLegacyPair(item: Case) throws {
        let package = try PortFixtures.package(country: "jp")
        let pairID = item.base + "-" + item.pair
        let pair = try #require(package.lines.first { $0.id == pairID })
        let first = try #require(pair.stations.first)
        let last = try #require(pair.stations.last)
        var coordinates: [Coordinate] = []
        for interval in RailIntervalCodes.intervals(for: pair) {
            coordinates += coordinates.last == interval.coordinates.first
                ? interval.coordinates.dropFirst() : interval.coordinates[...]
        }
        let forward = !item.forward
        let family = package.lines.filter { $0.id == item.base || $0.alignmentOf == item.base }
        let result = try #require(network(family).canonicalizeRouteFeature(RouteFeature(
            geometry: .lineString(forward ? coordinates : Array(coordinates.reversed())),
            hints: .init(requiredLineNames: [pair.name], requiredOperatorNames: [pair.operator],
                         fromStationCode: forward ? first.id : last.id,
                         toStationCode: forward ? last.id : first.id))))
        #expect(!result.displayLineIds.contains(pairID))
        #expect(result.displayLineIds.contains(item.base))
        #expect(result.geometry.lines.first?.first == (forward ? first.coordinate : last.coordinate))
        #expect(result.geometry.lines.last?.last == (forward ? last.coordinate : first.coordinate))
    }

    @Test("Unknown physical directions remain bidirectional unless traversal is explicitly sourced")
    func unassignedDirections() throws {
        let package = try PortFixtures.package(country: "jp")
        let pairs = package.lines.filter { $0.alignmentOf != nil && $0.alignmentDirection == "unassigned" }
        #expect(pairs.count == 7)
        let northboundOsakiID = "jp-東日本旅客鉄道-大崎支線-p1"
        for pair in pairs {
            // Osaki's reviewed northbound track has a sourced reverse traversal,
            // independently of the unassigned physical up/down classification.
            // The original six pairs have no traversal restriction.
            #expect(pair.permittedTraversal == (pair.id == northboundOsakiID ? "reverse" : nil))
            let first = try #require(pair.stations.first)
            let last = try #require(pair.stations.last)
            for (from, to, forward) in [(first, last, true), (last, first, false)] {
                let expected = pair.id != northboundOsakiID || !forward
                #expect(RailwayRouteChoices.choices(
                    package: package, originCode: from.id, destinationCode: to.id)
                    .contains { $0.lineIDs == [pair.id] } == expected,
                    "\(pair.id): stored forward=\(forward), expected available=\(expected)")
            }
        }
    }

    @Test("Port Liner loop branch follows the operator's single permitted traversal")
    func portLiner() throws {
        let package = try PortFixtures.package(country: "jp")
        let branchID = "jp-神戸新交通-ポートアイランド線-2"
        let forward = RailwayRouteChoices.choices(
            package: package, originCode: "007340", destinationCode: "007276")
        #expect(forward.contains { $0.lineIDs == [branchID] })
        let reverse = RailwayRouteChoices.choices(
            package: package, originCode: "007276", destinationCode: "007340")
        #expect(!reverse.contains { $0.lineIDs.contains(branchID) })
        #expect(reverse.contains { $0.stations.map(\.name) == ["中公園", "みなとじま", "市民広場"] })
    }
}
