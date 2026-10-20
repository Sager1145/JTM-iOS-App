import Foundation
import Testing
@testable import RailCore

struct RecordedRouteAdmissionTests {
    @Test("Existing authored physical selections remain guide-only when inference is rerun")
    func authoredSelectionCannotBecomeInference() throws {
        let package = try JSONDecoder().decode(CompactPackage.self, from: Data(#"{"format":"compact-v1","version":"test","country":"jp","lines":[{"id":"ordinary","name":"Rail","operator":"Operator","rank":3,"kind":"jr_conventional","stations":[["A","A",139,35],["B","B",139.02,35]],"segments":[[1,0,[[139,35],[139.02,35]]]]}]}"#.utf8))
        let authored = Train(id: "authored", number: "Local", origin: "A", destination: "B",
            routeSections: [RouteSection(fromN02StationCode: "A", toN02StationCode: "B",
                lineIDs: ["ordinary"], sectionCodes: ["ordinary@A:B"])],
            stops: [Stop(name: "A", n02StationCode: "A"), Stop(name: "B", n02StationCode: "B")], region: "jp")
        let search = RecordedRouteAdmission.search(in: authored, package: package)
        #expect(search.choices.count == 1)
        #expect(RecordedRouteAdmission.uniqueChoice(for: search) == nil)
        let outcome = RecordedRouteAdmission.admission(in: authored, package: package)
        #expect(outcome.automaticChoice == nil)
        #expect(outcome.choices.first?.sectionCodes == ["ordinary@A:B"])
        #expect(outcome.choices.first?.routeSections.first?.sectionCodesOrigin == nil)
    }

    @Test("Automatic materialization retains inferred origin while guide selections remain authored")
    func automaticAndPassengerSelections() throws {
        let package = try JSONDecoder().decode(CompactPackage.self, from: Data(#"{"format":"compact-v1","version":"test","country":"jp","lines":[{"id":"ordinary","name":"Rail","operator":"Operator","rank":3,"kind":"jr_conventional","stations":[["A","A",139,35],["X","X",139.01,35],["B","B",139.02,35]],"segments":[[1,0,[[139,35],[139.01,35]]],[1,0,[[139.01,35],[139.02,35]]]]}]}"#.utf8))
        let train = RailwayRouteEditing.preparing(Train(id: "admission", number: "Local",
            origin: "A", destination: "B", stops: [
                Stop(name: "A", n02StationCode: "A", departure: "10:00"),
                Stop(name: "B", n02StationCode: "B", arrival: "10:15")], region: "jp"))
        let admission = RecordedRouteAdmission.admission(in: train, package: package)
        let automatic = try #require(admission.automaticChoice)
        let automaticPlan = try #require(RailwayRouteEditing.plan(train: train, choice: automatic))
        let saved = TrainValidation.normalizeExportTrain(automaticPlan.updatedTrain)
        let reopened = try JSONDecoder().decode(Train.self, from: JSONEncoder().encode(saved))
        #expect(reopened.routeSections?.allSatisfy { $0.sectionCodesOrigin == .packageInference } == true)
        #expect(reopened.stops.first?.departure == "10:00")
        #expect(reopened.stops.last?.arrival == "10:15")
        #expect(automaticPlan.undo.restore(in: automaticPlan.updatedTrain) == train)

        let passengerChoice = try #require(admission.choices.first)
        let selected = try #require(RailwayRouteEditing.plan(train: train, choice: passengerChoice))
        #expect(selected.updatedTrain.routeSections?.allSatisfy { $0.sectionCodesOrigin == nil } == true)
    }
}

extension RecordedRouteAdmissionTests {
    @Test("Every authored intermediate stop anchors its own shortest leg")
    func anchors() throws {
        let package = try fixture([
            line("direct", ["A", "D"], [1]),
            line("anchored", ["A", "B", "C", "D"], [1, 1, 3]),
        ])
        let choice = try #require(RecordedRouteAdmission.search(in: train(["A", "C", "D"]), package: package).choices.first)
        #expect(choice.stations.map(\.code) == ["A", "B", "C", "D"])
        #expect(choice.routeSections.count == 3)
        #expect(choice.sectionCodes == ["anchored@A:B", "anchored@B:C", "anchored@C:D"])
    }

    @Test("Compatible line families do not establish physical continuation")
    func differentFamilies() throws {
        let package = try fixture([
            line("first", ["A", "B"], [2]), line("second", ["B", "C"], [3]),
        ])
        #expect(RecordedRouteAdmission.search(in: train(["A", "C"]), package: package).choices.isEmpty)
    }

    @Test("Physical segment mileage chooses the shortest competing alignment deterministically")
    func shortest() throws {
        let short = line("z-short", ["A", "X", "D"], [1, 1])
        let long = line("a-long", ["A", "Y", "D"], [3, 3])
        for rows in [[short, long], [long, short]] {
            let choice = try #require(RecordedRouteAdmission.search(in: train(["A", "D"]), package: fixture(rows)).choices.first)
            #expect(choice.lineIDs == ["z-short"])
            #expect(choice.stations.map(\.code) == ["A", "X", "D"])
        }
    }

    @Test("Unresolved and disconnected stops do not produce proposals or proximity transfers")
    func unresolved() throws {
        let package = try fixture([line("a", ["A", "B"], [1]), line("b", ["X", "D"], [1])])
        #expect(RecordedRouteAdmission.search(in: train(["A", "D"]), package: package).choices.first == nil)
        #expect(RecordedRouteAdmission.search(in: train(["A", "missing"]), package: package).choices.first == nil)
        var draft = train(["A", "B"])
        draft.stops[1].n02StationCode = nil
        #expect(RecordedRouteAdmission.search(in: draft, package: package).choices.first == nil)
    }

    @Test("Source traversal direction is enforced")
    func direction() throws {
        var forward = line("forward", ["A", "B", "C"], [1, 1])
        forward["permittedTraversal"] = "forward"
        let package = try fixture([forward])
        #expect(RecordedRouteAdmission.search(in: train(["A", "C"]), package: package).choices.first?.stations.map(\.code) == ["A", "B", "C"])
        #expect(RecordedRouteAdmission.search(in: train(["C", "A"]), package: package).choices.first == nil)
    }

    @Test("Repeated station occurrences cannot skip physical intervals")
    func occurrences() throws {
        var forward = line("repeat", ["A", "B", "C", "B", "D"], [1, 1, 1, 1])
        forward["permittedTraversal"] = "forward"
        var branch = line("branch", ["B", "X"], [10])
        branch["permittedTraversal"] = "forward"
        let choice = try #require(RecordedRouteAdmission.search(in: train(["A", "B", "D"]), package: fixture([forward, branch])).choices.first)
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
        #expect(RecordedRouteAdmission.search(in: draft, package: package).choices.count == 2)
        #expect(RecordedRouteAdmission.admission(in: draft, package: package).automaticChoice == nil)
        draft.routePolicy = nil
        draft.routeSections = [RouteSection(fromN02StationCode: "A", toN02StationCode: "D", lineIDs: ["preferred"])]
        #expect(RecordedRouteAdmission.search(in: draft, package: package).choices.first?.lineIDs == ["preferred"])
        draft.routeSections?[0].lineIDs = ["missing"]
        #expect(!RecordedRouteAdmission.search(in: draft, package: package).choices.isEmpty)
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
        let result = RecordedRouteAdmission.search(in: draft, package: package)
        #expect(result.choices.isEmpty)
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
        #expect(RecordedRouteAdmission.search(in: draft, package: package).choices.first == nil)
    }

    @Test("High speed eligibility and service exceptions prevent incompatible physical proposals")
    func eligibility() throws {
        var high = line("high", ["A", "D"], [1])
        high["kind"] = "high_speed"
        var suspended = line("suspended", ["A", "D"], [0.1])
        suspended["serviceStatus"] = "substitute_bus"
        let package = try fixture([high, suspended, line("ordinary", ["A", "B", "D"], [2, 2])])
        #expect(RecordedRouteAdmission.search(in: train(["A", "D"]), package: package).choices.first?.lineIDs == ["ordinary"])
        var draft = train(["A", "D"])
        draft.trainType = "shinkansen"
        #expect(RecordedRouteAdmission.search(in: draft, package: package).choices.first?.lineIDs == ["high"])
    }

    @Test("Legal line labels relax to physical branch rows as reviewable candidates")
    func relaxedLineLabels() throws {
        try RegistryIdentityTestGate.withProvider({ region in
            guard region == "jp" else { return nil }
            return RegistryIdentity(bundle: RegistryBundle(region: "jp", run: 1, operatorRecords: [
                "op:jp:1": RegistryOperatorRecord(names: ["Operator"], label: "Operator"),
                "op:jp:2": RegistryOperatorRecord(names: ["Other"], label: "Other"),
            ]))
        }) {
            try relaxedLineLabelsBody()
        }
    }

    private func relaxedLineLabelsBody() throws {
        let package = try fixture([line("Branch", ["A", "B"], [1])])
        var draft = train(["A", "B"])
        draft.routeSections = [RouteSection(fromN02StationCode: "A", toN02StationCode: "B",
            lineNames: ["Legal"], operatorNames: ["Operator"], lineIDs: ["legal-id"],
            sectionCodes: ["legal-section"])]
        let result = RecordedRouteAdmission.search(in: draft, package: package)
        #expect(result.choices.first?.lineIDs == ["Branch"])
        #expect(!result.topologyIsComplete)
        #expect(result.relaxedLineConstraints)
        #expect(RecordedRouteAdmission.uniqueChoice(for: result) == nil)
        #expect(RecordedRouteAdmission.admission(in: draft, package: package).automaticChoice == nil)
        draft.routeSections?[0].operatorNames = ["Other"]
        #expect(RecordedRouteAdmission.search(in: draft, package: package).choices.first == nil)
    }

    @Test("Pending registry leaves an operator mismatch unresolved")
    func pendingOperatorDoesNotReject() throws {
        try RegistryIdentityLookup.withTestPhase({ region in
            region == "jp" ? .pending : .unavailable
        }) {
            let package = try fixture([line("Branch", ["A", "B"], [1])])
            var draft = train(["A", "B"])
            draft.routeSections = [RouteSection(
                fromN02StationCode: "A", toN02StationCode: "B",
                lineNames: ["Legal"], operatorNames: ["Other"], lineIDs: ["legal-id"],
                sectionCodes: ["legal-section"])]
            #expect(RecordedRouteAdmission.search(in: draft, package: package).choices.first?.lineIDs == ["Branch"])
        }
    }

    @Test("A ride whose company does not convert still admits lines")
    func unconvertibleCompanyStillAdmitsLines() throws {
        try RegistryIdentityTestGate.withProvider({ region in
            guard region == "jp" else { return nil }
            return RegistryIdentity(bundle: RegistryBundle(region: "jp", run: 1, operatorRecords: [
                "op:jp:1": RegistryOperatorRecord(names: ["Operator"], label: "Operator"),
            ]))
        }) {
            let package = try fixture([line("Branch", ["A", "B"], [1])])
            var draft = train(["A", "B"])
            draft.routeSections = [RouteSection(
                fromN02StationCode: "A", toN02StationCode: "B",
                lineNames: ["Legal"], operatorNames: ["架空鉄道"], lineIDs: ["legal-id"],
                sectionCodes: ["legal-section"])]
            #expect(RecordedRouteAdmission.search(in: draft, package: package).choices.first?.lineIDs == ["Branch"])
        }
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
            #expect(!RecordedRouteAdmission.search(in: train(["A", "B"]), package: package).choices.isEmpty == traversable)
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
        let choice = try #require(RecordedRouteAdmission.search(in: original, package: package).choices.first)
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
        try RegistryIdentityTestGate.withProvider({ region in
            guard region == "jp" else { return nil }
            return RegistryIdentity(bundle: RegistryBundle(region: "jp", run: 1, operatorRecords: [
                "op:jp:east": RegistryOperatorRecord(
                    names: ["JR東日本", "東日本旅客鉄道"], label: "JR東日本", identity: "jp.jr-east"),
                "op:jp:central": RegistryOperatorRecord(
                    names: ["JR東海"], label: "JR東海", identity: "jp.jr-central"),
            ]))
        }) {
            try operatorAliasBody()
        }
    }

    private func operatorAliasBody() throws {
        var row = line("joban", ["A", "X", "B"], [1, 1])
        row["operator"] = "東日本旅客鉄道"
        let package = try fixture([row])
        var draft = train(["A", "B"])
        draft.routeSections = [RouteSection(fromN02StationCode: "A", toN02StationCode: "B",
            operatorNames: ["JR東日本"], lineIDs: ["joban"])]
        draft.routePolicy = RoutePolicy(preferredOperatorNames: ["JR東日本"])
        #expect(RecordedRouteAdmission.search(in: draft, package: package).choices.first?.stations.map(\.code) == ["A", "X", "B"])
        draft.routeSections?[0].operatorNames = ["JR東海"]
        #expect(RecordedRouteAdmission.search(in: draft, package: package).choices.first == nil)
    }

    @Test("A single available row cannot prove complete network uniqueness")
    func incompleteTopology() throws {
        let package = try fixture([line("single", ["A", "B", "D"], [1, 1])])
        let result = RecordedRouteAdmission.search(in: train(["A", "D"]), package: package)
        #expect(result.choices.count == 1)
        #expect(!result.isTruncated)
        #expect(!result.topologyIsComplete)
        #expect(RecordedRouteAdmission.uniqueChoice(for: result) != nil)
        #expect(RecordedRouteAdmission.admission(in: train(["A", "D"]), package: package).automaticChoice != nil)
    }

    @Test("Super Oki and Shirasagi do not gain an unreviewed cross-row path from station-group aliases")
    func superOkiAndShirasagi() throws {
        // Shirasagi's sections name 西日本旅客鉄道, the same string as the Hokuriku
        // package row. Admission compares operator ids, so the name converts here.
        // Super Oki has no section operators. Both stay empty for topology.
        try RegistryIdentityTestGate.withProvider({ region in
            guard region == "jp" else { return nil }
            return RegistryIdentity(bundle: RegistryBundle(region: "jp", run: 1, operatorRecords: [
                "op:jp:west": RegistryOperatorRecord(
                    names: ["西日本旅客鉄道", "JR西日本"], label: "JR西日本", identity: "jp.jr-west"),
            ]))
        }) {
            try superOkiAndShirasagiBody()
        }
    }

    private func superOkiAndShirasagiBody() throws {
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
            let result = RecordedRouteAdmission.search(in: train, package: package, stationAliases: aliases)
            #expect(!result.topologyIsComplete)
            // Aliases rename stops; they do not connect rows. Super Oki's 山陰線 and
            // 山口線 meet at a station with no reviewed junction. Shirasagi's first
            // 北陸線 interval is the opposite direction of the paired alignment, and
            // the paired row is not a reviewed continuation.
            #expect(result.choices.isEmpty)
            #expect(RecordedRouteAdmission.uniqueChoice(for: result) == nil)
        }
    }

    @Test("総武線-3 品川 uses the package row id for the Narita Express sample")
    func sobuTunnelShinagawaUsesThePackageRow() throws {
        let root = try PortFixtures.repositoryRoot()
        let package = try PortFixtures.package(country: "jp")
        let ids = try #require(TokyoConventionalRouteInference.tunnelStationIDs(in: package))
        let part = try JSONDecoder().decode(SamplePart.self, from: Data(contentsOf:
            root.appending(path: "app/data/sample-data/part-171.json")))
        #expect(part.train.id == "20260727_08_narita_express")
        let tokyoID = "st:jp:tokyo-corridor"
        let shinagawaID = "st:jp:shinagawa-corridor"
        let identity = RegistryIdentity(bundle: RegistryBundle(
            region: "jp", run: 1,
            stationCodes: ["003766": tokyoID, ids[2]: shinagawaID],
            stations: [
                tokyoID: RegistryStationRecord(
                    cx: "cx:1", group: "tokyo", codes: ["003766"], op: "op:jp:1",
                    name: "東京", lines: []),
                shinagawaID: RegistryStationRecord(
                    cx: "cx:2", group: "shinagawa", codes: [ids[2]], op: "op:jp:1",
                    name: "品川", lines: []),
            ]))
        try RegistryIdentityTestGate.withProvider({ region in region == "jp" ? identity : nil }) {
            let choice = try #require(TokyoConventionalRouteInference.choice(in: part.train, package: package))
            #expect(choice.lineIDs == [TokyoConventionalRouteInference.tunnelLineID])
            #expect(choice.stations.last?.code == ids[2])
            var unnamed = part.train
            unnamed.stops[0].stationID = tokyoID
            unnamed.stops[1].n02StationCode = nil
            unnamed.stops[1].stationID = shinagawaID
            unnamed.routeSections = [RouteSection(
                from: "東京", to: "品川", fromN02StationCode: "003766",
                fromStationID: tokyoID, toStationID: shinagawaID)]
            let applied = TokyoConventionalRouteInference.applying(to: unnamed, package: package)
            let section = try #require(applied.routeSections?.first)
            #expect(section.toN02StationCode == ids[2])
            #expect(section.sectionCodes?.last?.hasSuffix(":" + ids[2]) == true)
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
        let result = RecordedRouteAdmission.search(in: draft, package: package,
            stationAliases: ["a": "A", "x": "X", "b": "B"])
        #expect(result.choices.isEmpty)
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
        // One surveyed row still resolves. Rides that change package row have no
        // reviewed junction, so they stay without a proposal and cannot auto-apply.
        let singleRowIDs: Set<String> = ["20260723_03_ishizuchi10", "20260724_01_ishizuchi9"]
        let crossRowIDs: Set<String> = ["20260703_01_haruka", "20260713_07_hokuto21",
            "20260722_06_sonic44", "20260729_05_sunrise_izumo",
            "20260724_02_nanpu9", "20260724_06_nanpu28",
            "20260704_08_shonan_shinjuku_line", "20260726_09_shonan_shinjuku_yokohama"]
        let requiredIDs = singleRowIDs.union(crossRowIDs)
        var checkedIDs: Set<String> = []
        var emptyIDs: [String] = []
        var autoCompleteCount = 0
        var guideCount = 0
        for train in store.trains where train.region == "jp"
            && train.stops.allSatisfy({ !($0.n02StationCode ?? "").isEmpty }) {
            let codes = train.stops.compactMap(\.n02StationCode)
                + (train.routeSections ?? []).flatMap { [$0.fromN02StationCode, $0.toN02StationCode].compactMap { $0 } }
            let aliases = LocalJourneySearch.stationAliases(for: codes, package: package) { groups[$0] }
            // Long national rides such as Sunrise Izumo need more than the default
            // 50,000 expansions; exercise the existing supported search ceiling.
            let result = RecordedRouteAdmission.search(in: train, package: package, stationAliases: aliases,
                maximumExpansions: 200_000)
            checkedIDs.insert(train.id)
            if RecordedRouteAdmission.uniqueChoice(for: result) != nil { autoCompleteCount += 1 }
            else if !result.choices.isEmpty { guideCount += 1 }
            if result.choices.isEmpty {
                emptyIDs.append(train.id)
                print("Zero-choice \(train.id), truncated: \(result.isTruncated)")
            }
            if singleRowIDs.contains(train.id) {
                #expect(!result.choices.isEmpty, "Expected route choices for \(train.id)")
            }
            if crossRowIDs.contains(train.id) {
                #expect(result.choices.isEmpty, "Unreviewed cross-row ride \(train.id) must stay without a proposal")
                #expect(RecordedRouteAdmission.uniqueChoice(for: result) == nil)
            }
        }
        #expect(requiredIDs.isSubset(of: checkedIDs))
        print("Auto-complete: \(autoCompleteCount); guide: \(guideCount)")
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

    /// A run of same-line sections is resolved whole so a later via can
    /// decide an earlier branch. When the whole run has no answer, a leg the
    /// station database resolves uniquely on its own still needs no solver.
    @Test("Legs of an unsupported station run still infer from the station database")
    func unsupportedRunFallsBackToLegs() throws {
        let root = try PortFixtures.repositoryRoot()
        let data = try PhysicalEndpointTrimTests().loadRealData(root: root)
        let store = try JSONDecoder().decode(TrainStore.self,
            from: Data(contentsOf: root.appending(path: "app/data/sample-data/sample-full.json")))
        let train = try #require(store.trains.first { $0.id == "20260704_08_shonan_shinjuku_line" })
        let sections = try #require(train.routeSections)
        // The institutions the app itself allows for this journey.
        let allowedCodes = RouteGraph.allowedInstitutionTypeCodes(RouteGraph.CacheKeyTrain(
            trainType: train.trainType ?? "", company: train.company ?? "",
            preferredLineNames: [], preferredOperatorNames: [],
            allowedInstitutionTypeCodes: nil, institutionFilterMode: nil), country: "jp")
        let inferred = RouteSolver.inferStationSections(sections, resolver: data.resolver,
            network: data.network, eligibility: data.eligibility, allowedCodes: allowedCodes, hard: false)
        var legsResolvedAlone = 0
        var permittedInferences = 0
        for (index, section) in sections.enumerated() {
            let lineIDs = section.lineIDs ?? []
            let lineNames = section.lineNames ?? []
            let operatorNames = section.operatorNames ?? []
            guard let from = data.eligibility.stationCode(section.fromN02StationCode),
                  let to = data.eligibility.stationCode(section.toN02StationCode),
                  case .resolved = data.resolver.resolve(
                    stationCodes: [from, to], requiredLineIDs: lineIDs,
                    requiredLineNames: lineNames, requiredOperatorNames: operatorNames)
            else { continue }
            legsResolvedAlone += 1
            // A display family that fails the source check stays with the
            // solver. Inferring it here would replace dated geometry with today.
            let candidates = data.resolver.candidateLineIDs(
                requiredLineIDs: lineIDs, requiredLineNames: lineNames,
                requiredOperatorNames: operatorNames) ?? []
            let permitted = !candidates.isEmpty && data.network.lines.filter {
                candidates.contains($0.lineId)
            }.allSatisfy {
                data.eligibility.permits($0, allowedInstitutionCodes: allowedCodes, hard: false)
            }
            guard permitted else { continue }
            let hints = try #require(inferred.hints[index])
            #expect(data.network.sourceCertification(for: hints) != nil)
            permittedInferences += 1
        }
        #expect(legsResolvedAlone > 0)
        #expect(permittedInferences > 0)
    }
}

private struct SamplePart: Decodable {
    let train: Train
}
