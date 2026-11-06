import Foundation
import Testing
@testable import RailCore

/// The single feasibility rule (`TripConnectivity`): a row change continues
/// only at a dated reviewed physical junction or a dated through service.
/// Crossings, nearby stations and shared N02 group codes are transfers.
struct TripRouteFeasibilityTests {
    // MARK: Synthetic rows

    @Test("A crossing at a shared code continues only with a reviewed junction")
    func crossingNeedsJunction() throws {
        let package = try fixture([line("main", ["A", "J", "B"]), line("cross", ["C", "J", "D"])])
        guard case .disconnected(let refused) = plan(package, from: "A", to: "D") else {
            Issue.record("A bare shared station must not continue"); return
        }
        #expect(refused.first?.link == TripConnectivity.Link.none)

        let junctions = TripConnectivity.Junctions([.init(id: "j", stationCode: "J", lineIDs: ["main", "cross"])])
        guard case .corridors(let found) = plan(package, from: "A", to: "D", junctions: junctions) else {
            Issue.record("A reviewed junction lets the train continue"); return
        }
        #expect(found.first?.choice.lineIDs == ["main", "cross"])
        #expect(found.first?.junctions.first?.link == .physicalJunction)
    }

    @Test("A junction is honoured only inside its half-open dates")
    func datedJunction() throws {
        let package = try fixture([line("main", ["A", "J", "B"]), line("cross", ["C", "J", "D"])])
        let junctions = TripConnectivity.Junctions([.init(
            id: "j", stationCode: "J", lineIDs: ["main", "cross"], validFrom: "2000-01-01", validTo: "2010-01-01")])
        func continues(_ date: String?) -> Bool {
            if case .corridors = plan(package, from: "A", to: "D", rideDate: date, junctions: junctions) { return true }
            return false
        }
        #expect(!continues("1999-12-31"))
        #expect(continues("2000-01-01"))
        #expect(continues("2009-12-31"))
        #expect(!continues("2010-01-01"))
        // An undated ride sees only junctions still in use.
        #expect(!continues(nil))
    }

    @Test("A junction at another station grants nothing here")
    func junctionIsStationSpecific() throws {
        let package = try fixture([line("main", ["A", "J", "B"]), line("cross", ["C", "J", "D"])])
        let junctions = TripConnectivity.Junctions([.init(id: "j", stationCode: "X", lineIDs: ["main", "cross"])])
        guard case .disconnected = plan(package, from: "A", to: "D", junctions: junctions) else {
            Issue.record("Expected disconnected"); return
        }
    }

    @Test("Parallel lines with separate nearby stations never join")
    func parallelLinesNoSharedStation() throws {
        // Coordinates are a few metres apart, but no station code is shared.
        let package = try fixture([line("east", ["A", "B", "C"]), line("west", ["A2", "B2", "C2"])])
        let outcome = plan(package, from: "A", to: "C2")
        if case .corridors = outcome { Issue.record("Proximity must not connect rows: \(outcome)") }
    }

    @Test("A via line change follows the same rule")
    func viaJoinUsesRule() throws {
        let package = try fixture([line("main", ["A", "J", "B"]), line("cross", ["C", "J", "D"])])
        let first = try #require(corridorList(package, from: "A", to: "J").first)
        let second = try #require(corridorList(package, from: "J", to: "D").first)
        let refused = TripRoutePlanner.joining(
            [first, second], allowUnverifiedConnections: false, rideDate: nil,
            patterns: [], connectors: [], junctions: .empty) { $0 }
        guard case .disconnected = refused else { Issue.record("Expected a refused via change"); return }
        let junctions = TripConnectivity.Junctions([.init(id: "j", stationCode: "J", lineIDs: ["main", "cross"])])
        let joined = TripRoutePlanner.joining(
            [first, second], allowUnverifiedConnections: false, rideDate: nil,
            patterns: [], connectors: [], junctions: junctions) { $0 }
        guard case .corridors(let route) = joined else { Issue.record("Expected a joined route"); return }
        #expect(route.first?.junctions.first?.link == .physicalJunction)
    }

    // MARK: Registry

    @Test("The registry yields dated two-row joins with evidence")
    func registryJoins() throws {
        let junctions = try registry()
        #expect(junctions.join("jp-東海旅客鉄道-東海道新幹線", "jp-西日本旅客鉄道-山陽新幹線",
                               at: "006911", on: "2026-01-01")?.id == "shin-osaka-tokaido-sanyo")
        #expect(junctions.join("jp-西日本旅客鉄道-山陽新幹線", "jp-九州旅客鉄道-九州新幹線",
                               at: "009033", on: "2011-03-11") == nil)
        #expect(junctions.join("jp-西日本旅客鉄道-山陽新幹線", "jp-九州旅客鉄道-九州新幹線",
                               at: "009033", on: "2011-03-12") != nil)
        // Same-row identity records (one row ID) never become a join.
        #expect(junctions.join("jp-東日本旅客鉄道-東北新幹線", "jp-東日本旅客鉄道-東北新幹線",
                               at: "003766", on: "2026-01-01") == nil)
    }

    // MARK: Bundled Japan network

    @Test("Shinkansen through trains route across reviewed junctions", arguments: [
        ("003766", "009033", "2026-01-01", ["jp-東海旅客鉄道-東海道新幹線", "jp-西日本旅客鉄道-山陽新幹線"]),
        ("006911", "010047", "2026-01-01", ["jp-西日本旅客鉄道-山陽新幹線", "jp-九州旅客鉄道-九州新幹線"]),
        ("003766", "001296", "2026-01-01", ["jp-東日本旅客鉄道-東北新幹線", "jp-東日本旅客鉄道-上越新幹線"]),
        ("003766", "002093", "2026-01-01", ["jp-東日本旅客鉄道-東北新幹線", "jp-東日本旅客鉄道-上越新幹線",
                                           "jp-東日本旅客鉄道-北陸新幹線", "jp-西日本旅客鉄道-北陸新幹線"]),
    ])
    func shinkansenThrough(origin: String, destination: String, date: String, lineIDs: [String]) throws {
        let package = try japan(lineIDs)
        let catalog = try JapanThroughServices.loadBundled()
        let outcome = TripRoutePlanner.plan(
            package: package, request: .init(originCode: origin, destinationCode: destination, trainType: "shinkansen"),
            rideDate: date, patterns: catalog.patterns, connectors: catalog.connectors, junctions: try registry())
        guard case .corridors(let found) = outcome else { Issue.record("Expected corridors, got \(outcome)"); return }
        #expect(found.first?.choice.lineIDs == lineIDs)
        #expect(found.first?.junctions.allSatisfy { $0.link.continues } == true)
    }

    @Test("Sanyo–Kyushu does not continue before 2011-03-12")
    func kyushuBeforeOpening() throws {
        let ids = ["jp-西日本旅客鉄道-山陽新幹線", "jp-九州旅客鉄道-九州新幹線"]
        let package = try japan(ids)
        let catalog = try JapanThroughServices.loadBundled()
        let outcome = TripRoutePlanner.plan(
            package: package, request: .init(originCode: "006911", destinationCode: "010047", trainType: "shinkansen"),
            rideDate: "2011-03-11", patterns: catalog.patterns, connectors: catalog.connectors, junctions: try registry())
        guard case .disconnected = outcome else { Issue.record("Expected disconnected, got \(outcome)"); return }
    }

    @Test("A shared group code of unrelated operators is a transfer (浅草 Ginza → Tobu)")
    func sharedGroupCodeIsTransfer() throws {
        let ids = ["jp-東京地下鉄-3号線銀座線", "jp-東武鉄道-伊勢崎線"]
        let package = try japan(ids)
        let catalog = try JapanThroughServices.loadBundled()
        let outcome = TripRoutePlanner.plan(
            package: package,
            request: .init(originCode: "003505", destinationCode: "003260",
                           originLineID: ids[0], destinationLineID: ids[1]),
            rideDate: "2026-01-01", patterns: catalog.patterns, connectors: catalog.connectors, junctions: try registry())
        guard case .disconnected(let refused) = outcome else { Issue.record("Expected disconnected, got \(outcome)"); return }
        #expect(refused.first?.stationCode == "003522")
        #expect(refused.first?.link == TripConnectivity.Link.none)
    }

    @Test("Continue anyway at a shared group code draws two separate rows, never joining track")
    func overrideDrawsTransferNotTrack() throws {
        let ids = ["jp-東京地下鉄-3号線銀座線", "jp-東武鉄道-伊勢崎線"]
        let package = try japan(ids)
        let catalog = try JapanThroughServices.loadBundled()
        let outcome = TripRoutePlanner.plan(
            package: package,
            request: .init(originCode: "003505", destinationCode: "003260",
                           originLineID: ids[0], destinationLineID: ids[1], allowUnverifiedConnections: true),
            rideDate: "2026-01-01", patterns: catalog.patterns, connectors: catalog.connectors, junctions: try registry())
        guard case .corridors(let found) = outcome, let corridor = found.first else {
            Issue.record("Expected the overridden corridor, got \(outcome)"); return
        }
        // The change stays a transfer: it is labelled unverified and the
        // saved sections split at 浅草, one row per section.
        #expect(corridor.junctions.map(\.link) == [TripConnectivity.Link.none])
        #expect(corridor.junctions.first?.stationCode == "003522")
        #expect(corridor.choice.routeSections.allSatisfy { ($0.lineIDs ?? []).count == 1 })
        let pieces = TripRouteGeometry.pieces(for: corridor.choice, cache: TripRouteGeometry.Cache(package: package))
        // Each drawn piece is real track of one row; nothing bridges the rows.
        #expect(pieces.allSatisfy { !$0.isConnector })
        #expect(Set(pieces.compactMap(\.lineID)) == Set(ids))
        #expect(pieces.count == 2)
    }

    @Test("Same-name stations with separate codes do not join (TX 浅草 vs Tobu 浅草)")
    func sameNameSeparateStations() throws {
        let ids = ["jp-首都圏新都市鉄道-常磐新線", "jp-東武鉄道-伊勢崎線"]
        let package = try japan(ids)
        let catalog = try JapanThroughServices.loadBundled()
        let outcome = TripRoutePlanner.plan(
            package: package,
            request: .init(originCode: "003624", destinationCode: "003522",
                           originLineID: ids[0], destinationLineID: ids[1]),
            rideDate: "2026-01-01", patterns: catalog.patterns, connectors: catalog.connectors, junctions: try registry())
        if case .corridors = outcome { Issue.record("Unconnected operators must not route: \(outcome)") }
    }

    @Test("Lines crossing without a station do not join (南武線 × 田園都市線 at 溝の口)")
    func crossingWithoutStation() throws {
        let ids = ["jp-東日本旅客鉄道-南武線", "jp-東急電鉄-田園都市線"]
        let package = try japan(ids)
        let catalog = try JapanThroughServices.loadBundled()
        let outcome = TripRoutePlanner.plan(
            package: package,
            request: .init(originCode: "004242", destinationCode: "004430",
                           originLineID: ids[0], destinationLineID: ids[1]),
            rideDate: "2026-01-01", patterns: catalog.patterns, connectors: catalog.connectors, junctions: try registry())
        if case .corridors = outcome { Issue.record("A crossing must not route: \(outcome)") }
    }

    @Test("New through-service records continue at their anchors on their dates")
    func newCatalogRecords() throws {
        let catalog = try JapanThroughServices.loadBundled()
        func link(_ a: String, _ b: String, _ code: String, _ date: String) -> TripConnectivity.Link {
            TripConnectivity.link(fromLineID: a, toLineID: b, atStationCode: code, on: date,
                                  patterns: catalog.patterns, connectors: catalog.connectors)
        }
        #expect(link("jp-東急電鉄-東横線", "jp-横浜高速鉄道-みなとみらい21線", "004633", "2004-02-01") == .throughService)
        #expect(link("jp-東急電鉄-東横線", "jp-横浜高速鉄道-みなとみらい21線", "004633", "2004-01-31") == .none)
        #expect(link("jp-東急電鉄-田園都市線", "jp-東京地下鉄-11号線半蔵門線", "003922", "1978-08-01") == .throughService)
        #expect(link("jp-東急電鉄-田園都市線", "jp-東京地下鉄-11号線半蔵門線", "003922", "1978-07-31") == .none)
        #expect(link("jp-東海旅客鉄道-東海道新幹線", "jp-西日本旅客鉄道-山陽新幹線", "006911", "1975-03-10") == .throughService)
        #expect(link("jp-東海旅客鉄道-東海道新幹線", "jp-東日本旅客鉄道-東北新幹線", "003766", "2026-01-01") == .none)
    }

    // MARK: Helpers

    private func plan(_ package: CompactPackage, from: String, to: String, rideDate: String? = nil,
                      junctions: TripConnectivity.Junctions = .empty) -> TripRoutePlanner.Outcome {
        TripRoutePlanner.plan(package: package, request: .init(originCode: from, destinationCode: to),
                              rideDate: rideDate, patterns: [], connectors: [], junctions: junctions)
    }

    private func corridorList(_ package: CompactPackage, from: String, to: String) -> [TripRoutePlanner.Corridor] {
        guard case .corridors(let values) = plan(package, from: from, to: to) else { return [] }
        return values
    }

    private func japan(_ ids: [String]) throws -> CompactPackage {
        let source = try PortFixtures.package(country: "jp")
        return CompactPackage(format: source.format, version: source.version, country: source.country,
                              lines: source.lines.filter { ids.contains($0.id) })
    }

    private func registry() throws -> TripConnectivity.Junctions {
        let url = try PortFixtures.repositoryRoot().appendingPathComponent("app/data/physical-rail-junctions.json")
        return try Self.cachedRegistry(url)
    }

    private static let lock = NSLock()
    nonisolated(unsafe) private static var cached: TripConnectivity.Junctions?
    private static func cachedRegistry(_ url: URL) throws -> TripConnectivity.Junctions {
        lock.lock()
        defer { lock.unlock() }
        if let cached { return cached }
        let value = try TripConnectivity.Junctions(registryData: Data(contentsOf: url), region: "jp")
        cached = value
        return value
    }

    private func line(_ id: String, _ codes: [String]) -> [String: Any] {
        ["id": id, "name": id, "operator": "Operator", "rank": 3, "kind": "jr_conventional",
         "stations": codes.enumerated().map { [$0.element, $0.element, Double($0.offset), 0] as [Any] },
         "segments": (0..<(codes.count - 1)).map {
             [1.0, 0, [[Double($0), 0], [Double($0 + 1), 0]]] as [Any]
         }]
    }

    private func fixture(_ lines: [[String: Any]]) throws -> CompactPackage {
        let data = try JSONSerialization.data(withJSONObject: [
            "format": "compact-v1", "version": "test", "country": "jp", "lines": lines])
        return try JSONDecoder().decode(CompactPackage.self, from: data)
    }
}
