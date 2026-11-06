import Foundation
import Testing
@testable import RailCore

/// Regression guard: `japan-paired-tracks.json` is the reviewed list that lets a
/// source path hand over between a line and its paired track. It must stay
/// consistent with the `paired_alignment` rows the package declares, and a real
/// branch must never be listed as a paired track.
@Suite(.serialized)
struct RegressionGuardPairedTracks {
    private static func loadPackage() throws -> DisplayParts.LoadedPackage {
        let root = try PortFixtures.repositoryRoot()
        return try DisplayParts.LoadedPackage.load(
            contentsOf: root.appending(path: "app/public/rail/jp-2025.json"))
    }

    private static func rows(_ package: CompactPackage) -> [String: CompactPackage.Line] {
        Dictionary(package.lines.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
    }

    @Test("The bundled catalog validates against jp-2025 without dropping an entry")
    func bundledValidates() throws {
        let package = try Self.loadPackage().package
        let rows = Self.rows(package)
        let notPairs = Set(PairedTracks.Catalog.bundled.notPairs.map(\.lineID))
        for pair in PairedTracks.Catalog.bundled.pairs {
            let reason = PairedTracks.Catalog.rejection(of: pair, rows: rows, notPairs: notPairs)
            #expect(reason == nil, "\(pair.pairedLineID) is not backed by jp-2025: \(reason ?? "")")
        }
        let validated = PairedTracks.Catalog.bundled.validated(against: package)
        #expect(validated.pairs.count == PairedTracks.Catalog.bundled.pairs.count)
    }

    @Test("Every paired_alignment row in the package has a catalog entry")
    func everyPairedRowIsCatalogued() throws {
        let package = try Self.loadPackage().package
        let paired = package.lines.filter { $0.alignmentRole == "paired_alignment" }
        #expect(!paired.isEmpty)
        for row in paired {
            #expect(PairedTracks.Catalog.bundled.pair(forRow: row.id) != nil,
                "\(row.id) (paired track of \(row.alignmentOf ?? "?")) is declared paired_alignment in jp-2025 but has no entry in japan-paired-tracks.json. Add it to japan-paired-tracks.json with a source.")
        }
    }

    private static func injected(
        pairedID: String, parentID: String, rows: [String: CompactPackage.Line],
        up: String? = nil, down: String? = nil
    ) throws -> PairedTracks.Pair {
        let paired = try #require(rows[pairedID])
        let parent = try #require(rows[parentID])
        let first = try #require(paired.stations.first), last = try #require(paired.stations.last)
        return .init(pairedLineID: pairedID, parentLineID: parentID, line: parent.name,
            operator: parent.operator, from: .init(name: first.name, code: first.id),
            to: .init(name: last.name, code: last.id), upTrack: up, downTrack: down, sharedTrack: nil,
            pairStatus: .confirmed, directionStatus: .confirmed, sources: [], note: nil)
    }

    @Test("Injected 函館線-2 and 上越線-2 entries are rejected")
    func branchesAreRejected() throws {
        let package = try Self.loadPackage().package
        let rows = Self.rows(package)
        let branches = [("jp-北海道旅客鉄道-函館線-2", "jp-北海道旅客鉄道-函館線"),
                        ("jp-東日本旅客鉄道-上越線-2", "jp-東日本旅客鉄道-上越線")]
        for (branchID, parentID) in branches {
            let pair = try Self.injected(pairedID: branchID, parentID: parentID, rows: rows)
            let injectedCatalog = PairedTracks.Catalog(pairs: [pair], notPairs: [])
            #expect(injectedCatalog.validated(against: package).pairs.isEmpty,
                "\(branchID) is a real branch and must not validate as a paired track")
            let listed = PairedTracks.Catalog(pairs: [pair], notPairs: PairedTracks.Catalog.bundled.notPairs)
            #expect(listed.validated(against: package).pairs.isEmpty)
            #expect(PairedTracks.Catalog.bundled.notPairs.contains { $0.lineID == branchID },
                "\(branchID) should be listed under notPairs in japan-paired-tracks.json")
        }
    }

    @Test("An entry whose direction disagrees with the package is rejected")
    func disagreeingDirectionIsRejected() throws {
        let package = try Self.loadPackage().package
        let rows = Self.rows(package)
        let real = try #require(PairedTracks.Catalog.bundled.pair(forRow: "jp-九州旅客鉄道-日豊線-p1"))
        #expect(real.upTrack == real.pairedLineID, "package says 日豊線-p1 is up")
        let flipped = PairedTracks.Pair(
            pairedLineID: real.pairedLineID, parentLineID: real.parentLineID, line: real.line,
            operator: real.operator, from: real.from, to: real.to,
            upTrack: real.downTrack, downTrack: real.upTrack, sharedTrack: real.sharedTrack,
            pairStatus: real.pairStatus, directionStatus: real.directionStatus, sources: real.sources,
            note: real.note)
        let catalog = PairedTracks.Catalog(pairs: [flipped])
        #expect(catalog.validated(against: package).pairs.isEmpty)
        _ = rows
    }

    @Test("Validation depends on catalog content, never on a stale cache")
    func validationIsNotCached() throws {
        let package = try Self.loadPackage().package
        let real = try #require(PairedTracks.Catalog.bundled.pair(forRow: "jp-九州旅客鉄道-日豊線-p1"))
        let good = PairedTracks.Catalog(pairs: [real])
        let flipped = PairedTracks.Pair(
            pairedLineID: real.pairedLineID, parentLineID: real.parentLineID, line: real.line,
            operator: real.operator, from: real.from, to: real.to,
            upTrack: real.downTrack, downTrack: real.upTrack, sharedTrack: real.sharedTrack,
            pairStatus: real.pairStatus, directionStatus: real.directionStatus, sources: real.sources,
            note: real.note)
        #expect(good.validated(against: package).pairs.count == 1)
        #expect(PairedTracks.Catalog(pairs: [flipped]).validated(against: package).pairs.isEmpty)
        #expect(good.validated(against: package).pairs.count == 1)
    }

    @Test("A paired row whose parent has extra stations needs the parent as sharedTrack")
    func extraStationsNeedSharedTrack() throws {
        let package = try Self.loadPackage().package
        let real = try #require(PairedTracks.Catalog.bundled.pair(forRow: "jp-北海道旅客鉄道-函館線-p1"))
        #expect(real.sharedTrack == real.parentLineID)
        let unshared = PairedTracks.Pair(
            pairedLineID: real.pairedLineID, parentLineID: real.parentLineID, line: real.line,
            operator: real.operator, from: real.from, to: real.to, upTrack: real.upTrack,
            downTrack: real.downTrack, sharedTrack: nil, pairStatus: real.pairStatus,
            directionStatus: real.directionStatus, sources: real.sources, note: real.note)
        #expect(PairedTracks.Catalog(pairs: [unshared]).validated(against: package).pairs.isEmpty)
    }

    @Test("Confirmed catalog directions equal the direction the package derives")
    func directionsMatchPackage() throws {
        let package = try Self.loadPackage().package
        let rows = Self.rows(package)
        for pair in PairedTracks.Catalog.bundled.pairs where pair.directionStatus == .confirmed {
            let paired = try #require(rows[pair.pairedLineID])
            let parent = try #require(rows[pair.parentLineID])
            func opposite(_ d: PairedTracks.Direction) -> PairedTracks.Direction { d == .up ? .down : .up }
            var onPaired = paired.alignmentDirection.flatMap(PairedTracks.Direction.init(rawValue:))
            if onPaired == nil, let stated = parent.alignmentPairs.first(where: { $0.with == pair.pairedLineID })?
                .direction, let d = PairedTracks.Direction(rawValue: stated) { onPaired = opposite(d) }
            let direction = try #require(onPaired,
                "\(pair.pairedLineID) is directionStatus confirmed but the package states no direction")
            let catalog = PairedTracks.Catalog(pairs: [pair])
            #expect(catalog.track(for: direction, pair: pair) == pair.pairedLineID,
                "\(pair.pairedLineID): package says the paired row is \(direction.rawValue), catalog disagrees")
            #expect(catalog.track(for: opposite(direction), pair: pair) != pair.pairedLineID)
            // The parent's own allowed direction, from RailwayDirection, must name the other track.
            let ids = parent.stations.map(\.id)
            if let a = ids.firstIndex(of: pair.from.code), let b = ids.firstIndex(of: pair.to.code),
               let order = parent.stationOrderDirection.flatMap(PairedTracks.Direction.init(rawValue:)) {
                let allowed = RailwayDirection.allowedDirections(for: parent, intervalIndex: min(a, b))
                if allowed.count == 1 {
                    let parentDirection = allowed[0] == 1 ? order : opposite(order)
                    #expect(parentDirection == opposite(direction),
                        "\(pair.pairedLineID): RailwayDirection gives the parent \(parentDirection.rawValue) but the paired row is \(direction.rawValue)")
                }
            }
        }
    }

    @Test("notPairs rows declare no alignmentOf")
    func notPairsHaveNoAlignment() throws {
        let rows = Self.rows(try Self.loadPackage().package)
        for entry in PairedTracks.Catalog.bundled.notPairs {
            let row = try #require(rows[entry.lineID], "\(entry.lineID) is not a package row")
            #expect(row.alignmentOf == nil, "\(entry.lineID) declares alignmentOf but is listed in notPairs")
        }
    }

    // MARK: T8 — real branches near a pair behave the same with and without the catalog

    @Test("Branch rides 大沼→森 via 渡島砂原 and 越後湯沢→ガーラ湯沢 ignore the catalog")
    func branchRidesIgnoreCatalog() throws {
        let root = try PortFixtures.repositoryRoot()
        let pipeline = PhysicalEndpointTrimTests()
        let data = try pipeline.loadRealData(root: root)
        let rides = [("jp-北海道旅客鉄道-函館線-2", "大沼", "森"),
                     ("jp-東日本旅客鉄道-上越線-2", "越後湯沢", "ガーラ湯沢")]
        for (lineID, from, to) in rides {
            let empty = Self.branchRide(lineID, from, to, catalog: .empty, data: data, pipeline: pipeline)
            let bundled = Self.branchRide(lineID, from, to, catalog: data.network.pairedTracks, data: data, pipeline: pipeline)
            #expect(empty.found, "\(from)→\(to) on \(lineID) is not on the network")
            #expect(empty.keys == bundled.keys, "\(from)→\(to) differs with the bundled catalog")
        }
    }

    private static func branchRide(
        _ lineID: String, _ from: String, _ to: String, catalog: PairedTracks.Catalog,
        data: PhysicalEndpointTrimTests.RealData, pipeline: PhysicalEndpointTrimTests
    ) -> (found: Bool, keys: [String]?) {
        guard let line = data.network.lines.first(where: { $0.lineId == lineID }),
              let stations = line.compactLine?.stations.map(\.id),
              let fromCode = line.compactLine?.stations.first(where: { $0.name == from })?.id,
              let toCode = line.compactLine?.stations.first(where: { $0.name == to })?.id,
              let start = stations.firstIndex(of: fromCode), let end = stations.firstIndex(of: toCode),
              start != end else { return (false, nil) }
        let step = start < end ? 1 : -1
        var codes: [String] = []
        var index = start
        while index != end {
            codes.append(line.intervals[min(index, index + step)].code)
            index += step
        }
        let hints = RouteHints(requiredLineIDs: [lineID], sectionCodes: codes,
            fromStationCode: fromCode, toStationCode: toCode)
        guard let certified = data.network.sourceCertification(for: hints) else { return (false, nil) }
        let graph = pipeline.proofGraph(certified.geometry.lines.flatMap { $0 }, store: data.graphStore)
        let keys = RouteSolver.verifiedSourcePath(
            certified.geometry.lines, graph: graph, context: .init(rideDate: "2026-10-03"),
            section: .init(from: from, to: to, fromN02StationCode: fromCode, toN02StationCode: toCode),
            displayRowNames: certified.rowNames, anchorIndices: certified.anchorIndices,
            selectedLineIDs: certified.selectedLineIDs, seams: certified.seams, pairedTracks: catalog)
        return (true, keys)
    }

    // MARK: T10 — every confirmed pair certifies in both directions

    @Test("Every confirmed pair certifies a passing-loop seam in both directions")
    func everyConfirmedPairCertifies() {
        let layout = PairedSeamSyntheticTests.loop()
        let catalog = PairedTracks.Catalog.bundled
        for pair in catalog.pairs where pair.pairStatus == .confirmed {
            let forward = RouteSolver.verifiedSourcePath(
                [layout.previous, layout.next], graph: layout.graph, context: .init(rideDate: nil),
                section: .init(), seams: [.init(stationCode: pair.to.code, fromLineID: pair.parentLineID,
                    toLineID: pair.pairedLineID)], pairedTracks: catalog)
            #expect(forward != nil, "\(pair.pairedLineID) does not certify parent→paired")
            let backward = RouteSolver.verifiedSourcePath(
                [layout.next.reversed(), layout.previous.reversed()], graph: layout.graph,
                context: .init(rideDate: nil), section: .init(),
                seams: [.init(stationCode: pair.from.code, fromLineID: pair.pairedLineID,
                    toLineID: pair.parentLineID)], pairedTracks: catalog)
            #expect(backward != nil, "\(pair.pairedLineID) does not certify paired→parent")
        }
    }

    // MARK: every override certifies

    /// The interval codes of `row` between the pair's two stations, in travel
    /// order from `from` to `to`.
    private static func codes(
        on row: String, from: String, to: String, network: RouteNetwork
    ) -> [String]? {
        guard let line = network.lines.first(where: { $0.lineId == row }),
              let ids = line.compactLine?.stations.map(\.id),
              let start = ids.firstIndex(of: from), let end = ids.firstIndex(of: to), start != end else { return nil }
        let low = min(start, end), high = max(start, end)
        guard line.intervals.indices.contains(high - 1) else { return nil }
        let codes = line.intervals[low..<high].map(\.code)
        return start < end ? Array(codes) : codes.reversed()
    }

    @Test("Every confirmed pair certifies with each forced track in both travel directions")
    func everyOverrideCertifies() throws {
        let data = try PhysicalEndpointTrimTests().loadRealData(root: try PortFixtures.repositoryRoot())
        let network = data.network
        let catalog = network.pairedTracks
        let offered = catalog.pairs.filter { $0.pairStatus == .confirmed && $0.directionStatus == .confirmed }
        #expect(!offered.isEmpty)
        for pair in offered {
            for preference in [TrackPreference.up, .down] {
                guard let row = catalog.forcedTrack(preference, pair: pair) else {
                    Issue.record("\(pair.pairedLineID): no row for \(preference.rawValue)"); continue
                }
                for (from, to) in [(pair.from.code, pair.to.code), (pair.to.code, pair.from.code)] {
                    let name = "\(pair.pairedLineID) forced \(preference.rawValue) \(from)→\(to) on \(row)"
                    guard let codes = Self.codes(on: row, from: from, to: to, network: network) else {
                        Issue.record("\(name): the forced row does not run between the pair's stations"); continue
                    }
                    let hints = RouteHints(requiredLineIDs: [row], sectionCodes: codes,
                        fromStationCode: from, toStationCode: to, trackPreference: preference)
                    #expect(network.sourceCertification(for: hints) != nil, "\(name) does not certify")
                    let drawn = network.canonicalizeRouteFeature(RouteFeature(geometry: nil, hints: hints))
                    #expect(drawn?.displayLineIds == [row], "\(name) does not draw on the forced row")
                    // The other track is refused under the override, whatever the direction.
                    let other = [pair.parentLineID, pair.pairedLineID].first { $0 != row }
                    if let other, let otherCodes = Self.codes(on: other, from: from, to: to, network: network) {
                        let forcedOther = RouteHints(requiredLineIDs: [other], sectionCodes: otherCodes,
                            fromStationCode: from, toStationCode: to, trackPreference: preference)
                        #expect(network.sourceCertification(for: forcedOther) == nil,
                            "\(name): the other track \(other) must be refused")
                    }
                }
            }
        }
    }
}
