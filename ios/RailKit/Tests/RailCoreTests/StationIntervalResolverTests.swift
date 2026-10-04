import Foundation
import Testing
@testable import RailCore

struct StationIntervalResolverTests {
    @Test func shortFamilyHintResolvesBothDirections() throws {
        let resolver = try fixture([row("main", ["A", "B", "C"], name: "1号線(Family)", norm: "Family")])
        let forward = try resolved(resolver.resolve(stationCodes: ["A", "C"], requiredLineNames: ["Family"]))
        let reverse = try resolved(resolver.resolve(stationCodes: ["C", "A"], requiredLineNames: ["Family"]))
        #expect(forward.sectionCodes == ["main@A:B", "main@B:C"])
        #expect(reverse.sectionCodes == Array(forward.sectionCodes.reversed()))
        #expect(forward.intervals.allSatisfy { $0.direction == 1 })
        #expect(reverse.intervals.allSatisfy { $0.direction == -1 })
        #expect(try JSONDecoder().decode(StationIntervalResolver.Selection.self,
            from: JSONEncoder().encode(forward)) == forward)
    }

    @Test func onlyExplicitKnownFamiliesAreAccepted() throws {
        let resolver = try fixture([row("main", ["A", "B", "C"])])
        #expect(resolver.resolve(stationCodes: ["A", "C"]) == .unsupported)
        #expect(resolver.resolve(stationCodes: ["A", "C"], requiredOperatorNames: ["Operator"]) == .unsupported)
        #expect(resolver.resolve(stationCodes: ["A", "C"], requiredLineIDs: ["unknown"]) == .unsupported)
        #expect(resolver.resolve(stationCodes: ["A", "C"], requiredLineIDs: ["main", "unknown"]) == .unsupported)
        #expect(resolver.resolve(stationCodes: ["A", "C"], requiredLineNames: ["Unknown"]) == .unsupported)
    }

    @Test func branchAmbiguityAndLaterViaAreConsideredAcrossTheWholeRun() throws {
        let resolver = try fixture([
            row("trunk", ["A", "B", "C", "D", "E"]),
            row("branch", ["B", "X", "D"]),
        ])
        #expect(resolver.candidateLineIDs(requiredLineIDs: ["trunk"]) == ["trunk", "branch"])
        #expect(resolver.resolve(stationCodes: ["A", "E"], requiredLineNames: ["Family"]) == .ambiguous)
        let pinned = try resolved(resolver.resolve(stationCodes: ["A", "E"], requiredLineIDs: ["trunk"]))
        #expect(pinned.lineIDs == ["trunk"])
        #expect(resolver.resolve(stationCodes: ["A", "X", "E"], requiredLineIDs: ["trunk"]) == .unsupported)
        let selected = try resolved(resolver.resolve(
            stationCodes: ["A", "B", "X", "E"], requiredLineNames: ["Family"]))
        #expect(selected.sectionCodes == ["trunk@A:B", "branch@B:X", "branch@D:X", "trunk@D:E"])
        #expect(selected.legIntervals.map(\.count) == [1, 1, 2])
        #expect(selected.lineIDs == ["trunk", "branch"])
    }

    @Test func repeatedVisitsRetainTheAuthoredReversal() throws {
        let resolver = try fixture([row("main", ["A", "B", "C"])])
        let selected = try resolved(resolver.resolve(stationCodes: ["A", "B", "A"], requiredLineIDs: ["main"]))
        #expect(selected.stationCodes == ["A", "B", "A"])
        #expect(selected.sectionCodes == ["main@A:B", "main@A:B"])
        #expect(selected.intervals.map(\.direction) == [1, -1])
        #expect(selected.legIntervals.map(\.count) == [1, 1])
    }

    @Test func intermediatePassThroughCannotReverseToAnUnrequestedStation() throws {
        let resolver = try fixture([
            row("main", ["A", "B"]), row("exit", ["A", "C"]),
        ])
        #expect(resolver.resolve(stationCodes: ["A", "B", "C"], requiredLineNames: ["Family"]) == .unsupported)
    }

    @Test func sourcedDirectionAndLoopSeamAreRespected() throws {
        let directed = try fixture([row("main", ["A", "B", "C"], traversal: "forward")])
        #expect(directed.resolve(stationCodes: ["C", "A"], requiredLineIDs: ["main"]) == .unsupported)
        let loop = try fixture([row("loop", ["A", "B", "C"], loop: true, traversal: "forward")])
        let selected = try resolved(loop.resolve(stationCodes: ["C", "B"], requiredLineIDs: ["loop"]))
        #expect(selected.sectionCodes == ["loop@A:C", "loop@A:B"])
        #expect(selected.intervals.map(\.direction) == [1, 1])
        let via = try resolved(loop.resolve(stationCodes: ["C", "A", "B"], requiredLineIDs: ["loop"]))
        #expect(via.legIntervals.map { $0.map(\.code) } == [["loop@A:C"], ["loop@A:B"]])
    }

    @Test func disconnectedOrNonExactSourceJoinsStayUnsupported() throws {
        let disconnected = try fixture([row("first", ["A", "B"]), row("second", ["C", "D"])])
        #expect(disconnected.resolve(stationCodes: ["A", "D"], requiredLineNames: ["Family"]) == .unsupported)
        let gap = try fixture([
            row("first", ["A", "B"]), row("second", ["B", "D"], sourceOffset: 0.00001),
        ])
        #expect(gap.resolve(stationCodes: ["A", "D"], requiredLineNames: ["Family"]) == .unsupported)
        let exactAndGap = try fixture([
            row("direct", ["A", "D"]), row("first", ["A", "B"]),
            row("second", ["B", "D"], sourceOffset: 0.00001),
        ])
        #expect(exactAndGap.resolve(stationCodes: ["A", "D"], requiredLineNames: ["Family"]) == .unsupported)
    }

    @Test func sameNamedOperatorCollisionsRemainAmbiguous() throws {
        let resolver = try fixture([
            row("one", ["A", "B", "C"], operatorName: "One"),
            row("two", ["A", "B", "C"], operatorName: "Two"),
        ])
        #expect(resolver.resolve(stationCodes: ["A", "C"], requiredLineNames: ["Family"]) == .ambiguous)
        let selected = try resolved(resolver.resolve(stationCodes: ["A", "C"],
            requiredLineNames: ["Family"], requiredOperatorNames: ["Two"]))
        #expect(selected.lineIDs == ["two"])
        let separate = try fixture([row("one", ["A", "B"], name: "First"), row("two", ["B", "C"], name: "Second")])
        #expect(separate.resolve(stationCodes: ["A", "C"], requiredLineNames: ["First", "Second"]) == .unsupported)
    }

    @Test func exactCoordinatesDoNotDeclarePairedAlignmentContinuation() throws {
        var paired = row("paired", ["B", "C"])
        paired["alignmentOf"] = "trunk"
        let unsafe = try fixture([row("trunk", ["A", "B"]), paired])
        #expect(unsafe.resolve(stationCodes: ["A", "C"], requiredLineNames: ["Family"]) == .unsupported)
        var directed = row("directed", ["B", "C"])
        directed["alignmentDirection"] = "up"
        let unsafeDirection = try fixture([row("trunk", ["A", "B"]), directed])
        #expect(unsafeDirection.resolve(stationCodes: ["A", "C"], requiredLineNames: ["Family"]) == .unsupported)
        var pairs = row("pairs", ["B", "C"])
        pairs["alignmentPairs"] = [["with": "trunk", "from": "B", "to": "C", "direction": "up"]]
        let unsafePairs = try fixture([row("trunk", ["A", "B"]), pairs])
        #expect(unsafePairs.resolve(stationCodes: ["A", "C"], requiredLineNames: ["Family"]) == .unsupported)
        var single = row("single", ["A", "B", "C"])
        single["alignmentOf"] = "another"
        let safe = try fixture([single])
        #expect(try resolved(safe.resolve(stationCodes: ["A", "C"], requiredLineIDs: ["single"])).sectionCodes ==
            ["single@A:B", "single@B:C"])
        let ordinary = try fixture([row("one", ["A", "B"]), row("two", ["B", "C"])])
        #expect(try resolved(ordinary.resolve(stationCodes: ["A", "C"], requiredLineNames: ["Family"])).lineIDs == ["one", "two"])
    }

    @Test func budgetAndCancellationCannotCertifyTheFirstFoundPath() throws {
        let resolver = try fixture([row("direct", ["A", "D"]), row("long", ["A", "B", "C", "D"])])
        #expect(resolver.resolve(stationCodes: ["A", "D"], requiredLineNames: ["Family"],
            maximumExaminedStates: 1) == .unsupported)
        #expect(resolver.resolve(stationCodes: ["A", "D"], requiredLineNames: ["Family"],
            maximumExaminedStates: 0) == .unsupported)
        #expect(resolver.resolve(stationCodes: ["A", "D"], requiredLineNames: ["Family"],
            isCancelled: { true }) == .unsupported)
    }

    @Test func sourceOccurrencesCannotTeleportBetweenRepeatedStationCodes() throws {
        let resolver = try fixture([row("repeat", ["A", "B", "C", "B", "D"], traversal: "forward")])
        #expect(resolver.resolve(stationCodes: ["A", "D"], requiredLineIDs: ["repeat"]) == .unsupported)
        let selected = try resolved(resolver.resolve(stationCodes: ["A", "B", "C", "B", "D"], requiredLineIDs: ["repeat"]))
        #expect(selected.sectionCodes == ["repeat@A:B", "repeat@B:C~1", "repeat@B:C~2", "repeat@B:D"])
    }

    @Test func adjacentOrShorterIntervalWinsWhenSeveralRowsRemain() throws {
        let resolver = try fixture([
            row("direct", ["A", "D"]),
            row("long", ["A", "B", "C", "D"]),
        ])
        let selected = try resolved(resolver.resolve(
            stationCodes: ["A", "D"], requiredLineNames: ["Family"]))
        #expect(selected.lineIDs == ["direct"])
        #expect(selected.intervals.count == 1)
        let tied = try fixture([
            row("one", ["A", "B"], name: "Loop"),
            row("two", ["A", "B"], name: "Loop"),
        ])
        #expect(tied.resolve(stationCodes: ["A", "B"], requiredLineNames: ["Loop"]) == .ambiguous)
    }

    @Test func oedoDaimonToAkabanebashiPrefersTheAdjacentLoopInterval() throws {
        let package = try PortFixtures.package(country: "jp")
        let selected = try resolved(index(package).resolve(
            stationCodes: ["003939", "003954"], requiredLineNames: ["12号線大江戸線"]))
        #expect(selected.intervals.count == 1)
        #expect(selected.lineIDs == ["jp-東京都-12号線大江戸線-2"])
    }

    @Test func tokyoUenoOmiyaUsesTheSourcedShinkansenIntervals() throws {
        let package = try PortFixtures.package(country: "jp")
        let resolver = index(package)
        let selected = try resolved(resolver.resolve(
            stationCodes: ["003766", "003505", "002914"], requiredLineNames: ["東北新幹線"]))
        #expect(selected.fromStationCode == "003766")
        #expect(selected.toStationCode == "002914")
        #expect(selected.legIntervals.count == 2)
        #expect(selected.legIntervals.allSatisfy { !$0.isEmpty })
        #expect(selected.sectionCodes.contains { $0.contains("003505:003766") })
    }

    private func resolved(_ result: StationIntervalResolver.Result) throws -> StationIntervalResolver.Selection {
        guard case .resolved(let selection) = result else {
            Issue.record("Expected unique physical intervals, got \(result)")
            throw CocoaError(.fileReadCorruptFile)
        }
        return selection
    }

    private func index(_ package: CompactPackage) -> StationIntervalResolver {
        StationIntervalResolver(network: RouteNetwork(lines: package.lines.map { line in
            RouteNetwork.Line(lineId: line.id, name: line.name, operator: line.operator,
                isLoop: line.isLoop, alignmentDirection: line.alignmentDirection,
                parts: [], intervals: RailIntervalCodes.intervals(for: line), compactLine: line)
        }))
    }

    private func fixture(_ rows: [[String: Any]]) throws -> StationIntervalResolver {
        let data = try JSONSerialization.data(withJSONObject: [
            "format": "compact-v1", "version": "test", "country": "jp", "lines": rows])
        return index(try JSONDecoder().decode(CompactPackage.self, from: data))
    }

    private func row(_ id: String, _ stations: [String], name: String = "Family", norm: String? = nil,
                     operatorName: String = "Operator", loop: Bool = false,
                     traversal: String? = nil, sourceOffset: Double = 0) -> [String: Any] {
        func point(_ code: String, offset: Double = 0) -> [Double] {
            [Double(code.utf8.first!) * 0.01 + offset, 35]
        }
        var row: [String: Any] = [
            "id": id, "name": name, "operator": operatorName, "rank": 3, "isLoop": loop,
            "stations": stations.map { [$0, $0, point($0, offset: sourceOffset)[0], point($0)[1]] as [Any] },
            "segments": (0..<(loop ? stations.count : stations.count - 1)).map { offset in
                [1, 0, [point(stations[offset], offset: sourceOffset),
                    point(stations[(offset + 1) % stations.count], offset: sourceOffset)]] as [Any]
            },
        ]
        if let norm { row["nameNorm"] = norm }
        if let traversal { row["permittedTraversal"] = traversal }
        return row
    }
}
