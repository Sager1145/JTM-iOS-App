import Foundation
import Testing
@testable import RailCore

struct ResolvedRouteExportTests {
    private func network() throws -> RouteNetwork {
        let data = Data(#"{"format":"compact-v1","version":"2025","country":"jp","lines":[{"id":"surface","name":"Surface","rank":1,"stations":[["A","A",139,35],["B","B",139.01,35]],"segments":[[1,0,[[139,35],[139.01,35]]]]}]}"#.utf8)
        let package = try JSONDecoder().decode(CompactPackage.self, from: data)
        return RouteNetwork(lines: package.lines.map { line in
            RouteNetwork.Line(lineId: line.id, name: line.name, operator: line.operator,
                isLoop: line.isLoop, alignmentDirection: line.alignmentDirection,
                parts: CompactPackage.decodeDisplayIntervals(line),
                intervals: RailIntervalCodes.intervals(for: line), compactLine: line)
        })
    }
    private func train(to: String = "B") -> Train {
        Train(id: "ride", number: "1", origin: "A", destination: to,
              routeSections: [.init(from: "A", to: to, fromN02StationCode: "A", toN02StationCode: to)], stops: [])
    }
    private func selection(_ directions: [Int] = [1], to: String = "B") -> ResolvedRouteExport.Selection {
        .init(sectionIndex: 0, fromStationCode: "A", toStationCode: to,
              intervals: directions.map { .init(lineID: "surface", code: "surface@A:B", direction: $0) })
    }
    @Test func materializesConfirmedIntervals() throws {
        let result = ResolvedRouteExport.applying(to: train(), selections: [selection()],
                                                 network: try network(), isComplete: true)
        #expect(result.routeSections?.first?.sectionCodes == ["surface@A:B"])
        #expect(result.routeSections?.first?.lineIDs == ["surface"])
    }
    @Test func preservesAuthoredChoice() throws {
        var original = train()
        original.routeSections?[0].sectionCodes = ["authored@A:B"]
        original.routeSections?[0].lineIDs = ["authored"]
        #expect(ResolvedRouteExport.applying(to: original, selections: [selection()],
            network: try network(), isComplete: true) == original)
    }
    @Test func rejectsPartialAndIncorrectDirection() throws {
        let original = train()
        let network = try network()
        #expect(ResolvedRouteExport.applying(to: original, selections: [selection()], network: network, isComplete: false) == original)
        #expect(ResolvedRouteExport.applying(to: original, selections: [selection([-1])], network: network, isComplete: true) == original)
        #expect(ResolvedRouteExport.applying(to: original, selections: [], network: network, isComplete: true) == original)
    }
    @Test func retainsRepeatedPassages() throws {
        let result = ResolvedRouteExport.applying(to: train(), selections: [selection([1, -1, 1])],
                                                 network: try network(), isComplete: true)
        #expect(result.routeSections?.first?.sectionCodes == Array(repeating: "surface@A:B", count: 3))
        #expect(result.routeSections?.first?.lineIDs == ["surface"])
    }
    @Test func rejectsUnconfirmedConflictingAndUnmappedSelections() throws {
        let network = try network()
        var pending = train()
        pending.routeConfirmation = .pending
        #expect(ResolvedRouteExport.applying(to: pending, selections: [selection()], network: network, isComplete: true) == pending)
        var constrained = train()
        constrained.routeSections?[0].lineIDs = ["another-line"]
        #expect(ResolvedRouteExport.applying(to: constrained, selections: [selection()], network: network, isComplete: true) == constrained)
        let unmapped = ResolvedRouteExport.Selection(sectionIndex: 1, fromStationCode: "A", toStationCode: "B", intervals: selection().intervals)
        let original = train()
        #expect(ResolvedRouteExport.applying(to: original, selections: [unmapped], network: network, isComplete: true) == original)
        let wrongEndpoint = ResolvedRouteExport.Selection(sectionIndex: 0, fromStationCode: "B", toStationCode: "A", intervals: selection([-1]).intervals)
        #expect(ResolvedRouteExport.applying(to: original, selections: [wrongEndpoint], network: network, isComplete: true) == original)
    }
}
