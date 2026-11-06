import Foundation
import Testing
@testable import RailCore

/// 日豊線 立石: the parent's 立石–中山香 and the paired 日豊線-p1 meet 35 m
/// apart on different tracks, so source certification splits the path there and
/// the seam must be joined through the passing loop, never by reversing.
@Suite(.serialized)
struct PairedSeamCertificationTests {
    static let parentID = "jp-九州旅客鉄道-日豊線"
    static let pairedID = "jp-九州旅客鉄道-日豊線-p1"
    static let date = "2026-10-03"

    struct Ride {
        var keys: [String]?
        var parts = 0
        var selected: Set<String> = []
    }

    static func stationCode(_ name: String, in network: RouteNetwork) -> String? {
        network.lines.first { $0.lineId == parentID }?.compactLine?.stations.first { $0.name == name }?.id
    }

    /// Station-to-station source certification as the production rider does it:
    /// solve the section, canonicalise onto the display rows, certify the matched
    /// intervals, then prove the source path with the selected line ids.
    static func ride(
        _ from: String, _ to: String, pairedTracks: PairedTracks.Catalog? = nil,
        data: PhysicalEndpointTrimTests.RealData, pipeline: PhysicalEndpointTrimTests
    ) -> Ride? {
        guard let fromCode = stationCode(from, in: data.network),
              let toCode = stationCode(to, in: data.network) else { return nil }
        let section = RouteSection(from: from, to: to, fromN02StationCode: fromCode,
            toN02StationCode: toCode, lineNames: ["日豊線"], operatorNames: ["九州旅客鉄道"])
        let context = RouteSolver.TrainContext(rideDate: date)
        guard let solved = RouteSolver.solveSectionOnDemand(
            section, segmentIndex: 0, train: context, country: "jp",
            graphStore: data.graphStore, stations: data.stations, traversalPolicy: .physicalRail) else { return nil }
        var cache = RouteProjectionCache()
        let hints = RouteHints(
            requiredLineNames: ["日豊線"].map(Optional.some), preferredLineNames: [],
            requiredOperatorNames: ["九州旅客鉄道"].map(Optional.some), preferredOperatorNames: [],
            requiredLineIDs: [], sectionCodes: [], fromStationCode: fromCode, toStationCode: toCode)
        guard let canonical = data.network.canonicalizeRouteFeature(
            RouteFeature(geometry: .lineString(solved.coordinates), hints: hints),
            continueFrom: nil, cache: &cache) else { return nil }
        var matched = hints
        matched.sectionCodes = canonical.matchedSectionCodes
        matched.requiredLineIDs = canonical.displayLineIds
        guard let certified = data.network.sourceCertification(for: matched) else { return nil }
        let graph = pipeline.proofGraph(certified.geometry.lines.flatMap { $0 }, store: data.graphStore)
        let keys = RouteSolver.verifiedSourcePath(
            certified.geometry.lines, graph: graph, context: context, section: section,
            displayRowNames: certified.rowNames, anchorIndices: certified.anchorIndices,
            selectedLineIDs: certified.selectedLineIDs, seams: certified.seams,
            pairedTracks: pairedTracks ?? data.network.pairedTracks)
        return Ride(keys: keys, parts: certified.geometry.lines.count,
                    selected: certified.selectedLineIDs.reduce(into: []) { $0.formUnion($1) })
    }

    static func digest(_ keys: [String]) -> String {
        RouteGraph.keyDigest(keys.joined(separator: "|"))
    }

    static func hasNode(_ keys: [String], lon: Double, lat: Double) -> Bool {
        let suffix = "@" + Grid.coordKey(Grid.normalizeGraphCoord(Coordinate(lon: lon, lat: lat)))
        return keys.contains { $0.hasSuffix(suffix) }
    }

    static func hasReversal(_ keys: [String]) -> Bool {
        zip(keys, keys.dropFirst(2)).contains { $0 == $1 }
    }

    private func load() throws -> (PhysicalEndpointTrimTests, PhysicalEndpointTrimTests.RealData) {
        let pipeline = PhysicalEndpointTrimTests()
        return (pipeline, try pipeline.loadRealData(root: try PortFixtures.repositoryRoot()))
    }

    @Test("T2/T4 up ride 杵築→中津 certifies through the loop's south track")
    func upRideCertifies() throws {
        let (pipeline, data) = try load()
        let empty = Self.ride("杵築", "中津", pairedTracks: .empty, data: data, pipeline: pipeline)
        print("BASE[empty] 杵築→中津 keys=\(empty?.keys.map { "\($0.count) \(Self.digest($0))" } ?? "nil")")
        let up = try #require(Self.ride("杵築", "中津", data: data, pipeline: pipeline))
        let keys = try #require(up.keys, "杵築→中津 does not certify")
        #expect(Self.hasNode(keys, lon: 131.4783, lat: 33.48176))
        #expect(Self.hasNode(keys, lon: 131.47583, lat: 33.48178))
        #expect(!Self.hasNode(keys, lon: 131.47833, lat: 33.48194))
        #expect(!Self.hasReversal(keys))
    }

    @Test("T3 down ride 中津→杵築 stays on the parent and is unchanged by the catalog")
    func downRideUnchanged() throws {
        let (pipeline, data) = try load()
        let empty = try #require(Self.ride("中津", "杵築", pairedTracks: .empty, data: data, pipeline: pipeline))
        let bundled = try #require(Self.ride("中津", "杵築", data: data, pipeline: pipeline))
        print("BASE[T3] 中津→杵築 keys=\(empty.keys.map { "\($0.count) \(Self.digest($0))" } ?? "nil") selected=\(empty.selected)")
        #expect(empty.keys != nil)
        #expect(bundled.keys == empty.keys)
        #expect(!bundled.selected.contains(Self.pairedID), "the down ride must stay on the parent")
    }

    @Test("T4 rides touching 立石 are unchanged by the catalog; 立石→中津 uses p1 without reversal")
    func ridesTouchingTateishi() throws {
        let (pipeline, data) = try load()
        let rides = [("立石", "中津"), ("中山香", "立石"), ("立石", "杵築"), ("杵築", "立石"), ("立石", "宇佐")]
        for (from, to) in rides {
            let empty = Self.ride(from, to, pairedTracks: .empty, data: data, pipeline: pipeline)
            let bundled = Self.ride(from, to, data: data, pipeline: pipeline)
            print("BASE[T4] \(from)→\(to) keys=\(empty?.keys.map { "\($0.count) \(Self.digest($0))" } ?? "nil") parts=\(empty?.parts ?? -1) selected=\(empty?.selected.map { String($0.suffix(6)) } ?? [])")
            #expect(bundled?.keys == empty?.keys, "\(from)→\(to) changed with the catalog")
        }
        let toNakatsu = try #require(Self.ride("立石", "中津", data: data, pipeline: pipeline))
        #expect(toNakatsu.selected.contains(Self.pairedID), "立石→中津 should use p1")
        let keys = try #require(toNakatsu.keys, "立石→中津 does not certify")
        #expect(!Self.hasReversal(keys))
    }

    @Test("T5 ソニック44 has no certification gap after the seam join")
    func sonic44() throws {
        let (pipeline, data) = try load()
        let root = try PortFixtures.repositoryRoot()
        var counts: [String: PhysicalEndpointTrimTests.GapCounts] = [:]
        for (name, catalog) in [("empty", PairedTracks.Catalog.empty), ("bundled", .bundled)] {
            counts[name] = try pipeline.gapCounts(
                fixture: "part-131", expectedID: "journey_6F379655E47131DD2F854B65A847B9F0",
                branch: .automatic, root: root, data: data, pairedTracks: catalog)
            print("BASE[T5 \(name)] nonBoundary=\(counts[name]!.nonBoundary) reasons=\(counts[name]!.reasons) boundary=\(counts[name]!.boundaryStations)")
        }
        let bundled = try #require(counts["bundled"])
        #expect(bundled.nonBoundary == 0)
        #expect(!bundled.boundaryStations.contains("杵築"), "杵築→宇佐 still has a gap")
    }

    // MARK: Branch counter-tests and junction rides

    /// Certify the chain of station codes along the given rows via the resolver.
    private func chain(
        _ codes: [String], lineIDs: [String], catalog: PairedTracks.Catalog,
        data: PhysicalEndpointTrimTests.RealData, pipeline: PhysicalEndpointTrimTests
    ) -> (resolved: Bool, lineIDs: Set<String>, keys: [String]?) {
        let outcome = data.resolver.resolve(stationCodes: codes, requiredLineIDs: lineIDs)
        guard case .resolved(let selection) = outcome else {
            print("BASE[chain] \(codes) -> \(outcome)")
            return (false, [], nil)
        }
        let hints = RouteHints(requiredLineIDs: Array(selection.lineIDs), sectionCodes: selection.sectionCodes,
            fromStationCode: codes.first, toStationCode: codes.last)
        guard let certified = data.network.sourceCertification(for: hints) else {
            print("BASE[chain] \(codes) resolved but sourceCertification is nil; lines=\(selection.lineIDs)")
            return (true, Set(selection.lineIDs), nil)
        }
        let graph = pipeline.proofGraph(certified.geometry.lines.flatMap { $0 }, store: data.graphStore)
        let keys = RouteSolver.verifiedSourcePath(
            certified.geometry.lines, graph: graph, context: .init(rideDate: Self.date), section: .init(),
            displayRowNames: certified.rowNames, anchorIndices: certified.anchorIndices,
            selectedLineIDs: certified.selectedLineIDs, seams: certified.seams, pairedTracks: catalog)
        if keys == nil {
            print("BASE[chain] \(codes) certified parts=\(certified.geometry.lines.count) lines=\(selection.lineIDs) but verifiedSourcePath is nil")
        }
        return (true, Set(selection.lineIDs), keys)
    }

    private func code(_ name: String, row: String, data: PhysicalEndpointTrimTests.RealData) -> String? {
        data.network.lines.first { $0.lineId == row }?.compactLine?.stations.first { $0.name == name }?.id
    }

    @Test("ガーラ湯沢→水上 does not use the seam join")
    func galaToMinakami() throws {
        let (pipeline, data) = try load()
        let branch = "jp-東日本旅客鉄道-上越線-2", parent = "jp-東日本旅客鉄道-上越線"
        let gala = try #require(code("ガーラ湯沢", row: branch, data: data))
        let minakami = try #require(code("水上", row: parent, data: data))
        let junction = try #require(code("越後湯沢", row: parent, data: data))
        let empty = chain([gala, junction, minakami], lineIDs: [branch, parent], catalog: .empty, data: data, pipeline: pipeline)
        let bundled = chain([gala, junction, minakami], lineIDs: [branch, parent], catalog: data.network.pairedTracks, data: data, pipeline: pipeline)
        // The resolver reports this long chain unsupported today for reasons unrelated to
        // the seam join, so this guards only that the catalog changes nothing.
        #expect(bundled.resolved == empty.resolved)
        #expect(bundled.keys == empty.keys)
    }

    @Test("函館線-2 森→大沼→七飯 does not join 藤城 against its direction")
    func moriToNanae() throws {
        let (pipeline, data) = try load()
        let branch = "jp-北海道旅客鉄道-函館線-2", parent = "jp-北海道旅客鉄道-函館線"
        let mori = try #require(code("森", row: branch, data: data))
        let onuma = try #require(code("大沼", row: branch, data: data))
        let nanae = try #require(code("七飯", row: parent, data: data))
        let empty = chain([mori, onuma, nanae], lineIDs: [branch, parent], catalog: .empty, data: data, pipeline: pipeline)
        let bundled = chain([mori, onuma, nanae], lineIDs: [branch, parent], catalog: data.network.pairedTracks, data: data, pipeline: pipeline)
        #expect(bundled.resolved && empty.resolved)
        #expect(!bundled.lineIDs.contains(parent + "-p1"), "藤城 is down-only; 大沼→七飯 is up")
        #expect(bundled.keys == empty.keys)
    }

    @Test("Rides through the ガーラ湯沢 and 東北線-2..-5 junctions are unchanged by the catalog")
    func junctionRides() throws {
        let (pipeline, data) = try load()
        // 東北線-4 shares no station with the parent row, so it has no junction to ride.
        // Whether these chains resolve or certify at all is the paired-join follow-up
        // (the resolver blocks some of them today); this guards only that the seam
        // catalog changes none of them.
        var cases: [(String, String)] = [("jp-東日本旅客鉄道-上越線-2", "jp-東日本旅客鉄道-上越線")]
        for n in 2...5 { cases.append(("jp-東日本旅客鉄道-東北線-\(n)", "jp-東日本旅客鉄道-東北線")) }
        for (branchID, parentID) in cases {
            guard let branch = data.network.lines.first(where: { $0.lineId == branchID })?.compactLine,
                  let parent = data.network.lines.first(where: { $0.lineId == parentID })?.compactLine else {
                Issue.record("\(branchID) or \(parentID) is not in the package"); continue
            }
            let branchIDs = branch.stations.map(\.id), parentIDs = parent.stations.map(\.id)
            guard let junction = branchIDs.filter(parentIDs.contains).first else { continue }
            let b = branchIDs.firstIndex(of: junction)!, p = parentIDs.firstIndex(of: junction)!
            let branchNeighbours = [b - 1, b + 1].filter { branchIDs.indices.contains($0) && !parentIDs.contains(branchIDs[$0]) }
            let parentNeighbours = [p - 1, p + 1].filter { parentIDs.indices.contains($0) && !branchIDs.contains(parentIDs[$0]) }
            for bn in branchNeighbours { for pn in parentNeighbours {
                let codes = [branchIDs[bn], junction, parentIDs[pn]]
                let empty = chain(codes, lineIDs: [branchID, parentID], catalog: .empty, data: data, pipeline: pipeline)
                let bundled = chain(codes, lineIDs: [branchID, parentID], catalog: data.network.pairedTracks,
                                    data: data, pipeline: pipeline)
                #expect(bundled.resolved == empty.resolved && bundled.keys == empty.keys,
                    "\(branchID): \(branch.stations[bn].name)→\(branch.stations[b].name)→\(parent.stations[pn].name) changed with the catalog")
            } }
        }
    }

    @Test("Bundled catalog first on fresh data certifies; the empty catalog afterwards still fails")
    func bundledFirstIsOrderIndependent() throws {
        let (pipeline, data) = try load()
        let bundled = try #require(Self.ride("杵築", "中津", data: data, pipeline: pipeline))
        #expect(bundled.keys != nil)
        // A spliced proof is never retained in the graph's shared proof cache, so a later
        // ride without the catalog cannot be served the spliced result.
        let empty = try #require(Self.ride("杵築", "中津", pairedTracks: .empty, data: data, pipeline: pipeline))
        #expect(empty.keys == nil)
        let again = try #require(Self.ride("杵築", "中津", data: data, pipeline: pipeline))
        #expect(again.keys == bundled.keys)
    }
}
