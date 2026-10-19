import Foundation
import Testing

@testable import RailCore

struct HakoneSourceReversalTests {
    private struct SourceEvidence: Decodable {
        let sourceInterval: [[Double]]
    }

    @Test("current cached passenger rides use repaired display curves in both directions")
    func cachedPassengerDisplay() throws {
        let root = try PortFixtures.repositoryRoot()
        let loaded = try DisplayParts.LoadedPackage.load(
            contentsOf: root.appending(path: "app/public/rail/jp-2025.json"))
        let id = "jp-小田急箱根-鉄道線"
        let line = try #require(loaded.package.lines.first { $0.id == id })
        let topology = try #require(loaded.topologyByLineID[id])
        let intervals = RailIntervalCodes.intervals(for: line)
        let network = RouteNetwork(lines: [.init(lineId: id, name: line.name, operator: line.operator,
            isLoop: line.isLoop, alignmentDirection: line.alignmentDirection,
            parts: DisplayParts.parts(for: line, topology: topology), intervals: intervals, compactLine: line)])
        for index in 4...9 {
            let interval = intervals[index]
            for reverse in [false, true] {
                let source = reverse ? Array(interval.coordinates.reversed()) : interval.coordinates
                let hints = RouteHints(requiredLineIDs: [id], sectionCodes: [interval.code],
                    fromStationCode: reverse ? interval.toStationCode : interval.fromStationCode,
                    toStationCode: reverse ? interval.fromStationCode : interval.toStationCode)
                var cache = RouteProjectionCache()
                let drawn = network.precomputedDisplayParts(source: source, hints: hints, cache: &cache)
                try #require(!drawn.isEmpty)
                #expect(drawn.allSatisfy { $0.displayLineIDs == [id] })
                #expect(drawn.allSatisfy { $0.sourceCoordinates.count >= 2 })
                let sourceMetres = RouteSolver.pathLength(for: source)
                let partitionMetres = drawn.reduce(0.0) { $0 + RouteSolver.pathLength(for: $1.sourceCoordinates) }
                #expect(abs(sourceMetres - partitionMetres) < 0.000001)
                #expect(drawn.first?.coordinates.first == line.displayCoordinate(for: line.stations[reverse ? index + 1 : index]))
                #expect(drawn.last?.coordinates.last == line.displayCoordinate(for: line.stations[reverse ? index : index + 1]))
                if index == 5 || index == 6 {
                    let tip = index == 5 ? Coordinate(lon: 139.0881895, lat: 35.2322218)
                        : Coordinate(lon: 139.0757745, lat: 35.2347961)
                    #expect(drawn.flatMap(\.coordinates).filter { $0 == tip }.count == 1)
                }
                #expect(drawn.first?.sourceCoordinates.first == source.first)
                #expect(drawn.last?.sourceCoordinates.last == source.last)
            }
        }
    }

    @Test("loaded Hakone metadata preserves its surveyed reversal without changing the passenger source")
    func loadedPassengerReversal() throws {
        let root = try PortFixtures.repositoryRoot()
        let loaded = try DisplayParts.LoadedPackage.load(
            contentsOf: root.appending(path: "app/public/rail/jp-2025.json"))
        let id = "jp-小田急箱根-鉄道線"
        let line = try #require(loaded.package.lines.first { $0.id == id })
        let topology = try #require(loaded.topologyByLineID[id])
        let tip = Coordinate(lon: 139.07524, lat: 35.23596)
        let surveyedTips = [Coordinate(lon: 139.0881895, lat: 35.2322218),
                            Coordinate(lon: 139.0757745, lat: 35.2347961)]
        #expect(topology.reversalTails == [tip] + surveyedTips)

        // The evidence pins the complete original raw-surveyed outgoing
        // passenger chain, independently of the added display metadata.
        let evidence = try JSONDecoder().decode(SourceEvidence.self, from: Data(contentsOf:
            root.appending(path: "app/scripts/railway/hakone-source-reversal-evidence.json")))
        let original = evidence.sourceInterval.map { Coordinate(lon: $0[0], lat: $0[1]) }
        let source = CompactPackage.decodeIntervals(line)[6]
        #expect(source == original)
        try #require(source.count == 93)
        #expect(source[23] == tip)
        #expect(source.first == line.stations[6].coordinate)
        #expect(source.last == line.stations[7].coordinate)

        let parts = DisplayParts.parts(for: line, topology: topology)
        try #require(parts.count == 7)
        for stem in line.displayReversalBranches {
            #expect(parts.filter { $0 == stem }.count == 1)
            #expect(parts.filter { $0.first == stem.first || $0.last == stem.first }.count == 3)
            #expect(parts.flatMap { $0 }.filter { $0 == stem.last }.count == 1)
        }
        for surveyed in surveyedTips {
            #expect(parts.flatMap { $0 }.contains(surveyed))
        }
        // The legacy physical tip stays in the canonical graph, while the
        // display corridor reaches the node-connected terminal stems.
        #expect(!parts.flatMap { $0 }.contains(tip))
        let display = CompactPackage.decodeDisplayIntervals(line)
        for (interval, surveyed) in zip([5, 6], surveyedTips) {
            let index = try #require(display[interval].firstIndex(of: surveyed))
            try #require(index > 0 && index + 1 < display[interval].count)
            #expect(display[interval][index - 1] == display[interval][index + 1])
        }
    }
}
