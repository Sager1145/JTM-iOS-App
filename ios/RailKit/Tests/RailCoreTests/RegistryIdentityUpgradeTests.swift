import Foundation
import Testing
@testable import RailCore

@Suite("RegistryIdentityUpgradeTests")
struct RegistryIdentityUpgradeTests {
    private let stationPattern = "^st:(jp|tw|hk|mo|kr|cn):[1-9][0-9]*$"
    private let operatorPattern = "^op:(jp|tw|hk|mo|kr|cn):[1-9][0-9]*$"

    private func bundle(
        region: String = "jp",
        stationCodes: [String: String] = [:],
        groupCodes: [String: [String]] = [:],
        operators: [String: [String]] = [:],
        stationOperator: [String: String] = [:]
    ) -> RegistryBundle {
        RegistryBundle(
            region: region, run: 1,
            stationCodes: stationCodes, groupCodes: groupCodes,
            operators: operators, stationOperator: stationOperator)
    }

    private func ride(
        company: String? = nil,
        operatorID: String? = nil,
        region: String? = "jp",
        stops: [Stop],
        sections: [RouteSection]? = nil
    ) -> Train {
        Train(
            id: "ride1", number: "1", company: company,
            origin: "A", destination: "B",
            routeSections: sections, stops: stops,
            region: region, operatorID: operatorID)
    }

    private func pair(_ code: String? = nil, stationID: String? = nil, name: String = "A") -> [Stop] {
        [
            Stop(
                name: name, n02StationCode: code, departure: "06:00",
                stopType: "origin", rideSegment: true, stationID: stationID),
            Stop(name: "B", arrival: "07:00", stopType: "destination", rideSegment: true),
        ]
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

    @Test func decodesABundleAndRejectsAnotherSchema() throws {
        let json = """
        {"schema":"jtm-registry-bundle/1","region":"jp","run":3,\
        "stationCodes":{"003700":"st:jp:1"},"groupCodes":{"G":["st:jp:2"]},\
        "operators":{"op:jp:1":["JR東日本"]},"stationOperator":{"st:jp:2":"op:jp:1"},\
        "lines":{"yamanote":"lp:jp:1"},\
        "stations":{"st:jp:9":{"cx":"cx:jp:1","group":"G","codes":["9"],"op":"op:jp:1","name":"ignored","lines":[]}}}
        """
        let decoded = try JSONDecoder().decode(RegistryBundle.self, from: Data(json.utf8))
        #expect(decoded.schema == RegistryBundle.legacySchema)
        #expect(decoded.region == "jp")
        #expect(decoded.run == 3)
        #expect(decoded.stationCodes["003700"] == "st:jp:1")
        #expect(decoded.groupCodes["G"] == ["st:jp:2"])
        #expect(decoded.operators["op:jp:1"] == ["JR東日本"])
        #expect(decoded.operatorRecords["op:jp:1"]?.label == "")
        #expect(decoded.operatorRecords["op:jp:1"]?.identity == nil)
        #expect(decoded.stations.isEmpty)
        #expect(decoded.complexes.isEmpty)
        #expect(decoded.lineParts.isEmpty)
        #expect(decoded.lines["yamanote"] == "lp:jp:1")

        let rejected = """
        {"schema":"nope","region":"jp","run":1,"stationCodes":{},"groupCodes":{},\
        "operators":{},"stationOperator":{},"lines":{}}
        """
        #expect(throws: DecodingError.self) {
            _ = try JSONDecoder().decode(RegistryBundle.self, from: Data(rejected.utf8))
        }
    }

    @Test func schema2OperatorObjectStillMatchesTheCompany() throws {
        let json = """
        {"schema":"jtm-registry-bundle/2","region":"jp","run":1,\
        "stationCodes":{"003700":"st:jp:1"},"groupCodes":{},\
        "operators":{"op:jp:1":{"names":["JR East","JR東日本"],"label":"JR東日本","logo":"/logos/jr-east.svg","identity":"jp.jr-east"}},\
        "stationOperator":{},"lines":{},"stations":{},"complexes":{},"lineParts":{}}
        """
        let decoded = try JSONDecoder().decode(RegistryBundle.self, from: Data(json.utf8))
        #expect(decoded.schema == RegistryBundle.currentSchema)
        #expect(decoded.operators["op:jp:1"] == ["JR East", "JR東日本"])
        #expect(decoded.operatorRecords["op:jp:1"]?.label == "JR東日本")
        #expect(decoded.operatorRecords["op:jp:1"]?.logo == "/logos/jr-east.svg")
        #expect(decoded.operatorRecords["op:jp:1"]?.identity == "jp.jr-east")
        let upgraded = RegistryIdentityUpgrade.apply(
            ride(company: "JR東日本", stops: pair("003700")), bundle: decoded)
        #expect(upgraded.operatorID == "op:jp:1")
        #expect(upgraded.stops[0].stationID == "st:jp:1")
    }

    @Test func uniqueStationCodeAndCompany() {
        let source = ride(
            company: "  JR東日本  ",
            stops: pair("003700", name: "東京"),
            sections: [RouteSection(fromN02StationCode: "003700", toN02StationCode: "116021")])
        let upgraded = RegistryIdentityUpgrade.apply(
            source,
            bundle: bundle(
                stationCodes: ["003700": "st:jp:1"],
                operators: ["op:jp:1": ["JR East", "JR東日本"], "op:jp:2": ["JR東海"]]))
        #expect(upgraded.operatorID == "op:jp:1")
        #expect(upgraded.company == "  JR東日本  ")
        #expect(upgraded.stops[0].stationID == "st:jp:1")
        #expect(upgraded.stops[0].n02StationCode == "003700")
        #expect(upgraded.stops[0].name == "東京")
        #expect(upgraded.stops[1].stationID == nil)
        #expect(upgraded.routeSections?.first?.fromN02StationCode == "003700")
        #expect(upgraded.routeSections?.first?.toN02StationCode == "116021")
        #expect(upgraded.routeSections?.first?.fromStationID == "st:jp:1")
        #expect(upgraded.routeSections?.first?.toStationID == nil)
    }

    @Test func aliasCanonicalizesAHongKongCode() {
        let upgraded = RegistryIdentityUpgrade.apply(
            ride(region: "hk", stops: pair("EAL-LOW-MTR-ADM")),
            bundle: bundle(
                region: "hk",
                stationCodes: [
                    "EAL-LOW-MTR-ADM": "st:hk:999",
                    "MTR-ADM": "st:hk:7",
                ]))
        #expect(upgraded.stops[0].stationID == "st:hk:7")
        #expect(upgraded.stops[0].n02StationCode == "EAL-LOW-MTR-ADM")
    }

    @Test func groupCodeWithOneStation() {
        let upgraded = RegistryIdentityUpgrade.apply(
            ride(stops: pair("GRP")),
            bundle: bundle(groupCodes: ["GRP": ["st:jp:5"]]))
        #expect(upgraded.stops[0].stationID == "st:jp:5")
    }

    @Test func groupCodeResolvesByOperator() {
        let tables = bundle(
            groupCodes: ["GRP": ["st:jp:1", "st:jp:2"]],
            operators: ["op:jp:1": ["JR東日本"], "op:jp:2": ["JR東海"]],
            stationOperator: ["st:jp:1": "op:jp:1", "st:jp:2": "op:jp:2"])
        let resolved = RegistryIdentityUpgrade.apply(
            ride(company: "JR東日本", stops: pair("GRP")), bundle: tables)
        #expect(resolved.operatorID == "op:jp:1")
        #expect(resolved.stops[0].stationID == "st:jp:1")

        let unresolved = RegistryIdentityUpgrade.apply(
            ride(stops: pair("GRP")), bundle: tables)
        #expect(unresolved.operatorID == nil)
        #expect(unresolved.stops[0].stationID == nil)
    }

    @Test func groupCodeStaysNilWhenTwoStationsShareTheOperator() {
        let upgraded = RegistryIdentityUpgrade.apply(
            ride(company: "JR東日本", stops: pair("GRP")),
            bundle: bundle(
                groupCodes: ["GRP": ["st:jp:1", "st:jp:2"]],
                operators: ["op:jp:1": ["JR東日本"]],
                stationOperator: ["st:jp:1": "op:jp:1", "st:jp:2": "op:jp:1"]))
        #expect(upgraded.operatorID == "op:jp:1")
        #expect(upgraded.stops[0].stationID == nil)
    }

    @Test func uniqueAnswerOverwritesAStaleIdentity() {
        let upgraded = RegistryIdentityUpgrade.apply(
            ride(
                company: "JR東日本", operatorID: "op:jp:9",
                stops: pair("003700", stationID: "st:jp:9")),
            bundle: bundle(
                stationCodes: ["003700": "st:jp:1"],
                operators: ["op:jp:1": ["JR東日本"]]))
        #expect(upgraded.operatorID == "op:jp:1")
        #expect(upgraded.stops[0].stationID == "st:jp:1")
        #expect(upgraded.stops[0].n02StationCode == "003700")
        #expect(upgraded.company == "JR東日本")
    }

    @Test func editedStopCodeRefreshesStationID() {
        let upgraded = RegistryIdentityUpgrade.apply(
            ride(stops: pair("003800", stationID: "st:jp:1")),
            bundle: bundle(stationCodes: [
                "003700": "st:jp:1",
                "003800": "st:jp:2",
            ]))
        #expect(upgraded.stops[0].stationID == "st:jp:2")
        #expect(upgraded.stops[0].n02StationCode == "003800")
        #expect(upgraded.stops[0].name == "A")
    }

    @Test func companyChangeRefreshesOperatorAndDependentStations() {
        let tables = bundle(
            groupCodes: ["GRP": ["st:jp:1", "st:jp:2"]],
            operators: ["op:jp:1": ["JR東日本"], "op:jp:2": ["JR東海"]],
            stationOperator: ["st:jp:1": "op:jp:1", "st:jp:2": "op:jp:2"])
        var edited = ride(
            company: "JR東日本", operatorID: "op:jp:1",
            stops: pair("GRP", stationID: "st:jp:1"))
        RegistryIdentityUpgrade.reassignCompany("JR東海", on: &edited)
        #expect(edited.company == "JR東海")
        #expect(edited.operatorID == nil)
        #expect(edited.stops[0].stationID == nil)
        #expect(edited.stops[0].n02StationCode == "GRP")

        let fromStale = RegistryIdentityUpgrade.apply(
            ride(
                company: "JR東海", operatorID: "op:jp:1",
                stops: pair("GRP", stationID: "st:jp:1")),
            bundle: tables)
        #expect(fromStale.operatorID == "op:jp:2")
        #expect(fromStale.stops[0].stationID == "st:jp:2")
        #expect(fromStale.company == "JR東海")

        RegistryIdentityUpgrade.reassignCompany("JR東海", on: &edited)
        #expect(edited.operatorID == nil)
    }

    @Test func staleIdentityMissingFromTheBundleIsCleared() {
        let upgraded = RegistryIdentityUpgrade.apply(
            ride(
                company: "京王", operatorID: "op:jp:9",
                stops: pair("GRP", stationID: "st:jp:9")),
            bundle: bundle(
                stationCodes: ["OTHER": "st:jp:8"],
                groupCodes: ["GRP": ["st:jp:1", "st:jp:2"]],
                operators: ["op:jp:1": ["京王"], "op:jp:2": ["京王"]],
                stationOperator: ["st:jp:1": "op:jp:1", "st:jp:2": "op:jp:2"]))
        #expect(upgraded.operatorID == nil)
        #expect(upgraded.stops[0].stationID == nil)
        #expect(upgraded.company == "京王")
        #expect(upgraded.stops[0].n02StationCode == "GRP")
    }

    @Test func ambiguousIdentityKeepsAConsistentId() {
        let tables = bundle(
            groupCodes: ["GRP": ["st:jp:1", "st:jp:2"]],
            operators: ["op:jp:1": ["京王"], "op:jp:2": ["京王"]],
            stationOperator: ["st:jp:1": "op:jp:1", "st:jp:2": "op:jp:1"])
        let kept = RegistryIdentityUpgrade.apply(
            ride(
                company: "京王", operatorID: "op:jp:1",
                stops: pair("GRP", stationID: "st:jp:1")),
            bundle: tables)
        #expect(kept.operatorID == "op:jp:1")
        #expect(kept.stops[0].stationID == "st:jp:1")

        let outsideGroup = RegistryIdentityUpgrade.apply(
            ride(
                company: "京王", operatorID: "op:jp:1",
                stops: pair("GRP", stationID: "st:jp:9")),
            bundle: tables)
        #expect(outsideGroup.operatorID == "op:jp:1")
        #expect(outsideGroup.stops[0].stationID == nil)

        let wrongName = RegistryIdentityUpgrade.apply(
            ride(company: "JR", operatorID: "op:jp:1", stops: pair()),
            bundle: bundle(operators: ["op:jp:1": ["JR東日本"]]))
        #expect(wrongName.operatorID == nil)
    }

    @Test func missingBundleLeavesIdsUntouched() {
        let source = ride(
            company: "JR東日本", operatorID: "op:jp:9",
            stops: pair("003700", stationID: "st:jp:9"))
        defer { RegistryIdentityUpgrade.installBundleProvider(nil) }
        RegistryIdentityUpgrade.installBundleProvider(nil)
        let absentHook = RegistryIdentityUpgrade.applyLoaded(source, regionFallback: "jp")
        #expect(absentHook.operatorID == "op:jp:9")
        #expect(absentHook.stops[0].stationID == "st:jp:9")
        #expect(absentHook.company == "JR東日本")
        #expect(absentHook.stops[0].n02StationCode == "003700")

        RegistryIdentityUpgrade.installBundleProvider { _ in nil }
        let missed = RegistryIdentityUpgrade.applyLoaded(source, regionFallback: "jp")
        #expect(missed.operatorID == "op:jp:9")
        #expect(missed.stops[0].stationID == "st:jp:9")
        let noRegion = RegistryIdentityUpgrade.applyLoaded(
            ride(company: "JR東日本", operatorID: "op:jp:9", region: nil,
                 stops: pair("003700", stationID: "st:jp:9")),
            regionFallback: nil)
        #expect(noRegion.operatorID == "op:jp:9")
        #expect(noRegion.stops[0].stationID == "st:jp:9")
    }

    @Test func ambiguousCompanyAndNonExactNamesStayNil() {
        let ambiguous = RegistryIdentityUpgrade.apply(
            ride(company: "京王", stops: pair()),
            bundle: bundle(operators: ["op:jp:1": ["京王"], "op:jp:2": ["京王"]]))
        #expect(ambiguous.operatorID == nil)

        let substring = RegistryIdentityUpgrade.apply(
            ride(company: "JR", stops: pair()),
            bundle: bundle(operators: ["op:jp:1": ["JR東日本"]]))
        #expect(substring.operatorID == nil)

        let fullwidth = RegistryIdentityUpgrade.apply(
            ride(company: "ＪＲ東日本", stops: pair()),
            bundle: bundle(operators: ["op:jp:1": ["JR東日本"]]))
        #expect(fullwidth.operatorID == "op:jp:1")
    }

    @Test func taiwanCompanyUsesTheShortName() {
        let upgraded = RegistryIdentityUpgrade.apply(
            ride(company: "臺灣鐵路管理局", region: "tw", stops: pair("TRA-1000")),
            bundle: bundle(region: "tw", operators: ["op:tw:1": ["台鐵"]]))
        #expect(upgraded.operatorID == "op:tw:1")
        #expect(upgraded.company == "臺灣鐵路管理局")

        let japanBundle = RegistryIdentityUpgrade.apply(
            ride(company: "臺灣鐵路管理局", stops: pair()),
            bundle: bundle(region: "jp", operators: ["op:jp:1": ["台鐵"]]))
        #expect(japanBundle.operatorID == nil)
    }

    @Test func absentKeysStayByteIdentical() throws {
        let origin = Stop(
            name: "東京", n02StationCode: "003700", departure: "06:00",
            stopType: "origin", rideSegment: true)
        let destination = Stop(
            name: "新大阪", n02StationCode: "116021", arrival: "08:27",
            stopType: "destination", rideSegment: true)
        let train = Train(
            id: "t1", number: "1", company: "JR東海",
            origin: "東京", destination: "新大阪", stops: [origin, destination])
        let stopJSON = StoreOperations.stringify(StoreOperations.json(origin))
        #expect(stopJSON == """
        {"name":"東京","n02_station_code":"003700","platform_number":null,"arrival":null,"departure":"06:00","stop_type":"origin","ride_segment":true}
        """)
        let trainJSON = StoreOperations.stringify(StoreOperations.json(train))
        #expect(trainJSON == """
        {"id":"t1","number":"1","company":"JR東海","origin":"東京","destination":"新大阪","stops":[\
        {"name":"東京","n02_station_code":"003700","platform_number":null,"arrival":null,"departure":"06:00","stop_type":"origin","ride_segment":true},\
        {"name":"新大阪","n02_station_code":"116021","platform_number":null,"arrival":"08:27","departure":null,"stop_type":"destination","ride_segment":true}]}
        """)
        let encoded = String(decoding: try JSONEncoder().encode(train), as: UTF8.self)
        #expect(!encoded.contains("station_id"))
        #expect(!encoded.contains("operator_id"))
        let roundTrip = try JSONDecoder().decode(Train.self, from: Data(encoded.utf8))
        #expect(roundTrip.operatorID == nil)
        #expect(roundTrip.stops[0].stationID == nil)
        #expect(roundTrip.company == "JR東海")
        #expect(roundTrip.stops[0].n02StationCode == "003700")
    }

    @Test func presentKeysRoundTrip() throws {
        let origin = Stop(
            name: "東京", n02StationCode: "003700", departure: "06:00",
            stopType: "origin", rideSegment: true, stationID: "st:jp:1")
        let train = Train(
            id: "t1", number: "1", company: "JR東海",
            origin: "東京", destination: "新大阪",
            stops: [
                origin,
                Stop(
                    name: "新大阪", n02StationCode: "116021", arrival: "08:27",
                    stopType: "destination", rideSegment: true, stationID: "st:jp:2"),
            ],
            operatorID: "op:jp:4")
        let text = StoreOperations.stringify(StoreOperations.json(train))
        #expect(text.contains("\"company\":\"JR東海\",\"operator_id\":\"op:jp:4\",\"origin\""))
        #expect(text.contains("\"n02_station_code\":\"003700\",\"station_id\":\"st:jp:1\",\"platform_number\""))
        let encoded = try JSONEncoder().encode(train)
        let decoded = try JSONDecoder().decode(Train.self, from: encoded)
        #expect(decoded.operatorID == "op:jp:4")
        #expect(decoded.operatorIDs == nil)
        #expect(decoded.stops.map(\.stationID) == ["st:jp:1", "st:jp:2"])
        #expect(decoded.company == "JR東海")
        #expect(decoded.stops[0].n02StationCode == "003700")

        let explicitNull = """
        {"id":"t1","number":"1","origin":"A","destination":"B","operator_id":null,"stops":[
        {"name":"A","n02_station_code":null,"station_id":null,"platform_number":null,"arrival":null,"departure":"06:00","stop_type":"origin","ride_segment":true},
        {"name":"B","n02_station_code":null,"platform_number":null,"arrival":"07:00","departure":null,"stop_type":"destination","ride_segment":true}]}
        """
        let fromNull = try JSONDecoder().decode(Train.self, from: Data(explicitNull.utf8))
        #expect(fromNull.operatorID == nil)
        #expect(fromNull.stops[0].stationID == nil)
    }

    @Test func validationAcceptsIdsAndRejectsMalformedOrWrongRegion() throws {
        let valid = ride(
            operatorID: "op:jp:2", region: "JP",
            stops: pair("003700", stationID: "st:jp:10"))
        #expect(rejection(valid) == nil)

        var malformed = ride(stops: pair(stationID: "st:jp:0"))
        #expect(rejection(malformed) == "Train 1 stop 1: station_id must match \(stationPattern).")
        malformed.stops[0].stationID = "st:jp:01"
        #expect(rejection(malformed) == "Train 1 stop 1: station_id must match \(stationPattern).")
        malformed.stops[0].stationID = "st:us:1"
        #expect(rejection(malformed) == "Train 1 stop 1: station_id must match \(stationPattern).")
        malformed.stops[0].stationID = ""
        #expect(rejection(malformed) == "Train 1 stop 1: station_id must match \(stationPattern).")
        malformed.stops[0].stationID = "st:tw:1"
        #expect(rejection(malformed) == "Train 1 stop 1: station_id region must equal the train region.")

        var badOperator = ride(operatorID: "op:jp:0", stops: pair())
        #expect(rejection(badOperator) == "Train 1: operator_id must match \(operatorPattern).")
        badOperator.operatorID = "op:tw:1"
        #expect(rejection(badOperator) == "Train 1: operator_id region must equal the train region.")

        let raw = try TrainValidation.JSON.parse("""
        {"id":"ride1","number":"1","origin":"A","destination":"B","region":"jp","operator_id":4,\
        "stops":[{"name":"A","departure":"06:00","stop_type":"origin","ride_segment":true},\
        {"name":"B","arrival":"07:00","stop_type":"destination","ride_segment":true}]}
        """)
        var ids: Set<String> = []
        #expect(throws: TrainValidation.ValidationError.self) {
            try TrainValidation.validateTrain(raw, index: 0, ids: &ids)
        }
    }

    @Test func importKeepsSuppliedRegistryIds() throws {
        var session = ImportEngine.Session(country: "jp")
        let raw = try TrainValidation.JSON.parse("""
        {"id":"ride1","number":"1","origin":"東京","destination":"新大阪","region":"jp",\
        "company":"JR東海","operator_id":"op:jp:3","stops":[
        {"name":"東京","n02_station_code":"003700","station_id":"st:jp:1","departure":"06:00","stop_type":"origin","ride_segment":true},
        {"name":"新大阪","n02_station_code":"116021","station_id":"st:jp:2","arrival":"08:27","stop_type":"destination","ride_segment":true}]}
        """)
        let id = try session.appendImportedTrain(raw)
        #expect(id == "ride1")
        let imported = try #require(session.trains.first)
        #expect(imported.operatorID == "op:jp:3")
        #expect(imported.company == "JR東海")
        #expect(imported.stops[0].stationID == "st:jp:1")
        #expect(imported.stops[0].n02StationCode == "003700")
        #expect(imported.stops[1].stationID == "st:jp:2")
        #expect(imported.stops[1].n02StationCode == "116021")
    }

    @Test func sectionEndpointsFollowTheStopFailClosedRule() {
        let source = ride(
            company: "JR東日本",
            stops: pair("003700"),
            sections: [RouteSection(
                from: "A", to: "B",
                fromN02StationCode: "111111", toN02StationCode: "222222",
                fromStationID: "st:jp:9", toStationID: "st:jp:8")])
        let upgraded = RegistryIdentityUpgrade.apply(
            source,
            bundle: bundle(
                stationCodes: ["111111": "st:jp:1"],
                groupCodes: ["222222": ["st:jp:2", "st:jp:3"]],
                operators: ["op:jp:1": ["JR東日本"]],
                stationOperator: ["st:jp:2": "op:jp:1", "st:jp:3": "op:jp:1"]))
        let section = upgraded.routeSections?.first
        #expect(section?.fromStationID == "st:jp:1")
        #expect(section?.toStationID == nil)
        #expect(section?.fromN02StationCode == "111111")
        #expect(section?.toN02StationCode == "222222")
    }

    @Test func retiredIdsResolveAndUpgradeToTheLiveId() throws {
        var tables = bundle(
            groupCodes: ["222222": ["st:jp:2", "st:jp:3"]],
            operators: ["op:jp:1": ["JR東日本"]],
            stationOperator: ["st:jp:2": "op:jp:1", "st:jp:3": "op:jp:1"])
        tables.aliases = ["st:jp:9": "st:jp:2", "op:jp:7": "op:jp:1"]
        tables.stations["st:jp:2"] = RegistryStationRecord(
            cx: "cx:jp:1", group: "222222", codes: ["222222"], op: "op:jp:1", name: "B", lines: [])
        let identity = RegistryIdentity(bundle: tables)
        #expect(identity.station("st:jp:9")?.name == "B")
        #expect(identity.codes(of: "st:jp:9") == ["222222"])
        #expect(tables.canonicalID("st:jp:2") == "st:jp:2")
        let source = ride(
            operatorID: "op:jp:7",
            stops: pair("222222", stationID: "st:jp:9"),
            sections: [RouteSection(
                from: "A", to: "B", fromN02StationCode: "222222", toN02StationCode: "222222",
                fromStationID: "st:jp:9", toStationID: "st:jp:3")])
        let upgraded = RegistryIdentityUpgrade.apply(source, bundle: tables)
        #expect(upgraded.operatorID == nil || upgraded.operatorID == "op:jp:1")
        #expect(upgraded.stops[0].stationID == "st:jp:2")
        #expect(upgraded.routeSections?.first?.fromStationID == "st:jp:2")
        #expect(upgraded.routeSections?.first?.toStationID == "st:jp:3")
    }

    @Test func missingAliasesKeyStillDecodes() throws {
        let json = """
        {"schema":"jtm-registry-bundle/2","region":"jp","run":3,"stationCodes":{},\
        "groupCodes":{},"operators":{},"stationOperator":{},"lines":{}}
        """
        let decoded = try JSONDecoder().decode(RegistryBundle.self, from: Data(json.utf8))
        #expect(decoded.aliases.isEmpty)
        #expect(decoded.canonicalID("st:jp:1") == "st:jp:1")
    }

    @Test func slashJoinedCompaniesBecomeOperatorIds() throws {
        let tables = bundle(operators: [
            "op:jp:1": ["JR東日本"],
            "op:jp:2": ["JR東海"],
        ])
        let joint = RegistryIdentityUpgrade.apply(
            ride(company: "JR東日本／JR東海", operatorID: "op:jp:9", stops: pair()),
            bundle: tables)
        #expect(joint.operatorIDs == ["op:jp:1", "op:jp:2"])
        #expect(joint.operatorID == nil)
        let ascii = RegistryIdentityUpgrade.apply(
            ride(company: "JR東日本/JR東海", stops: pair()), bundle: tables)
        #expect(ascii.operatorIDs == ["op:jp:1", "op:jp:2"])
        let mixed = RegistryIdentityUpgrade.apply(
            ride(company: "JR東日本/架空", operatorID: "op:jp:1", stops: pair()), bundle: tables)
        #expect(mixed.operatorIDs == nil)
        #expect(mixed.operatorID == nil)
        var singleSource = ride(company: "JR東日本", stops: pair())
        singleSource.operatorIDs = ["op:jp:1", "op:jp:2"]
        let single = RegistryIdentityUpgrade.apply(singleSource, bundle: tables)
        #expect(single.operatorID == "op:jp:1")
        #expect(single.operatorIDs == nil)

        var cleared = joint
        RegistryIdentityUpgrade.reassignCompany(nil, on: &cleared)
        #expect(cleared.operatorID == nil)
        #expect(cleared.operatorIDs == nil)

        var encodedTrain = Train(
            id: "t1", number: "1", company: "JR東日本／JR東海",
            origin: "A", destination: "B", stops: pair())
        encodedTrain.operatorIDs = ["op:jp:1", "op:jp:2"]
        let text = StoreOperations.stringify(StoreOperations.json(encodedTrain))
        #expect(text.contains("\"operator_ids\":[\"op:jp:1\",\"op:jp:2\"]"))
        #expect(!text.contains("\"operator_id\":"))
        let roundTrip = try JSONDecoder().decode(Train.self, from: JSONEncoder().encode(encodedTrain))
        #expect(roundTrip.operatorIDs == ["op:jp:1", "op:jp:2"])
        #expect(roundTrip.operatorID == nil)
    }

    @Test func reassignCompanyClearsSectionStationIds() {
        var train = ride(
            company: "JR東日本", operatorID: "op:jp:1",
            stops: pair("003700", stationID: "st:jp:1"),
            sections: [RouteSection(
                from: "A", to: "B", fromStationID: "st:jp:1", toStationID: "st:jp:2")])
        RegistryIdentityUpgrade.reassignCompany("JR東日本", on: &train)
        #expect(train.operatorID == "op:jp:1")
        #expect(train.routeSections?.first?.fromStationID == "st:jp:1")
        #expect(train.routeSections?.first?.toStationID == "st:jp:2")
        RegistryIdentityUpgrade.reassignCompany("JR東海", on: &train)
        #expect(train.company == "JR東海")
        #expect(train.operatorID == nil)
        #expect(train.stops[0].stationID == nil)
        #expect(train.routeSections?.first?.fromStationID == nil)
        #expect(train.routeSections?.first?.toStationID == nil)
    }

    @Test func operatorFieldsRejectBothAndDuplicates() throws {
        let stops = """
        "stops":[{"name":"A","departure":"06:00","stop_type":"origin","ride_segment":true},\
        {"name":"B","arrival":"07:00","stop_type":"destination","ride_segment":true}]
        """
        func message(_ extra: String) -> String? {
            let raw = try? TrainValidation.JSON.parse("""
            {"id":"ride1","number":"1","origin":"A","destination":"B","region":"jp",\(extra),\(stops)}
            """)
            guard let raw else { return "parse" }
            var ids: Set<String> = []
            do {
                try TrainValidation.validateTrain(raw, index: 0, ids: &ids)
                return nil
            } catch let error as TrainValidation.ValidationError {
                return error.message
            } catch {
                return "other"
            }
        }
        #expect(message(#""operator_id":"op:jp:1","operator_ids":["op:jp:2"]"#)
            == "Train 1: operator_id and operator_ids cannot both be set.")
        #expect(message(#""operator_ids":["op:jp:1"," op:jp:1 "]"#)
            == "Train 1: operator_ids contains a duplicate.")
        #expect(message(#""operator_id":"op:jp:1","operator_ids":["  "]"#) == nil)
    }
}
