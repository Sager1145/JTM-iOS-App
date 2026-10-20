import Foundation
import Testing
@testable import RailCore

@Suite("RegistrySolverInputTests", .serialized)
struct RegistrySolverInputTests {
    private let stationPattern = TrainValidation.stationIDPatternSource

    private func station(
        _ identifier: String, codes: [String], op: String, cx: String = "cx:jp:1"
    ) -> RegistryStationRecord {
        RegistryStationRecord(
            cx: cx, group: "G", codes: codes, op: op, name: identifier, lines: [])
    }

    private func identity() -> RegistryIdentity {
        RegistryIdentity(bundle: RegistryBundle(
            region: "jp", run: 1,
            stationCodes: [
                "111111": "st:jp:1", "111110": "st:jp:1",
                "222222": "st:jp:2", "003766": "st:jp:10", "004095": "st:jp:11",
            ],
            operators: [
                "op:jp:1": ["JR East Package", "東日本旅客鉄道"],
                "op:jp:2": ["Other Company"],
            ],
            stationOperator: [
                "st:jp:1": "op:jp:1", "st:jp:2": "op:jp:2",
                "st:jp:10": "op:jp:1", "st:jp:11": "op:jp:1",
            ],
            stations: [
                "st:jp:1": station("st:jp:1", codes: ["111111", "111110"], op: "op:jp:1"),
                "st:jp:2": station("st:jp:2", codes: ["222222"], op: "op:jp:2"),
                "st:jp:7": station("st:jp:7", codes: [], op: "op:jp:1"),
                "st:jp:10": station("st:jp:10", codes: ["003766"], op: "op:jp:1", cx: "cx:jp:2"),
                "st:jp:11": station("st:jp:11", codes: ["004095"], op: "op:jp:1", cx: "cx:jp:2"),
                "st:jp:4": station("st:jp:4", codes: ["111110"], op: "op:jp:1", cx: "cx:jp:2"),
            ],
            complexes: [
                "cx:jp:1": RegistryComplexRecord(
                    group: "G", name: "東京", stations: ["st:jp:1", "st:jp:2"], lon: 139, lat: 35),
            ]))
    }

    private func feature(code: String, group: String) -> Stations.Feature {
        Stations.Feature(properties: [
            "n02_station_code": .string(code),
            "n02_group_code": .string(group),
            "station_name": .string("東京"),
            "line_name": .string("山手線"),
            "operator": .string("JR East Package"),
            "institution_type_code": .string("2"),
        ])
    }

    private func stations() -> Stations.Index {
        Stations.Index([
            feature(code: "111111", group: "G"),
            feature(code: "222222", group: "G"),
            feature(code: "333333", group: "111111"),
            feature(code: "111110", group: "G"),
        ])
    }

    private func withIdentity<T>(_ body: () throws -> T) rethrows -> T {
        let identity = identity()
        return try RegistryIdentityTestGate.withProvider({ region in
            region == "jp" ? identity : nil
        }, body)
    }

    private func stop(
        _ name: String, code: String? = nil, stationID: String? = nil
    ) -> Stop {
        Stop(
            name: name, n02StationCode: code, departure: "06:00",
            stopType: "passenger_stop", rideSegment: true, stationID: stationID)
    }

    private func tokyoTrain() -> Train {
        Train(
            id: "tokyo", number: "1", company: "JR東日本",
            origin: "東京", destination: "品川",
            stops: [stop("東京"), stop("品川")],
            region: "jp")
    }

    private func rejection(_ train: Train) -> String? {
        var ids: Set<String> = []
        do {
            try TrainValidation.validateTrain(train, index: 0, ids: &ids)
            return nil
        } catch let error as TrainValidation.ValidationError {
            return error.message
        } catch {
            return String(describing: error)
        }
    }

    @Test func ownStationCodesAreTheSolverInputAndAMissingIdFailsClosed() {
        let index = stations()
        let owned = RouteSection(
            from: "東京", to: "隣",
            fromStationID: "st:jp:1", toStationID: "st:jp:2")
        #expect(RouteSolver.registryEndpointIndices(
            section: owned, country: "jp", stations: index) == nil)

        withIdentity {
            let ends = RouteSolver.registryEndpointIndices(
                section: owned, country: "jp", stations: index)
            #expect(ends?.from == [0, 3])
            #expect(ends?.to == [1])
            #expect(identity().stations(in: "cx:jp:1") == ["st:jp:1", "st:jp:2"])

            let missing = RouteSection(from: "東京", to: "隣", toStationID: "st:jp:2")
            #expect(RouteSolver.registryEndpointIndices(
                section: missing, country: "jp", stations: index) == nil)

            let stops = [
                stop("東京", code: "222222", stationID: "st:jp:1"),
                stop("無名", code: "111111"),
            ]
            #expect(SolverRegistryInput.solveInputCodes(stops: stops, region: "jp") == [
                "111111", "111110",
            ])
            #expect(SolverRegistryInput.solvableEndpointCount(stops: stops, region: "jp") == 1)
            #expect(SolverRegistryInput.graphStationCode(
                stationID: "st:jp:1", rawCode: "222222", region: "jp", eligibility: nil) == "111111")
            #expect(SolverRegistryInput.graphStationCode(
                stationID: nil, rawCode: "111111", region: "jp", eligibility: nil) == nil)
        }

        #expect(SolverRegistryInput.solveInputCodes(
            stops: [stop("東京", code: "111111")], region: "jp") == [])
        #expect(SolverRegistryInput.solvableEndpointCount(
            stops: [stop("東京", code: "111111")], region: "jp") == 0)
        #expect(SolverRegistryInput.hintedGraphStationCode(
            stationID: nil, rawCode: "111111", region: "jp", eligibility: nil) == "111111")
    }

    @Test func sectionStationIdsRoundTripValidateAndClearOnEdit() throws {
        let present = RouteSection(
            from: "A", to: "B", fromStationID: "st:jp:1", toStationID: "st:jp:2")
        let encoded = try JSONEncoder().encode(present)
        let text = String(decoding: encoded, as: UTF8.self)
        #expect(text.contains("\"from_station_id\":\"st:jp:1\""))
        #expect(text.contains("\"to_station_id\":\"st:jp:2\""))
        let decoded = try JSONDecoder().decode(RouteSection.self, from: encoded)
        #expect(decoded.fromStationID == "st:jp:1")
        #expect(decoded.toStationID == "st:jp:2")

        let absent = try JSONEncoder().encode(RouteSection(from: "A", to: "B"))
        let absentText = String(decoding: absent, as: UTF8.self)
        #expect(!absentText.contains("from_station_id"))
        #expect(!absentText.contains("to_station_id"))

        let valid = Train(
            id: "ride1", number: "1", origin: "A", destination: "B",
            routeSections: [present], stops: [stop("A"), stop("B")], region: "jp")
        #expect(rejection(valid) == nil)
        let malformed = Train(
            id: "ride1", number: "1", origin: "A", destination: "B",
            routeSections: [RouteSection(from: "A", to: "B", fromStationID: "st:jp:0")],
            stops: [stop("A"), stop("B")], region: "jp")
        #expect(rejection(malformed) == "Train 1 route section 1: from_station_id must match \(stationPattern).")
        let wrongRegion = Train(
            id: "ride1", number: "1", origin: "A", destination: "B",
            routeSections: [RouteSection(from: "A", to: "B", toStationID: "st:tw:1")],
            stops: [stop("A"), stop("B")], region: "jp")
        #expect(rejection(wrongRegion) == "Train 1 route section 1: to_station_id region must equal the train region.")

        let imported = try TrainValidation.normalizeImportedRouteSection(
            TrainValidation.JSON.parse("""
            {"from":"A","to":"B","from_station_id":"st:jp:1","to_station_id":"st:jp:2"}
            """))
        #expect(imported.fromStationID == "st:jp:1")
        #expect(imported.toStationID == "st:jp:2")
        let dropped = try TrainValidation.normalizeImportedRouteSection(
            TrainValidation.JSON.parse("""
            {"from":"A","to":"B","from_station_id":4}
            """))
        #expect(dropped.fromStationID == nil)

        let stored = StoreOperations.stringify(StoreOperations.json(present))
        #expect(stored.contains("\"from_station_id\":\"st:jp:1\""))
        #expect(!StoreOperations.stringify(StoreOperations.json(RouteSection(from: "A", to: "B")))
            .contains("station_id"))

        var edited = present
        SolverRegistryInput.renameEndpoint(&edited, from: true, name: "A")
        #expect(edited.fromStationID == "st:jp:1")
        SolverRegistryInput.renameEndpoint(&edited, from: true, name: "C")
        #expect(edited.from == "C")
        #expect(edited.fromN02StationCode == nil)
        #expect(edited.fromStationID == nil)
        #expect(edited.toStationID == "st:jp:2")
        SolverRegistryInput.assignEndpoint(&edited, from: false, name: "D", code: "333333")
        #expect(edited.to == "D")
        #expect(edited.toN02StationCode == "333333")
        #expect(edited.toStationID == nil)
    }

    @Test func operatorHintsComeFromOperatorIdsAndIgnoreSpelling() {
        let legacy = RouteSolver.inferSectionRouteConstraints(
            section: RouteSection(from: "大分", to: "小倉"),
            train: .init(trainType: "ソニック"), country: "jp")
        #expect(legacy.lineNames.contains("日豊線"))
        #expect(legacy.operatorNames.contains("九州旅客鉄道"))

        withIdentity {
            let sonic = RouteSolver.inferSectionRouteConstraints(
                section: RouteSection(from: "大分", to: "小倉"),
                train: .init(trainType: "ソニック", operatorID: "op:jp:1", region: "jp"),
                country: "jp")
            #expect(sonic.lineNames.contains("日豊線"))
            #expect(sonic.operatorNames.contains("JR East Package"))
            #expect(sonic.operatorNames.contains("東日本旅客鉄道"))
            #expect(!sonic.operatorNames.contains("九州旅客鉄道"))

            let unnamed = RouteSolver.inferSectionRouteConstraints(
                section: RouteSection(from: "大分", to: "小倉"),
                train: .init(trainType: "ソニック", region: "jp"), country: "jp")
            #expect(unnamed.lineNames.contains("日豊線"))
            #expect(!unnamed.operatorNames.contains("九州旅客鉄道"))

            let hints = RouteSolver.buildSegmentRouteHints(
                section: RouteSection(from: "東京", to: "品川", operatorNames: ["spelling-only"]),
                fromStationIndices: [], toStationIndices: [],
                stations: Stations.Index([]),
                train: .init(
                    company: "JR九州",
                    preferredOperatorNames: ["not-a-real-operator", "JR East Package", "op:jp:1"],
                    operatorID: "op:jp:1", region: "jp"),
                country: "jp")
            #expect(hints.preferredOperators.contains("JR East Package"))
            #expect(hints.preferredOperators.contains("東日本旅客鉄道"))
            #expect(!hints.preferredOperators.contains("not-a-real-operator"))
            #expect(!hints.preferredOperators.contains("spelling-only"))
            #expect(!hints.preferredOperators.contains("九州旅客鉄道"))
            #expect(!hints.requiredOperators.contains("spelling-only"))
            #expect(!hints.explicitRequiredOperators.contains("spelling-only"))
        }
    }

    @Test func homonymNamesAreNotTheSameStop() {
        let named = RouteSection(from: "A", to: "東京", toN02StationCode: "111111")
        let other = RouteSection(from: "東京", to: "B", fromN02StationCode: "222222")
        #expect(!RouteSolver.routeSectionBoundarySharesExplicitStop(named, other))
        #expect(RouteSolver.routeSectionBoundarySharesExplicitStop(
            RouteSection(from: "A", to: "東京", toN02StationCode: "111111"),
            RouteSection(from: "別", to: "B", fromN02StationCode: "111111")))
        #expect(RouteSolver.routeSectionBoundarySharesExplicitStop(
            RouteSection(toStationID: "st:jp:1"),
            RouteSection(fromStationID: "st:jp:1")))
        #expect(!RouteSolver.routeSectionBoundarySharesExplicitStop(
            RouteSection(to: "東京", toStationID: "st:jp:1"),
            RouteSection(from: "東京")))

        let homonym = stop("東京", code: "222222", stationID: "st:jp:2")
        #expect(!SolverRegistryInput.markerAgrees(declared: "東京", stop: homonym, region: "jp"))
        #expect(SolverRegistryInput.markerAgrees(declared: nil, stop: homonym, region: "jp"))
        #expect(SolverRegistryInput.markerAgrees(declared: "st:jp:2", stop: homonym, region: "jp"))
        #expect(SolverRegistryInput.markerAgrees(declared: "222222", stop: homonym, region: "jp"))

        withIdentity {
            #expect(RouteSolver.routeSectionBoundarySharesExplicitStop(
                RouteSection(to: "東", toN02StationCode: "999999", toStationID: "st:jp:1"),
                RouteSection(from: "西", fromN02StationCode: "888888", fromStationID: "st:jp:4")))
            #expect(!RouteSolver.routeSectionBoundarySharesExplicitStop(
                RouteSection(to: "東京", toStationID: "st:jp:1"),
                RouteSection(from: "東京", fromStationID: "st:jp:2")))
            #expect(SolverRegistryInput.markerAgrees(
                declared: "111110", stop: stop("別", stationID: "st:jp:1"), region: "jp"))
        }
    }

    @Test func tokyoNarrowsOnlyAStationThatOwnsTheCodeAndAnchorsWriteIds() {
        let open = RouteSection(from: "東京", to: "品川")
        let absent = TokyoConventionalRouteInference.section(open, in: tokyoTrain())
        #expect(absent.fromN02StationCode == nil)
        #expect(absent.toN02StationCode == nil)
        #expect(absent.sectionCodes == nil)

        withIdentity {
            let blocked = TokyoConventionalRouteInference.section(open, in: tokyoTrain())
            #expect(blocked.fromN02StationCode == nil)
            #expect(blocked.sectionCodes == nil)

            let owned = TokyoConventionalRouteInference.section(
                RouteSection(
                    from: "東京", to: "品川",
                    fromStationID: "st:jp:10", toStationID: "st:jp:11"),
                in: tokyoTrain())
            #expect(owned.fromN02StationCode == "003766")
            #expect(owned.toN02StationCode == "004095")
            #expect(owned.sectionCodes?.isEmpty == false)

            let foreign = TokyoConventionalRouteInference.section(
                RouteSection(
                    from: "東京", to: "品川",
                    fromN02StationCode: "999999", toN02StationCode: "004095",
                    fromStationID: "st:jp:10", toStationID: "st:jp:11"),
                in: tokyoTrain())
            #expect(foreign.fromN02StationCode == "999999")
            #expect(foreign.sectionCodes == nil)

            #expect(SolverRegistryInput.anchorStationID(
                code: "111111", region: "jp", operatorID: "op:jp:1") == "st:jp:1")
            #expect(SolverRegistryInput.anchorStationID(
                code: "000000", region: "jp", operatorID: "op:jp:1") == nil)
        }
    }

    @Test func persistedHopCodesComeFromTheStationWhenItHasOne() {
        #expect(SolverRegistryInput.persistedHopCode(
            persisted: "kept", sectionCode: "section", stationID: nil, region: "jp") == "kept")
        #expect(SolverRegistryInput.persistedHopCode(
            persisted: nil, sectionCode: "section", stationID: nil, region: "jp") == "section")

        withIdentity {
            #expect(SolverRegistryInput.persistedHopCode(
                persisted: "111110", sectionCode: "222222",
                stationID: "st:jp:1", region: "jp") == "111110")
            #expect(SolverRegistryInput.persistedHopCode(
                persisted: "999999", sectionCode: "111111",
                stationID: "st:jp:1", region: "jp") == "111111")
            #expect(SolverRegistryInput.persistedHopCode(
                persisted: "999999", sectionCode: "222222",
                stationID: "st:jp:1", region: "jp") == "111111")
            #expect(SolverRegistryInput.persistedHopCode(
                persisted: "111111", sectionCode: "111111",
                stationID: "st:jp:7", region: "jp") == nil)
            #expect(SolverRegistryInput.persistedHopCode(
                persisted: "111111", sectionCode: "111111",
                stationID: "st:jp:99", region: "jp") == nil)
        }
    }

    @Test func solveRequestedBeforePreloadUsesRegistryAfterItCompletes() async {
        let readyIdentity = identity()
        final class Gate: @unchecked Sendable { var ready = false }
        let gate = Gate()
        await RegistryIdentityTestGate.withPhase({ region in
            guard region == "jp" else { return .unavailable }
            return gate.ready ? .ready(readyIdentity) : .pending
        }) {
            let train = RouteGraph.CacheKeyTrain(trainType: "ソニック", operatorID: "op:jp:1")
            let sections = [RouteGraph.RouteSection(from: "大分", to: "小倉")]
            #expect(RouteGraph.solveContext(train: train, routeSections: sections, country: "jp") == nil)
            let pending = Task {
                await RouteGraph.solveContextAwaitingRegistry(
                    train: train, routeSections: sections, country: "jp")
            }
            gate.ready = true
            RegistryIdentityLookup.notifySettled(region: "jp")
            let key = await pending.value?.cacheKey ?? ""
            #expect(key.hasPrefix("solver:28|"))
            #expect(key.contains("JR East Package"))
            #expect(key.contains("日豊線"))
            #expect(!key.contains("九州旅客鉄道"))
        }
    }
}
