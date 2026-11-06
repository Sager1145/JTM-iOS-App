import Testing
@_spi(Testing) @testable import RailCore

/// Identity entry points refuse when no registry is installed. They do not
/// fall back to name folding, the alias table, or corridor guessing.
/// Map labels (`RailMapCoordinator.localized`) and journey logos
/// (`JourneyBranding.operatorLogoPath`) live in the app target and are covered
/// by the RailMap build. Bare 国鉄 names are covered by
/// `ServicePatternBrowsePolicyTests.nationalRailwayNamesStayInsideTheJRGate`.
@Suite("Registry unavailable")
struct RegistryUnavailableTests {
    private func catalog() -> EditorCatalog {
        EditorCatalogBuilder.build([
            EditorCatalogLineSource(
                regionCode: "jp", lineID: "yamanote", name: "山手線",
                operatorName: "東日本旅客鉄道",
                stations: [
                    EditorCatalogStationSource(
                        sourceCode: "TOK", name: "東京", longitude: 139.7, latitude: 35.6),
                ],
                rank: 1),
        ])
    }

    @Test func pastedTextDoesNotResolveNames() {
        let seed = Train(
            id: "draft", number: "", origin: "", destination: "",
            stops: [Stop(name: "", stopType: "origin")], region: "jp")
        let draft = JourneyCompletion.rawDraft(
            text: "東京", catalog: catalog(), regionCode: "jp", seed: seed)
        #expect(draft.stops.isEmpty)
        #expect(draft.unmatchedLines == ["東京"])
    }

    @Test func completionLeavesStoredText() {
        let train = Train(
            id: "t", number: "1", origin: "東京", destination: "品川",
            stops: [
                Stop(name: "東京", departure: "09:00", stopType: "origin"),
                Stop(name: "品川", arrival: "09:20", stopType: "destination"),
            ],
            region: "jp")
        let resolved = JourneyCompletion.resolvingUniqueStationNames(
            in: train, catalogs: ["jp": catalog()])
        #expect(resolved.stops.map(\.name) == ["東京", "品川"])
        #expect(resolved.stops.map(\.n02StationCode) == [nil, nil])
        #expect(resolved.stops.map(\.stationID) == [nil, nil])
    }

    @Test func solverReportsIdentityUnavailable() {
        let stops = [
            Stop(name: "東京", n02StationCode: "111111", stopType: "origin", stationID: "st:jp:1"),
            Stop(name: "品川", n02StationCode: "222222", stopType: "destination", stationID: "st:jp:2"),
        ]
        #expect(SolverRegistryInput.solveInputCodes(stops: stops, region: "jp") == [])
        #expect(SolverRegistryInput.solvableEndpointCount(stops: stops, region: "jp") == 0)
        let hinted = SolverRegistryInput.hintedGraphStationCode(
            stationID: nil, rawCode: "111111", region: "jp", eligibility: nil)
        #expect(hinted == "111111")
        RegistryIdentityLookup.withTestPhase({ _ in .unavailable }) {
            #expect(RouteGraph.solveContext(
                train: RouteGraph.CacheKeyTrain(origin: "東京", destination: "品川"),
                routeSections: [RouteGraph.RouteSection(from: "東京", to: "品川")],
                country: "jp") == nil)
            #expect(SolverRegistryInput.hintedGraphStationCode(
                stationID: nil, rawCode: "111111", region: "jp", eligibility: nil) == nil)
        }
    }

    @Test func transferGuideRefusesNames() throws {
        let east = StationIndex.LineRef(name: "山手線", operatorName: "東日本旅客鉄道")
        let index = StationIndex([
            StationIndex.Entry(
                code: "TOK", name: "東京", coordinate: Coordinate(lon: 139.7, lat: 35.6), line: east),
        ])
        let route = TransferGuide.Route(legs: [
            TransferGuide.Leg(service: "JR山手線", calls: [
                TransferGuide.Call(name: "東京", departure: "09:00"),
                TransferGuide.Call(name: "品川", arrival: "09:20"),
            ]),
        ])
        let result = TransferGuide.build(
            route: route, options: TransferGuide.BuildOptions(region: "jp"), stations: index)
        let train = try #require(result.trains.first)
        #expect(result.resolvedCalls == 0)
        #expect(result.unresolved == ["東京", "品川"])
        #expect(train.company == "")
        #expect(train.stops.map(\.n02StationCode) == [nil, nil])
        #expect(train.stops.map(\.name) == ["東京", "品川"])
    }

    @Test func pendingImportStaysUnresolvedUntilSettle() {
        let seed = Train(
            id: "draft", number: "", origin: "", destination: "",
            stops: [Stop(name: "", stopType: "origin")], region: "jp")
        RegistryIdentityLookup.withTestPhase({ region in
            region == "jp" ? .pending : .unavailable
        }) {
            let draft = JourneyCompletion.rawDraft(
                text: "東京", catalog: catalog(), regionCode: "jp", seed: seed)
            #expect(draft.stops.count == 1)
            #expect(draft.stops[0].ambiguous)
            #expect(draft.stops[0].candidates.isEmpty)
            let east = StationIndex.LineRef(name: "山手線", operatorName: "東日本旅客鉄道")
            let index = StationIndex([
                StationIndex.Entry(
                    code: "TOK", name: "東京", coordinate: Coordinate(lon: 139.7, lat: 35.6), line: east),
            ])
            let route = TransferGuide.Route(legs: [
                TransferGuide.Leg(service: "JR山手線", calls: [
                    TransferGuide.Call(name: "東京", departure: "09:00"),
                    TransferGuide.Call(name: "品川", arrival: "09:20"),
                ]),
            ])
            let result = TransferGuide.build(
                route: route, options: TransferGuide.BuildOptions(region: "jp"), stations: index)
            #expect(result.resolvedCalls == 0)
            #expect(result.ambiguous["東京"] == [])
            #expect(result.trains.first?.company == "")
            #expect(SolverRegistryInput.solveInputCodes(stops: [
                Stop(name: "東京", n02StationCode: "111111", stationID: "st:jp:1"),
            ], region: "jp") == [])
            var edited = Train(
                id: "edit", number: "1", company: "東日本旅客鉄道",
                origin: "東京", destination: "品川",
                stops: [
                    Stop(name: "東京", stopType: "origin"),
                    Stop(name: "品川", stopType: "destination"),
                ],
                region: "jp")
            #expect(!RegistryOperatorCommit.apply(text: "東日本旅客鉄道", region: "jp", to: &edited))
            #expect(edited.operatorID == nil)
            #expect(edited.company == "東日本旅客鉄道")
            let resolved = JourneyCompletion.resolvingUniqueStationNames(
                in: edited, catalogs: ["jp": catalog()])
            #expect(resolved.stops.map(\.n02StationCode) == [nil, nil])
            #expect(resolved.stops.map(\.stationID) == [nil, nil])
        }
    }

    @Test func importWhilePendingResolvesAfterSettle() async {
        let bundle = RegistryBundle(
            region: "jp", run: 1,
            stationCodes: ["SHIN": "st:jp:9"],
            operatorRecords: [
                "op:jp:1": RegistryOperatorRecord(
                    names: ["JR東日本"], label: "JR東日本", identity: "jp.jr-east"),
            ],
            stations: [
                "st:jp:9": RegistryStationRecord(
                    cx: "cx:jp:9", group: "SHIN", codes: ["SHIN"], op: "op:jp:1",
                    name: "品川", lines: ["lp:jp:1"]),
            ],
            complexes: [
                "cx:jp:9": RegistryComplexRecord(
                    group: "SHIN", name: "品川", stations: ["st:jp:9"], lon: 139.7, lat: 35.6),
            ],
            lineParts: [
                "lp:jp:1": RegistryLinePartRecord(
                    packageLine: "lp:jp:1", name: "山手線", op: "op:jp:1", rank: 1),
            ])
        let identity = RegistryIdentity(bundle: bundle)
        final class PhaseBox: @unchecked Sendable {
            var phase: RegistryPhase = .pending
        }
        let box = PhaseBox()
        let east = StationIndex.LineRef(name: "山手線", operatorName: "JR東日本")
        let index = StationIndex([
            StationIndex.Entry(
                code: "SHIN", name: "品川", coordinate: Coordinate(lon: 139.7, lat: 35.6), line: east),
        ])
        let route = TransferGuide.Route(legs: [
            TransferGuide.Leg(service: "JR山手線", calls: [
                TransferGuide.Call(name: "品川", departure: "09:00"),
                TransferGuide.Call(name: "品川", arrival: "09:20"),
            ]),
        ])
        final class Built: @unchecked Sendable {
            var result: TransferGuide.BuildResult?
        }
        let built = Built()
        await RegistryIdentityLookup.withTestPhase({ _ in box.phase }) {
            let pending = TransferGuide.build(
                route: route, options: TransferGuide.BuildOptions(region: "jp"), stations: index)
            #expect(pending.resolvedCalls == 0)
            #expect(pending.trains.first?.stops.allSatisfy { $0.stationID == nil } == true)
            RegistryIdentityLookup.whenSettled(region: "jp") { _ in
                built.result = TransferGuide.build(
                    route: route, options: TransferGuide.BuildOptions(region: "jp"), stations: index)
            }
            let waited = Task {
                _ = await SolverRegistryInput.awaitReady(region: "jp")
                return TransferGuide.build(
                    route: route, options: TransferGuide.BuildOptions(region: "jp"), stations: index)
            }
            box.phase = .ready(identity)
            RegistryIdentityLookup.notifySettled(region: "jp")
            let resolved = await waited.value
            #expect(resolved.resolvedCalls == 2)
            #expect(resolved.trains.first?.stops.map(\.stationID) == ["st:jp:9", "st:jp:9"])
            #expect(built.result?.trains.first?.stops.map(\.stationID) == ["st:jp:9", "st:jp:9"])
        }
    }
}
