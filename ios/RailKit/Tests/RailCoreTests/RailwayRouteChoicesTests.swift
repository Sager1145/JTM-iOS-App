import Foundation
import Testing
@testable import RailCore

struct RailwayRouteChoicesTests {
    private let surface = "jp-東日本旅客鉄道-東海道線"
    private let tunnel = "jp-東日本旅客鉄道-総武線-3"

    @Test("Tokyo–Shinagawa ordinary routes preserve surface and tunnel station membership")
    func tokyoPhysicalAlignments() throws {
        let choices = RailwayRouteChoices.choices(
            package: try PortFixtures.package(country: "jp"),
            originCode: "003766", destinationCode: "004095", trainType: "local")
        #expect(Set(choices.flatMap(\.lineIDs)) == Set([surface, tunnel]))
        let above = try #require(choices.first { $0.lineIDs == [surface] })
        #expect(above.stations.map(\.name) == [
            "東京", "有楽町", "新橋", "浜松町", "田町", "高輪ゲートウェイ", "品川"])
        let below = try #require(choices.first { $0.lineIDs == [tunnel] })
        #expect(below.stations.map(\.name) == ["東京", "新橋", "品川"])
        #expect(above.sectionCodes.count == 6)
        #expect(below.sectionCodes.count == 2)
        #expect(below.routeSections.first?.lineIDs == [tunnel])
        #expect(below.routeSections.flatMap { $0.sectionCodes ?? [] } == below.sectionCodes)
        #expect(above.routeSections.count == 6)
        #expect(below.routeSections.count == 2)
    }

    @Test("Deleting a mandatory surface station selects only the physical tunnel alternative")
    func excludeYurakuchoThenShimbashi() throws {
        let package = try PortFixtures.package(country: "jp")
        let alternatives = RailwayRouteChoices.choices(
            package: package, originCode: "003766", destinationCode: "004095",
            trainType: "rapid", excludingStationCodes: ["003795"])
        #expect(alternatives.count == 1)
        #expect(alternatives.first?.lineIDs == [tunnel])
        #expect(alternatives.first?.stations.map(\.name) == ["東京", "新橋", "品川"])
        #expect(RailwayRouteChoices.choices(
            package: package, originCode: "003766", destinationCode: "004095",
            trainType: "local", excludingStationCodes: ["003795", "003872"]).isEmpty)
    }

    @Test("Reverse travel retains physical identities in reversed traversal order")
    func reversal() throws {
        let package = try PortFixtures.package(country: "jp")
        let forward = try #require(RailwayRouteChoices.choices(
            package: package, originCode: "003766", destinationCode: "004095")
            .first { $0.lineIDs == [surface] })
        let reverse = try #require(RailwayRouteChoices.choices(
            package: package, originCode: "004095", destinationCode: "003766")
            .first { $0.lineIDs == [surface] })
        #expect(reverse.stations == Array(forward.stations.reversed()))
        #expect(reverse.sectionCodes == Array(forward.sectionCodes.reversed()))
    }

    @Test("High speed type chooses Shinkansen, never an ordinary alignment")
    func trainType() throws {
        let choices = RailwayRouteChoices.choices(
            package: try PortFixtures.package(country: "jp"),
            originCode: "003766", destinationCode: "004095", trainType: "highSpeed")
        #expect(choices.count == 1)
        #expect(choices.first?.lineIDs == ["jp-東海旅客鉄道-東海道新幹線"])
        #expect(choices.first?.stations.map(\.name) == ["東京", "品川"])
    }

    @Test("Disconnected same-name package rows cannot create an invented transfer")
    func disconnectedFamily() throws {
        let package = try fixture([
            line("first", stations: ["A", "B"]),
            line("second", stations: ["C", "D"]),
        ])
        #expect(RailwayRouteChoices.choices(
            package: package, originCode: "A", destinationCode: "D").isEmpty)
    }

    @Test("Same-family split rows still require verified junction evidence")
    func splitFamily() throws {
        let package = try fixture([
            line("first", stations: ["A", "B", "C"]),
            line("second", stations: ["C", "D", "E"]),
        ])
        #expect(RailwayRouteChoices.choices(
            package: package, originCode: "A", destinationCode: "E").isEmpty)
    }

    @Test("Both loop directions include the closing physical interval")
    func loopClosing() throws {
        let package = try fixture([line("loop", stations: ["A", "B", "C"], loop: true)])
        let choices = RailwayRouteChoices.choices(package: package, originCode: "A", destinationCode: "C")
        #expect(Set(choices.map { $0.stations.map(\.code) }) == Set([["A", "C"], ["A", "B", "C"]]))
        #expect(choices.contains { $0.sectionCodes == ["loop@A:C"] })
    }

    @Test("An unverified branch cannot leave and rejoin a known trunk")
    func rejoiningBranch() throws {
        let package = try fixture([
            line("trunk", stations: ["A", "B", "C", "D", "E"]),
            line("branch", stations: ["D", "X", "B"]),
        ])
        let choices = RailwayRouteChoices.choices(package: package, originCode: "A", destinationCode: "E")
        #expect(choices.map { $0.stations.map(\.code) } == [["A", "B", "C", "D", "E"]])
    }

    @Test("A common family name cannot establish a chain of cross-row junctions")
    func longSplitFamily() throws {
        let package = try fixture([
            line("first", stations: ["A", "B"]), line("second", stations: ["B", "C"]),
            line("third", stations: ["C", "D"]), line("fourth", stations: ["D", "E"]),
        ])
        #expect(RailwayRouteChoices.choices(
            package: package, originCode: "A", destinationCode: "E").isEmpty)
    }

    @Test("Hakodate candidates cannot claim complete branch topology from common station IDs")
    func hakodateConnections() throws {
        let package = try PortFixtures.package(country: "jp")
        let main = "jp-北海道旅客鉄道-函館線"
        let choices = RailwayRouteChoices.choices(
            package: package, originCode: "000455", destinationCode: "000412")
        #expect(choices.count == 1)
        #expect(choices.first?.lineIDs == [main])
        #expect(RailwayRouteChoices.choices(
            package: package, originCode: "000455", destinationCode: "000412",
            excludingStationCodes: ["000429", "000426"]).isEmpty)
    }

    @Test("Every generated physical interval survives save/import/export and reaches AI input",
          arguments: ["jp-東日本旅客鉄道-東海道線", "jp-東日本旅客鉄道-総武線-3"])
    func selectedIntervalsRoundTrip(lineID: String) throws {
        let choice = try #require(RailwayRouteChoices.choices(
            package: try PortFixtures.package(country: "jp"),
            originCode: "003766", destinationCode: "004095", trainType: "local")
            .first { $0.lineIDs == [lineID] })
        var stops = choice.stations.enumerated().map { index, visit in
            Stop(name: visit.name, n02StationCode: visit.code,
                 stopType: index == 0 ? "origin" : index == choice.stations.count - 1
                    ? "destination" : "pass_through", rideSegment: true)
        }
        stops[0].departure = "09:00"
        stops[stops.count - 1].arrival = "09:20"
        let draft = Train(
            id: "ordinary-physical-route", date: "2026-09-30", number: "Local",
            trainType: "local", origin: "東京", destination: "品川",
            routeSections: choice.routeSections, stops: stops, region: "jp")
        let saved = TrainValidation.normalizeExportTrain(draft)
        let encoded = try JSONEncoder().encode(saved)
        let reopened = try JSONDecoder().decode(Train.self, from: encoded)
        let json = try TrainValidation.JSON.parse(String(decoding: encoded, as: UTF8.self))
        let imported = try TrainValidation.normalizeImportedTrain(json)
        let exportedAgain = TrainValidation.normalizeExportTrain(imported)
        var workspace = StoreOperations.Workspace()
        #expect(StoreOperations.addTrain(draft, in: &workspace) == .trainCollectionChanged)
        let archive = StoreOperations.exportTrainStore(workspace)
        let archived = try #require(try JSONDecoder().decode(TrainStore.self, from: Data(archive.utf8)).trains.first)
        var restoredWorkspace = StoreOperations.Workspace()
        try StoreOperations.appendImportedTrain(StoreOperations.json(archived), in: &restoredWorkspace)
        let restored = try #require(restoredWorkspace.trains.first)
        for train in [saved, reopened, imported, exportedAgain, archived, restored] {
            let sections = try #require(train.routeSections)
            #expect(sections.count == choice.stations.count - 1)
            #expect(sections.map { $0.lineIDs ?? [] } == choice.sectionCodes.map { _ in [lineID] })
            #expect(sections.flatMap { $0.sectionCodes ?? [] } == choice.sectionCodes)
            #expect(sections.allSatisfy { $0.sectionCodes?.count == 1 })
            #expect(train.stops.first?.departure == "09:00")
            #expect(train.stops.last?.arrival == "09:20")
            #expect(train.stops.dropFirst().dropLast().allSatisfy {
                $0.arrival == nil && $0.departure == nil && $0.stopType == "pass_through"
            })
            let prompt = try JourneyCompletion.prompt(trains: [train], eligible: { _ in true })
            let input = try #require(prompt.components(separatedBy: "Input JSON:\n").last)
            let payload = try #require(try JSONSerialization.jsonObject(with: Data(input.utf8)) as? [String: Any])
            let rows = try #require(payload["trains"] as? [[String: Any]])
            let inputSections = try #require(rows.first?["route_sections"] as? [[String: Any]])
            #expect(inputSections.count == choice.sectionCodes.count)
            for (index, section) in inputSections.enumerated() {
                #expect(section["line_ids"] as? [String] == [lineID])
                #expect(section["section_codes"] as? [String] == [choice.sectionCodes[index]])
                #expect(section["from_index"] as? Int == index)
                #expect(section["to_index"] as? Int == index + 1)
            }
        }
    }

    @Test("Repeated station codes cannot skip to another occurrence in the same row", arguments: [false, true])
    func repeatedStationOccurrence(reverse: Bool) throws {
        var repeated = line("repeat", stations: ["A", "B", "C", "B", "D"])
        repeated["permittedTraversal"] = reverse ? "reverse" : "forward"
        let origin = reverse ? "D" : "A", destination = reverse ? "A" : "D"
        let package = try fixture([
            repeated, line("unrelated", stations: ["X", "Y"]),
        ])
        let choices = RailwayRouteChoices.choices(package: package, originCode: origin, destinationCode: destination)
        #expect(choices.count == 1)
        let choice = try #require(choices.first)
        let stations = ["A", "B", "C", "B", "D"]
        let codes = ["repeat@A:B", "repeat@B:C~1", "repeat@B:C~2", "repeat@B:D"]
        #expect(choice.stations.map(\.code) == (reverse ? Array(stations.reversed()) : stations))
        #expect(choice.sectionCodes == (reverse ? Array(codes.reversed()) : codes))
        #expect(RailwayRouteChoices.choices(
            package: package, originCode: origin, destinationCode: destination,
            excludingStationCodes: ["C"]).isEmpty)
    }

    @Test("A one-coordinate interval cannot be selected directly or through a split family")
    func missingPhysicalInterval() throws {
        var broken = line("broken", stations: ["A", "B"])
        broken["segments"] = [[1, 0, [[0, 0]]] as [Any]]
        let package = try fixture([broken, line("continuation", stations: ["B", "C"])])
        #expect(RailwayRouteChoices.choices(package: package, originCode: "A", destinationCode: "B").isEmpty)
        #expect(RailwayRouteChoices.choices(package: package, originCode: "A", destinationCode: "C").isEmpty)
    }

    @Test("Paired direction metadata does not itself prove a junction to its parent line")
    func explicitSelectionPolicy() throws {
        var paired = line("paired", stations: ["B", "C"])
        paired["alignmentOf"] = "trunk"
        paired["alignmentDirection"] = "down"
        paired["stationOrderDirection"] = "down"
        let package = try fixture([line("trunk", stations: ["A", "B"]), paired])
        #expect(RailwayRouteChoices.choices(
            package: package, originCode: "A", destinationCode: "C").isEmpty)
        #expect(RailwayRouteChoices.choices(
            package: package, originCode: "C", destinationCode: "B").isEmpty)
        #expect(RailwayRouteChoices.choices(
            package: package, originCode: "B", destinationCode: "C").count == 1)
    }

    @Test("Deep row slices enumerate their intervals without recursive station calls")
    func deepSplitFamily() throws {
        let codes = (0...2048).map { "deep-\($0)" }
        func point(_ code: String) -> [Double] {
            [139 + Double(Int(code.dropFirst(5))!) * 0.00001, 35]
        }
        func row(_ id: String, _ visits: [String]) -> [String: Any] {
            ["id": id, "name": "Deep physical family", "operator": "Operator", "rank": 3,
             "stations": visits.map { [$0, $0, point($0)[0], point($0)[1]] as [Any] },
             "segments": (0..<(visits.count - 1)).map {
                 [1, 0, [point(visits[$0]), point(visits[$0 + 1])]] as [Any]
             }]
        }
        let package = try fixture([
            row("whole", codes),
        ])
        let choices = RailwayRouteChoices.choices(
            package: package, originCode: codes[0], destinationCode: codes[2048])
        #expect(choices.count == 1)
        let choice = try #require(choices.first)
        #expect(choice.stations.map(\.code) == codes)
        #expect(choice.sectionCodes.count == 2048)
        #expect(choice.lineIDs == ["whole"])
        #expect(choice.routeSections.map { $0.lineIDs ?? [] } ==
            Array(repeating: ["whole"], count: 2048))
    }

    private func line(_ id: String, stations: [String], loop: Bool = false) -> [String: Any] {
        ["id": id, "name": "Physical family", "operator": "Operator", "rank": 3, "isLoop": loop,
         "stations": stations.enumerated().map { [$0.element, $0.element, Double($0.offset), 0] as [Any] },
         "segments": (0..<(loop ? stations.count : stations.count - 1)).map {
             [1, 0, [[Double($0), 0], [Double($0 + 1), 0]]] as [Any]
         }]
    }

    private func fixture(_ lines: [[String: Any]]) throws -> CompactPackage {
        let data = try JSONSerialization.data(withJSONObject: [
            "format": "compact-v1", "version": "test", "country": "jp", "lines": lines])
        return try JSONDecoder().decode(CompactPackage.self, from: data)
    }
}
