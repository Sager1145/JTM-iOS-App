import Foundation
import Testing
@testable import RailCore

struct RailwayRouteInferenceTests {
    @Test("Every authored intermediate stop anchors its own shortest leg")
    func anchors() throws {
        let package = try fixture([
            line("direct", ["A", "D"], [1]),
            line("anchored", ["A", "B", "C", "D"], [1, 1, 3]),
        ])
        let choice = try #require(RailwayRouteInference.search(in: train(["A", "C", "D"]), package: package).choices.first)
        #expect(choice.stations.map(\.code) == ["A", "B", "C", "D"])
        #expect(choice.routeSections.count == 3)
        #expect(choice.sectionCodes == ["anchored@A:B", "anchored@B:C", "anchored@C:D"])
    }

    @Test("Compatible line families yield reviewable shared-station candidates")
    func differentFamilies() throws {
        let package = try fixture([
            line("first", ["A", "B"], [2]), line("second", ["B", "C"], [3]),
        ])
        #expect(RailwayRouteInference.search(in: train(["A", "C"]), package: package).choices.first?.lineIDs == ["first", "second"])
    }

    @Test("Physical segment mileage chooses the shortest competing alignment deterministically")
    func shortest() throws {
        let short = line("z-short", ["A", "X", "D"], [1, 1])
        let long = line("a-long", ["A", "Y", "D"], [3, 3])
        for rows in [[short, long], [long, short]] {
            let choice = try #require(RailwayRouteInference.search(in: train(["A", "D"]), package: fixture(rows)).choices.first)
            #expect(choice.lineIDs == ["z-short"])
            #expect(choice.stations.map(\.code) == ["A", "X", "D"])
        }
    }

    @Test("Unresolved and disconnected stops do not produce proposals or proximity transfers")
    func unresolved() throws {
        let package = try fixture([line("a", ["A", "B"], [1]), line("b", ["X", "D"], [1])])
        #expect(RailwayRouteInference.search(in: train(["A", "D"]), package: package).choices.first == nil)
        #expect(RailwayRouteInference.search(in: train(["A", "missing"]), package: package).choices.first == nil)
        var draft = train(["A", "B"])
        draft.stops[1].n02StationCode = nil
        #expect(RailwayRouteInference.search(in: draft, package: package).choices.first == nil)
    }

    @Test("Source traversal direction is enforced")
    func direction() throws {
        var forward = line("forward", ["A", "B", "C"], [1, 1])
        forward["permittedTraversal"] = "forward"
        let package = try fixture([forward])
        #expect(RailwayRouteInference.search(in: train(["A", "C"]), package: package).choices.first?.stations.map(\.code) == ["A", "B", "C"])
        #expect(RailwayRouteInference.search(in: train(["C", "A"]), package: package).choices.first == nil)
    }

    @Test("Repeated station occurrences cannot skip physical intervals")
    func occurrences() throws {
        var forward = line("repeat", ["A", "B", "C", "B", "D"], [1, 1, 1, 1])
        forward["permittedTraversal"] = "forward"
        var branch = line("branch", ["B", "X"], [10])
        branch["permittedTraversal"] = "forward"
        let choice = try #require(RailwayRouteInference.search(in: train(["A", "B", "D"]), package: fixture([forward, branch])).choices.first)
        #expect(choice.stations.map(\.code) == ["A", "B", "C", "B", "D"])
        #expect(choice.sectionCodes == ["repeat@A:B", "repeat@B:C~1", "repeat@B:C~2", "repeat@B:D"])
    }

    @Test("Explicit sections and feasible preferred lines override competing alignments")
    func hints() throws {
        let package = try fixture([
            line("short", ["A", "X", "D"], [1, 1]),
            line("preferred", ["A", "Y", "D"], [3, 3]),
        ])
        var draft = train(["A", "D"])
        draft.routePolicy = RoutePolicy(preferredLineNames: ["preferred"])
        #expect(RailwayRouteInference.search(in: draft, package: package).choices.count == 2)
        #expect(RailwayRouteInference.choice(in: draft, package: package) == nil)
        draft.routePolicy = nil
        draft.routeSections = [RouteSection(fromN02StationCode: "A", toN02StationCode: "D", lineIDs: ["preferred"])]
        #expect(RailwayRouteInference.search(in: draft, package: package).choices.first?.lineIDs == ["preferred"])
        draft.routeSections?[0].lineIDs = ["missing"]
        #expect(!RailwayRouteInference.search(in: draft, package: package).choices.isEmpty)
    }

    @Test("Authored cross-line boundaries constrain reviewable transfer candidates")
    func nonCallBoundary() throws {
        let package = try fixture([
            line("first", ["A", "P", "X"], [2, 2]),
            line("second", ["X", "Q", "B"], [2, 2]),
            line("shortcut", ["A", "B"], [1]),
        ])
        var draft = train(["A", "P", "B"])
        draft.routeSections = [
            RouteSection(fromN02StationCode: "A", toN02StationCode: "X", lineIDs: ["first"]),
            RouteSection(fromN02StationCode: "X", toN02StationCode: "B", lineIDs: ["second"]),
        ]
        let result = RailwayRouteInference.search(in: draft, package: package)
        #expect(result.choices.first?.lineIDs == ["first", "second"])
        #expect(!result.topologyIsComplete)
    }

    @Test("Non-call boundaries cannot discard an authored stop or relax a known line chain")
    func boundaryAnchorConflict() throws {
        let package = try fixture([
            line("first", ["A", "X"], [1]), line("second", ["X", "B"], [1]),
            line("other", ["A", "P", "B"], [1, 1]),
        ])
        var draft = train(["A", "P", "B"])
        draft.routeSections = [
            RouteSection(fromN02StationCode: "A", toN02StationCode: "X", lineIDs: ["first"]),
            RouteSection(fromN02StationCode: "X", toN02StationCode: "B", lineIDs: ["second"]),
        ]
        #expect(RailwayRouteInference.search(in: draft, package: package).choices.first == nil)
    }

    @Test("High speed eligibility and service exceptions prevent incompatible physical proposals")
    func eligibility() throws {
        var high = line("high", ["A", "D"], [1])
        high["kind"] = "high_speed"
        var suspended = line("suspended", ["A", "D"], [0.1])
        suspended["serviceStatus"] = "substitute_bus"
        let package = try fixture([high, suspended, line("ordinary", ["A", "B", "D"], [2, 2])])
        #expect(RailwayRouteInference.search(in: train(["A", "D"]), package: package).choices.first?.lineIDs == ["ordinary"])
        var draft = train(["A", "D"])
        draft.trainType = "shinkansen"
        #expect(RailwayRouteInference.search(in: draft, package: package).choices.first?.lineIDs == ["high"])
    }

    @Test("Legal line labels relax to physical branch rows as reviewable candidates")
    func relaxedLineLabels() throws {
        let package = try fixture([line("Branch", ["A", "B"], [1])])
        var draft = train(["A", "B"])
        draft.routeSections = [RouteSection(fromN02StationCode: "A", toN02StationCode: "B",
            lineNames: ["Legal"], operatorNames: ["Operator"], lineIDs: ["legal-id"],
            sectionCodes: ["legal-section"])]
        let result = RailwayRouteInference.search(in: draft, package: package)
        #expect(result.choices.first?.lineIDs == ["Branch"])
        #expect(!result.topologyIsComplete)
        #expect(result.uniqueChoice == nil)
        draft.routeSections?[0].operatorNames = ["Other"]
        #expect(RailwayRouteInference.search(in: draft, package: package).choices.isEmpty)
    }

    @Test("Partial service statuses remain searchable but whole-line substitute buses do not")
    func partialServiceSearch() throws {
        for status in ["partial_all_trains_pass", "partial_substitute_bus",
                       "partial_service_suspended", "partial_no_passenger_train", "suspended",
                       "substitute_bus"] {
            var row = line("row", ["A", "B"], [1])
            row["serviceStatus"] = status
            let package = try fixture([row])
            let traversable = status != "substitute_bus"
            #expect(!RailwayRouteInference.search(in: train(["A", "B"]), package: package).choices.isEmpty == traversable)
            #expect(!RailwayRouteChoices.choices(package: package, originCode: "A", destinationCode: "B").isEmpty == traversable)
        }
    }

    @Test("Applying and undoing an inferred route restores exact non-call source boundaries and clocks")
    func boundaryUndo() throws {
        let package = try fixture([
            line("whole", ["A", "P", "X", "Q", "B"], [1, 1, 1, 1]),
        ])
        var draft = train(["A", "P", "B"])
        draft.stops[0].departure = "10:00"
        draft.stops[1].arrival = "10:10"
        draft.stops[1].departure = "10:12"
        draft.stops[2].arrival = "10:30"
        draft.routeSections = [
            RouteSection(fromN02StationCode: "A", toN02StationCode: "X", lineIDs: ["whole"]),
            RouteSection(fromN02StationCode: "X", toN02StationCode: "B", lineIDs: ["whole"]),
        ]
        let original = RailwayRouteEditing.preparing(draft)
        let choice = try #require(RailwayRouteInference.search(in: original, package: package).choices.first)
        let plan = try #require(RailwayRouteEditing.plan(train: original, choice: choice,
            fromVisitID: original.stops.first?.routeEditing?.visitID,
            toVisitID: original.stops.last?.routeEditing?.visitID))
        #expect(!plan.requiresConfirmation)
        #expect(plan.updatedTrain.stops.map(\.name) == ["A", "P", "X", "Q", "B"])
        #expect(plan.updatedTrain.stops[1].arrival == "10:10")
        #expect(plan.updatedTrain.stops[1].departure == "10:12")
        #expect(plan.updatedTrain.stops[2].stopType == "pass_through")
        #expect(plan.updatedTrain.stops[2].arrival == nil)
        #expect(plan.undo.restore(in: plan.updatedTrain) == original)
    }

    @Test("Published JR operator labels match their physical package company identities")
    func operatorAlias() throws {
        var row = line("joban", ["A", "X", "B"], [1, 1])
        row["operator"] = "東日本旅客鉄道"
        let package = try fixture([row])
        var draft = train(["A", "B"])
        draft.routeSections = [RouteSection(fromN02StationCode: "A", toN02StationCode: "B",
            operatorNames: ["JR東日本"], lineIDs: ["joban"])]
        draft.routePolicy = RoutePolicy(preferredOperatorNames: ["JR東日本"])
        #expect(RailwayRouteInference.search(in: draft, package: package).choices.first?.stations.map(\.code) == ["A", "X", "B"])
        draft.routeSections?[0].operatorNames = ["JR東海"]
        #expect(RailwayRouteInference.search(in: draft, package: package).choices.first == nil)
    }

    @Test("A single available row cannot prove complete network uniqueness")
    func incompleteTopology() throws {
        let package = try fixture([line("single", ["A", "B", "D"], [1, 1])])
        let result = RailwayRouteInference.search(in: train(["A", "D"]), package: package)
        #expect(result.choices.count == 1)
        #expect(!result.isTruncated)
        #expect(!result.topologyIsComplete)
        #expect(result.uniqueChoice == nil)
        #expect(RailwayRouteInference.choice(in: train(["A", "D"]), package: package) == nil)
    }

    @Test("Super Oki and Shirasagi infer routes using real N02 station-group aliases")
    func superOkiAndShirasagi() throws {
        let root = try PortFixtures.repositoryRoot()
        let package = try CompactPackage.load(contentsOf: root.appending(path: "app/public/rail/jp-2025.json"))
        let store = try JSONDecoder().decode(TrainStore.self,
            from: Data(contentsOf: root.appending(path: "app/data/sample-data/sample-full.json")))
        let stations = try Stations.FeatureCollection.load(contentsOf: root.appending(path: "app/data/stations.json"))
        var groups: [String: String] = [:]
        for feature in stations.features {
            if let code = Stations.stationCode(feature), let group = Stations.stationGroupCode(feature) {
                groups[code] = group
            }
        }
        for id in ["20260719_03_super_oki5", "20260708_02_shirasagi2"] {
            let train = try #require(store.trains.first { $0.id == id })
            let aliases = LocalJourneySearch.stationAliases(for: train.stops.compactMap(\.n02StationCode),
                package: package) { groups[$0] }
            let result = RailwayRouteInference.search(in: train, package: package, stationAliases: aliases)
            let choice = try #require(result.choices.first)
            #expect(!result.topologyIsComplete)
            if id == "20260719_03_super_oki5" {
                #expect(choice.stations.first?.code == "004759")
                #expect(choice.stations.last?.code == "008477")
                #expect(choice.lineIDs.contains("jp-西日本旅客鉄道-山陰線"))
                #expect(choice.lineIDs.contains("jp-西日本旅客鉄道-山口線"))
            }
        }
    }

    @Test("Section endpoints canonicalize non-call junction and restored visit aliases")
    func aliasedSectionBoundary() throws {
        let package = try fixture([
            line("first", ["A", "X"], [1]), line("second", ["X", "B"], [1]),
        ])
        var draft = train(["a", "b"])
        draft.routeSections = [
            RouteSection(fromN02StationCode: "A", toN02StationCode: "x", lineIDs: ["first"]),
            RouteSection(fromN02StationCode: "x", toN02StationCode: "B", lineIDs: ["second"]),
        ]
        let result = RailwayRouteInference.search(in: draft, package: package,
            stationAliases: ["a": "A", "x": "X", "b": "B"])
        #expect(result.choices.first?.stations.map(\.code) == ["a", "X", "b"])
    }

    @Test("All coded Japanese sample rides report route inference coverage")
    func allJapaneseSampleRides() throws {
        let root = try PortFixtures.repositoryRoot()
        let package = try PortFixtures.package(country: "jp")
        let store = try JSONDecoder().decode(TrainStore.self,
            from: Data(contentsOf: root.appending(path: "app/data/sample-data/sample-full.json")))
        let stations = try Stations.FeatureCollection.load(contentsOf: root.appending(path: "app/data/stations.json"))
        var groups: [String: String] = [:]
        for feature in stations.features {
            if let code = Stations.stationCode(feature), let group = Stations.stationGroupCode(feature) {
                groups[code] = group
            }
        }
        let requiredIDs: Set<String> = ["20260703_01_haruka", "20260713_07_hokuto21",
            "20260722_06_sonic44", "20260729_05_sunrise_izumo",
            "20260723_03_ishizuchi10", "20260724_01_ishizuchi9",
            "20260724_02_nanpu9", "20260724_06_nanpu28",
            "20260704_08_shonan_shinjuku_line", "20260726_09_shonan_shinjuku_yokohama"]
        var checkedIDs: Set<String> = []
        var emptyIDs: [String] = []
        for train in store.trains where train.region == "jp"
            && train.stops.allSatisfy({ !($0.n02StationCode ?? "").isEmpty }) {
            let codes = train.stops.compactMap(\.n02StationCode)
                + (train.routeSections ?? []).flatMap { [$0.fromN02StationCode, $0.toN02StationCode].compactMap { $0 } }
            let aliases = LocalJourneySearch.stationAliases(for: codes, package: package) { groups[$0] }
            // Long national rides such as Sunrise Izumo need more than the default
            // 50,000 expansions; exercise the existing supported search ceiling.
            let result = RailwayRouteInference.search(in: train, package: package, stationAliases: aliases,
                maximumExpansions: 200_000)
            checkedIDs.insert(train.id)
            if result.choices.isEmpty {
                emptyIDs.append(train.id)
                print("Zero-choice \(train.id), truncated: \(result.isTruncated)")
            }
            if requiredIDs.contains(train.id) {
                #expect(!result.choices.isEmpty, "Expected route choices for \(train.id)")
            }
        }
        #expect(requiredIDs.isSubset(of: checkedIDs))
        print("Japanese sample rides checked: \(checkedIDs.count); zero-choice rides: \(emptyIDs.sorted().joined(separator: ", "))")
    }

    private func train(_ codes: [String]) -> Train {
        Train(id: "draft", number: "Draft", origin: codes.first!, destination: codes.last!,
              stops: codes.map { Stop(name: $0, n02StationCode: $0) })
    }

    private func line(_ id: String, _ codes: [String], _ distances: [Double]) -> [String: Any] {
        ["id": id, "name": id, "operator": "Operator", "rank": 3, "kind": "jr_conventional",
         "stations": codes.enumerated().map { [$0.element, $0.element, Double($0.offset), 0] as [Any] },
         "segments": distances.enumerated().map {
             [$0.element, 0, [[Double($0.offset), 0], [Double($0.offset + 1), 0]]] as [Any]
         }]
    }

    private func fixture(_ lines: [[String: Any]]) throws -> CompactPackage {
        try JSONDecoder().decode(CompactPackage.self, from: JSONSerialization.data(withJSONObject: [
            "format": "compact-v1", "version": "test", "country": "jp", "lines": lines]))
    }
}
