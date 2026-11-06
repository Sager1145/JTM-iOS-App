import Foundation
import Testing
@testable import RailCore

/// A passing loop at a paired-track seam, on synthetic rail (metres east and
/// north of a fixed origin). The main track runs west to east. A loop track
/// leaves it at `switchWest`, rejoins at `switchEast`, and the previous part
/// ends 20 m north of the main track on the loop while the next part starts on
/// the main track, so the plain bridge (through a switch and back) is too long.
@Suite(.serialized)
struct PairedSeamSyntheticTests {
    static let parent = "test-parent"
    static let paired = "test-paired"
    private static let origin = Coordinate(lon: 139, lat: 35)

    static func at(_ east: Double, _ north: Double = 0) -> Coordinate {
        Coordinate(lon: origin.lon + east / (111_320 * cos(origin.lat * .pi / 180)),
                   lat: origin.lat + north / 110_574)
    }

    static func rail(_ points: [Coordinate]) -> RouteGraph.SectionFeature {
        .init(properties: .init(lineName: "Rail", operator: "Operator", institutionTypeCode: "1"),
              lines: [points])
    }

    static func key(_ coordinate: Coordinate) -> String {
        RouteGraph.physicalNodeKey(coordinate,
            identity: .init(operatorName: "Operator", lineName: "Rail", railwayClassCode: ""))
    }

    static func catalog(status: PairedTracks.Status = .confirmed) -> PairedTracks.Catalog {
        .init(pairs: [.init(
            pairedLineID: paired, parentLineID: parent, line: "Rail", operator: "Operator",
            from: .init(name: "A", code: "1"), to: .init(name: "B", code: "2"),
            upTrack: nil, downTrack: nil, sharedTrack: nil, pairStatus: status, directionStatus: .unknown,
            sources: [], note: nil)])
    }

    /// `gap` is where the next part starts on the main track east of the west
    /// switch; `rejoin` is how far past it the loop rejoins the main track.
    struct Layout {
        let graph: RouteGraph.Graph
        let previous: [Coordinate]
        let next: [Coordinate]
    }

    static func loop(gap: Double = 300, rejoin: Double = 400) -> Layout {
        let west = at(-300), switchWest = at(0), start = at(gap), switchEast = at(gap + rejoin)
        let east = at(gap + rejoin + 300)
        let loopA = at(150, 20), loopEnd = at(gap, 20), loopB = at(gap + rejoin / 2, 20)
        let graph = RouteGraph.build(from: [
            rail([west, switchWest]), rail([switchWest, start]), rail([start, switchEast]),
            rail([switchEast, east]), rail([switchWest, loopA]), rail([loopA, loopEnd]),
            rail([loopEnd, loopB]), rail([loopB, switchEast]),
        ])
        return Layout(graph: graph, previous: [west, switchWest, loopA, loopEnd],
                      next: [start, switchEast, east])
    }

    static func certify(
        _ lines: [[Coordinate]], graph: RouteGraph.Graph,
        seams: [RouteNetwork.SourceSeam] = [.init(stationCode: "2", fromLineID: parent, toLineID: paired)],
        catalog: PairedTracks.Catalog
    ) -> [String]? {
        RouteSolver.verifiedSourcePath(
            lines, graph: graph, context: .init(rideDate: nil), section: .init(),
            selectedLineIDs: lines.indices.map { _ in [parent, paired] }, seams: seams, pairedTracks: catalog)
    }

    @Test("Without a pair the plain bridge is too long and the seam fails")
    func plainBridgeFails() {
        let layout = Self.loop()
        #expect(Self.certify([layout.previous, layout.next], graph: layout.graph, catalog: .empty) == nil)
    }

    @Test("A passing-loop seam certifies by running on through the loop to the rejoin, never reversing")
    func passingLoopCertifies() {
        let layout = Self.loop()
        let keys = Self.certify([layout.previous, layout.next], graph: layout.graph, catalog: Self.catalog())
        let expected = [Self.at(-300), Self.at(0), Self.at(150, 20), Self.at(300, 20), Self.at(500, 20),
                        Self.at(700), Self.at(1000)].map(Self.key)
        #expect(keys == expected)
    }

    @Test("The same seam certifies in the opposite direction through the east switch")
    func passingLoopCertifiesBackwards() {
        let layout = Self.loop()
        let keys = Self.certify(
            [layout.next.reversed(), layout.previous.reversed()], graph: layout.graph,
            seams: [.init(stationCode: "1", fromLineID: Self.paired, toLineID: Self.parent)],
            catalog: Self.catalog())
        #expect(keys != nil)
        #expect(keys?.first == Self.key(Self.at(1000)))
        #expect(keys?.last == Self.key(Self.at(-300)))
    }

    @Test("A trailing branch that needs a reversal returns nil")
    func trailingBranchNeedsReversal() {
        let layout = Self.loop()
        // The next part heads back west over the switch the previous part left by.
        let next = [Self.at(300), Self.at(0), Self.at(-300)]
        #expect(Self.certify([layout.previous, next], graph: layout.graph, catalog: Self.catalog()) == nil)
    }

    @Test("A join between 520 m and 1 km certifies; beyond the 1 km sanity bound it returns nil")
    func joinLength() {
        let long = Self.loop(rejoin: 700)
        #expect(Self.certify([long.previous, long.next], graph: long.graph, catalog: Self.catalog()) != nil)
        let tooLong = Self.loop(gap: 1200, rejoin: 1500)
        #expect(Self.certify([tooLong.previous, tooLong.next], graph: tooLong.graph,
                             catalog: Self.catalog()) == nil)
    }

    @Test("An ungated seam returns nil", arguments: [
        PairedTracks.Catalog.empty, PairedSeamSyntheticTests.catalog(status: .unclear),
    ])
    func ungatedSeam(catalog: PairedTracks.Catalog) {
        let layout = Self.loop()
        #expect(Self.certify([layout.previous, layout.next], graph: layout.graph, catalog: catalog) == nil)
        // Unrelated rows, a station that is not one of the pair's, a parent→parent gap
        // inside a part that merely lists both rows, and no seam at all.
        for seam in [RouteNetwork.SourceSeam(stationCode: "2", fromLineID: "other-a", toLineID: "other-b"),
                     .init(stationCode: "9", fromLineID: Self.parent, toLineID: Self.paired),
                     .init(stationCode: "2", fromLineID: Self.parent, toLineID: Self.parent)] {
            #expect(Self.certify([layout.previous, layout.next], graph: layout.graph, seams: [seam],
                                 catalog: Self.catalog()) == nil, "\(seam)")
        }
        #expect(Self.certify([layout.previous, layout.next], graph: layout.graph, seams: [],
                             catalog: Self.catalog()) == nil)
    }
}
