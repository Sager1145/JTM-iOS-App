import Foundation
import Testing
@testable import RailCore

/// 東京→新大阪: the conventional 東海道線 crosses three JR companies
/// (熱海, 大垣, 米原). Planning must stay fast enough for the editor's live
/// route, and every offered corridor must become a savable draft.
struct TokyoShinOsakaPlanningTests {
    @Test("東京→新大阪 plans well under a second and every corridor autofills", arguments: [false, true])
    func tokyoShinOsaka(allowUnverified: Bool) throws {
        let package = try PortFixtures.package(country: "jp")
        let catalog = try JapanThroughServices.loadBundled()
        let root = try PortFixtures.repositoryRoot()
        let history = try RailHistoryOverlay.load(from: root.appending(path: "app/data/rail-history.json"))
        let context = try RailwayRouteChoices.AdmissionContext(history: history, civilDay: "2025-01-03")
        let junctions = try TripConnectivity.Junctions(
            registryData: Data(contentsOf: root.appending(path: "app/data/physical-rail-junctions.json")),
            region: "jp")
        var request = TripRoutePlanner.Request(originCode: "003766", destinationCode: "006911")
        request.allowUnverifiedConnections = allowUnverified
        func plan() -> TripRoutePlanner.Outcome {
            TripRoutePlanner.plan(package: package, request: request, rideDate: "2025-01-03",
                                  patterns: catalog.patterns, connectors: catalog.connectors,
                                  junctions: junctions, admissionContext: context)
        }
        _ = plan() // per-line interval caches are warm in the editor
        let clock = ContinuousClock()
        var outcome: TripRoutePlanner.Outcome = .noRoute
        let elapsed = clock.measure { outcome = plan() }
        print("TIMING 東京→新大阪 override=\(allowUnverified) warm=\(elapsed)")
        #expect(elapsed < .seconds(1), "planned in \(elapsed)")
        guard case .corridors(let corridors) = outcome else {
            Issue.record("Expected corridors, got \(outcome)"); return
        }
        // The conventional line across 熱海, 大垣 and 米原 is one physical path.
        #expect(corridors.contains { corridor in
            ["jp-東海旅客鉄道-東海道線", "jp-東海旅客鉄道-東海道線-2", "jp-西日本旅客鉄道-東海道線"]
                .allSatisfy(corridor.choice.lineIDs.contains)
        })
        for corridor in corridors {
            let draft = Train(id: "new", number: "", origin: "", destination: "",
                              stops: [Stop(name: ""), Stop(name: "")])
            let proposal = LocalJourneyAutofill.proposal(train: draft, choice: corridor.choice)
            #expect(proposal != nil, "\(corridor.choice.lineIDs)")
            #expect(proposal?.train.stops.first?.n02StationCode == "003766")
            #expect(proposal?.train.stops.last?.n02StationCode == "006911")
        }
    }

    @Test("The indexed through-service continuations equal the per-call scan",
          arguments: [nil, "1975-03-10", "1990-01-01", "2004-01-31", "2011-03-11", "2011-03-12",
                      "2024-03-15", "2024-03-16", "2025-01-03", "2026-11-05"] as [String?])
    func indexMatchesScan(date: String?) throws {
        let catalog = try JapanThroughServices.loadBundled()
        let index = JapanThroughServices.ContinuationIndex(
            patterns: catalog.patterns, connectors: catalog.connectors, on: date)
        // Every leg boundary of every pattern, in both directions and with each
        // leg's reverse row, at both boundary codes and at an unrelated code.
        var probes: Set<[String]> = []
        for pattern in catalog.patterns {
            let legs = pattern.legs(on: nil)
            for (a, b) in zip(legs, legs.dropFirst()) {
                let firstIDs = [a.lineID] + (a.reverseLineID.map { [$0] } ?? [])
                let secondIDs = [b.lineID] + (b.reverseLineID.map { [$0] } ?? [])
                for first in firstIDs {
                    for second in secondIDs {
                        for code in [a.toStationCode, b.fromStationCode, a.fromStationCode, "000000"] {
                            probes.insert([first, second, code])
                            probes.insert([second, first, code])
                        }
                    }
                }
            }
        }
        #expect(probes.count > 500)
        for probe in probes {
            let scanned = JapanThroughServices.continuationCodes(
                fromLineID: probe[0], toLineID: probe[1], atStationCode: probe[2], on: date,
                patterns: catalog.patterns, connectors: catalog.connectors)
            #expect(index.continuationCodes(fromLineID: probe[0], toLineID: probe[1],
                                            atStationCode: probe[2]) == scanned, "\(probe) on \(date ?? "current")")
        }
    }
}
