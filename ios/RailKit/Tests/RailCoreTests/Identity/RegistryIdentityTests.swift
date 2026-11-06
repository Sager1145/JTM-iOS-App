import Foundation
import Testing
@testable import RailCore

@Suite("RegistryIdentityTests")
struct RegistryIdentityTests {
    private func part(_ id: String, name: String, op: String, rank: Int) -> (String, RegistryLinePartRecord) {
        (id, RegistryLinePartRecord(packageLine: id, name: name, op: op, rank: rank))
    }

    private func tokyoBundle() -> RegistryBundle {
        let yamanote = part("lp:jp:1", name: "山手線", op: "op:jp:1", rank: 4)
        let tokaidoJR = part("lp:jp:2", name: "東海道線", op: "op:jp:1", rank: 2)
        let tokaidoCentral = part("lp:jp:3", name: "東海道線", op: "op:jp:2", rank: 1)
        let closed = StationNameRecord(
            base: "東京", bracket: "廃止", kind: .status, status: .closed, position: .suffix)
        return RegistryBundle(
            region: "jp", run: 1,
            stationCodes: ["003700": "st:jp:1", "MTR-ADM": "st:hk:7"],
            groupCodes: [
                "GRP": ["st:jp:2", "st:jp:3"],
                "ONE": ["st:jp:4"],
            ],
            operatorRecords: [
                "op:jp:1": RegistryOperatorRecord(
                    names: ["JR East", "東日本旅客鉄道", "JR東日本"],
                    label: "JR東日本", logo: "/logos/jr-east.svg", identity: "jp.jr-east"),
                "op:jp:2": RegistryOperatorRecord(
                    names: ["JR東海"], label: "JR東海", identity: "jp.jr-central"),
                "op:jp:3": RegistryOperatorRecord(
                    names: ["共用"], label: "共用", identity: "jp.jr-east"),
            ],
            stationOperator: [
                "st:jp:1": "op:jp:1",
                "st:jp:2": "op:jp:1",
                "st:jp:3": "op:jp:2",
                "st:jp:4": "op:jp:1",
                "st:jp:5": "op:jp:1",
            ],
            stations: [
                "st:jp:1": RegistryStationRecord(
                    cx: "cx:jp:1", group: "003700", codes: ["003700"], op: "op:jp:1",
                    name: "東京", lines: ["lp:jp:1", "lp:jp:2"]),
                "st:jp:5": RegistryStationRecord(
                    cx: "cx:jp:1", group: "003700", codes: ["CLOSED"], op: "op:jp:1",
                    name: "東京（廃止）", parts: closed, lines: ["lp:jp:1"]),
            ],
            complexes: [
                "cx:jp:1": RegistryComplexRecord(
                    group: "003700", name: "東京", stations: ["st:jp:1", "st:jp:5"],
                    lon: 139.76713, lat: 35.68124),
            ],
            lineParts: [yamanote.0: yamanote.1, tokaidoJR.0: tokaidoJR.1, tokaidoCentral.0: tokaidoCentral.1])
    }

    @Test func readsStationComplexCodesAndOperator() {
        let identity = RegistryIdentity(bundle: tokyoBundle())
        #expect(identity.station("st:jp:1")?.name == "東京")
        #expect(identity.station("st:jp:9") == nil)
        #expect(identity.codes(of: "st:jp:1") == ["003700"])
        #expect(identity.codes(of: "missing") == [])
        #expect(identity.complex(of: "st:jp:1")?.name == "東京")
        #expect(identity.complex(of: "st:jp:9") == nil)
        #expect(identity.stations(in: "cx:jp:1") == ["st:jp:1", "st:jp:5"])
        #expect(identity.stations(in: "cx:jp:9") == [])
        let record = identity.`operator`(for: "op:jp:1")
        #expect(record?.names == ["JR East", "東日本旅客鉄道", "JR東日本"])
        #expect(record?.label == "JR東日本")
        #expect(record?.logo == "/logos/jr-east.svg")
        #expect(record?.identity == "jp.jr-east")
        #expect(identity.`operator`(for: "op:jp:9") == nil)
    }

    @Test func operatorIdentityIsFailClosed() {
        let identity = RegistryIdentity(bundle: tokyoBundle())
        #expect(identity.operatorID(forIdentityCode: "jp.jr-central") == "op:jp:2")
        #expect(identity.operatorID(forIdentityCode: "jp.jr-east") == nil)
        #expect(identity.operatorID(forIdentityCode: "jp.missing") == nil)
    }

    @Test func stationIDMatchesTheUpgradeRule() {
        let identity = RegistryIdentity(bundle: tokyoBundle())
        #expect(identity.stationID(forCode: "003700", operator: nil) == "st:jp:1")
        #expect(identity.stationID(forCode: "EAL-LOW-MTR-ADM", operator: nil) == "st:hk:7")
        #expect(identity.stationID(forCode: "ONE", operator: nil) == "st:jp:4")
        #expect(identity.stationID(forCode: "GRP", operator: "op:jp:1") == "st:jp:2")
        #expect(identity.stationID(forCode: "GRP", operator: "op:jp:2") == "st:jp:3")
        #expect(identity.stationID(forCode: "GRP", operator: nil) == nil)
        #expect(identity.stationID(forCode: "GRP", operator: "op:jp:9") == nil)
        #expect(identity.stationID(forCode: "ABSENT", operator: "op:jp:1") == nil)
        let onlyOnTheRecord = RegistryBundle(
            region: "jp", run: 1,
            stations: [
                "st:jp:1": RegistryStationRecord(
                    cx: "cx:jp:1", group: "G", codes: ["ONLY"], op: "op:jp:1",
                    name: "東京", lines: []),
            ])
        #expect(RegistryIdentity(bundle: onlyOnTheRecord).stationID(forCode: "ONLY", operator: "op:jp:1") == nil)
    }

    @Test func directCodeBeatsAGroupThatWouldAlsoMatch() {
        let bundle = RegistryBundle(
            region: "jp", run: 1,
            stationCodes: ["BOTH": "st:jp:1"],
            groupCodes: ["BOTH": ["st:jp:2", "st:jp:3"]],
            stationOperator: ["st:jp:2": "op:jp:1", "st:jp:3": "op:jp:2"])
        let identity = RegistryIdentity(bundle: bundle)
        #expect(identity.stationID(forCode: "BOTH", operator: "op:jp:2") == "st:jp:1")
    }

    @Test func labelUsesTheRequestedLineOrTheBestRank() {
        let identity = RegistryIdentity(bundle: tokyoBundle())
        let requested = identity.label(for: "st:jp:1", line: "lp:jp:1", country: "jp")
        #expect(requested?.lineID == "lp:jp:1")
        #expect(requested?.text.countryCode == "JP")
        #expect(requested?.text.name == "東京")
        #expect(requested?.text.qualifier == "(JP, 山手線)")

        let otherLine = identity.label(for: "st:jp:1", line: "lp:jp:9", country: "jp")
        #expect(otherLine?.lineID == "lp:jp:2")
        #expect(otherLine?.text.qualifier == "(JP, JR東日本 東海道線)")

        let best = identity.label(for: "st:jp:1", country: "Jp")
        #expect(best?.lineID == "lp:jp:2")
        #expect(identity.label(for: "st:jp:9", country: "jp") == nil)
    }

    @Test func statusLabelUsesTheBaseAndTheBracket() {
        let identity = RegistryIdentity(bundle: tokyoBundle())
        let label = identity.label(for: "st:jp:5", country: "jp")
        #expect(label?.presentation.label == "東京")
        #expect(label?.presentation.secondary == "廃止 · (JP, 山手線)")
        #expect(label?.presentation.copy == "東京（廃止） (JP, 山手線)")
        #expect(label?.text.name == "東京")
        #expect(label?.text.full == "東京 (JP, 山手線)")
    }

    @Test func schema1IgnoresReverseMapsAndStillResolvesCodes() throws {
        let json = """
        {"schema":"jtm-registry-bundle/1","region":"jp","run":1,\
        "stationCodes":{"003700":"st:jp:1"},"groupCodes":{"GRP":["st:jp:2"]},\
        "operators":{"op:jp:1":["JR東日本"]},"stationOperator":{"st:jp:2":"op:jp:1"},\
        "lines":{},\
        "stations":{"st:jp:1":{"cx":"cx:jp:1","group":"003700","codes":["003700"],"op":"op:jp:1","name":"東京","lines":["lp:jp:1"]}},\
        "complexes":{"cx:jp:1":{"group":"003700","name":"東京","stations":["st:jp:1"],"lon":1,"lat":2}},\
        "lineParts":{"lp:jp:1":{"packageLine":"yamanote","name":"山手線","op":"op:jp:1","rank":1}}}
        """
        let decoded = try JSONDecoder().decode(RegistryBundle.self, from: Data(json.utf8))
        let identity = RegistryIdentity(bundle: decoded)
        #expect(decoded.schema == RegistryBundle.legacySchema)
        #expect(identity.station("st:jp:1") == nil)
        #expect(identity.complex(of: "st:jp:1") == nil)
        #expect(identity.stations(in: "cx:jp:1") == [])
        #expect(identity.`operator`(for: "op:jp:1")?.identity == nil)
        #expect(identity.`operator`(for: "op:jp:1")?.label == "")
        #expect(identity.operatorID(forIdentityCode: "jp.jr-east") == nil)
        #expect(identity.label(for: "st:jp:1", country: "jp") == nil)
        #expect(identity.stationID(forCode: "003700", operator: nil) == "st:jp:1")
        #expect(identity.stationID(forCode: "GRP", operator: "op:jp:1") == "st:jp:2")
        #expect(identity.operatorID(forExactName: "JR東日本") == "op:jp:1")
        #expect(identity.operatorLabel("op:jp:1") == "JR東日本")
        #expect(identity.operatorLogo("op:jp:1") == nil)
    }

    @Test func lookupInstallsAndClears() {
        RegistryIdentityTestGate.withProvider({ region in
            guard region == "jp" else { return nil }
            return RegistryIdentity(bundle: RegistryBundle(region: "jp", run: 1))
        }) {
            #expect(RegistryIdentityLookup.identity(forRegion: "JP")?.bundle.region == "jp")
            #expect(RegistryIdentityLookup.identity(forRegion: "tw") == nil)
            #expect(RegistryIdentityLookup.identity(forRegion: "") == nil)
        }
        #expect(RegistryIdentityLookup.identity(forRegion: "jp") == nil)
    }

    @Test func exactNamesStayUniqueAndQueriesUseTheIdentityBridge() {
        let identity = RegistryIdentity(bundle: tokyoBundle())
        #expect(identity.operatorID(forExactName: "JR東日本") == "op:jp:1")
        #expect(identity.operatorID(forExactName: "JR東海") == "op:jp:2")
        #expect(identity.operatorID(forExactName: "共用") == "op:jp:3")
        #expect(identity.operatorID(forExactName: "jp.jr-east") == nil)
        #expect(identity.operatorID(forExactName: "not-a-company") == nil)
        #expect(identity.operatorIDs(matchingQuery: "jp.jr-east").isEmpty)
        #expect(identity.operatorIDs(matchingQuery: "East Japan Railway Company") == Set(["op:jp:1", "op:jp:3"]))
        #expect(identity.operatorIDs(matchingQuery: "東日本") == Set(["op:jp:1", "op:jp:3"]))
        #expect(identity.operatorIDs(matchingQuery: "共用") == Set(["op:jp:3"]))
        #expect(identity.operatorIDs(matchingQuery: " ") == [])
        #expect(identity.operatorIDs(forCatalogName: "JR東日本/JR東海") == ["op:jp:1", "op:jp:2"])
        #expect(identity.operatorIDs(forCatalogName: "not-a-company") == [])
        #expect(identity.operatorIDs(forCatalogName: "JR東日本/not-a-company") == ["op:jp:1"])
        #expect(identity.operatorLabel("op:jp:1") == "JR東日本")
        #expect(identity.operatorLogo("op:jp:1") == "/logos/jr-east.svg")
        #expect(identity.operatorLogo("op:jp:2") == nil)
        let branded = RegistryBundle(
            region: "jp", run: 2,
            operatorRecords: [
                "op:jp:1": RegistryOperatorRecord(
                    names: ["東日本旅客鉄道"], label: "TEST-LABEL", logo: "/logos/test.svg",
                    identity: "jp.jr-east"),
            ])
        let facade = RegistryIdentity(bundle: branded)
        #expect(facade.operatorLabel("op:jp:1") == "TEST-LABEL")
        #expect(facade.operatorLogo("op:jp:1") == "/logos/test.svg")
        #expect(facade.operatorID(forCatalogOrTimetableToken: "jr-east") == "op:jp:1")
        #expect(facade.operatorID(forCatalogOrTimetableToken: "missing") == nil)
        #expect(facade.operatorIDs(matchingQuery: "JR西").isEmpty)
    }

    @Test func unresolvedStationKeepsTheStoredName() {
        RegistryIdentityTestGate.withProvider({ region in
            guard region == "jp" else { return nil }
            return RegistryIdentity(bundle: self.tokyoBundle())
        }) {
            let missing = RegistryStationDisplay.resolve(storedName: "東京", stationID: nil, region: "jp")
            #expect(missing.unresolved)
            #expect(missing.primary == "東京")
            #expect(missing.readingCodes.isEmpty)
            #expect(RegistryStationDisplay.unresolvedKey == "ios.identity.unresolved")
            let namedOnly = RegistryStationDisplay.resolve(storedName: "熱海", stationID: "", region: "jp")
            #expect(namedOnly.unresolved)
            #expect(namedOnly.primary == "熱海")
            let resolved = RegistryStationDisplay.resolve(
                storedName: "ignored", stationID: "st:jp:1", region: "jp", lineID: "lp:jp:1")
            #expect(!resolved.unresolved)
            #expect(resolved.primary == "東京")
            #expect(resolved.readingCodes == ["003700"])
            let fromStation = RegistryStationDisplay.resolve(
                storedName: "ignored", stationID: "st:jp:1", region: nil, lineID: "lp:jp:1")
            #expect(!fromStation.unresolved)
            #expect(fromStation.primary == "東京")
            let unknown = RegistryStationDisplay.resolve(storedName: "東京", stationID: "st:jp:9", region: "jp")
            #expect(unknown.unresolved)
            #expect(unknown.primary == "東京")
        }
    }

    @Test func readingsWithoutACodeDoNotUseTheNameGloss() throws {
        let catalog = try Localization.Catalog(data: Data(#"{"sourceLanguage":"en","version":"1.0","strings":{}}"#.utf8))
        let row = Localization.StationReadingRow(kana: "トウキョウ")
        let readings = Localization.StationReadings(
            country: "jp",
            byCode: ["003700": row],
            byName: ["別駅": Localization.StationReadingRow(kana: "ベツエキ")])
        let localization = Localization(
            catalog: catalog, language: .ja, country: "jp",
            readingPrefs: Localization.ReadingPrefs(kana: true, romaji: false, zh: false),
            stationReadings: readings)
        #expect(localization.nameReadingsTyped("別駅", code: "003700", allowNameFallback: false).map(\.text) == ["トウキョウ"])
        #expect(localization.nameReadingsTyped("北斗", allowNameFallback: false).isEmpty)
        #expect(localization.nameReadingsTyped("北斗", allowNameFallback: true).map(\.text) == ["ほくと"])
        #expect(localization.hasStationReading(code: "003700"))
        #expect(!localization.hasStationReading(code: "000000"))
        #expect(RegistryStationDisplay.firstCodeWithReading(["000000", "003700"]) {
            localization.hasStationReading(code: $0)
        } == "003700")
        #expect(RegistryStationDisplay.firstCodeWithReading(["000000"]) { _ in false } == nil)
    }

    @Test func queryMatchCacheDropsTheOldestQuery() {
        let cache = QueryMatchCache(limit: 2)
        var builds: [String] = []
        func value(_ key: String) -> Set<String> {
            builds.append(key)
            return [key]
        }
        _ = cache.matches("a") { value("a") }
        _ = cache.matches("b") { value("b") }
        _ = cache.matches("a") { value("a-hit") }
        _ = cache.matches("c") { value("c") }
        _ = cache.matches("a") { value("a-kept") }
        _ = cache.matches("b") { value("b-miss") }
        #expect(builds == ["a", "b", "c", "b-miss"])
    }

    @Test func uninstalledLookupNoteRequiresAnExplicitPermit() {
        #expect(RegistryIdentityLookup.shouldNoteUninstalledLookup(installed: false, permitted: false))
        #expect(!RegistryIdentityLookup.shouldNoteUninstalledLookup(installed: true, permitted: false))
        #expect(!RegistryIdentityLookup.shouldNoteUninstalledLookup(installed: false, permitted: true))
    }

    @Test func pendingRegistryShowsStoredTextUntilItSettles() {
        let built = RegistryIdentity(bundle: tokyoBundle())
        final class Gate: @unchecked Sendable { var ready = false }
        let gate = Gate()
        RegistryIdentityTestGate.withPhase({ region in
            guard region == "jp" else { return .unavailable }
            return gate.ready ? .ready(built) : .pending
        }) {
            let pending = RegistryStationDisplay.resolve(
                storedName: "stored", stationID: "st:jp:1", region: nil)
            #expect(!pending.unresolved)
            #expect(pending.primary == "stored")
            #expect(pending.readingCodes.isEmpty)
            gate.ready = true
            RegistryIdentityLookup.notifySettled(region: "jp")
            let ready = RegistryStationDisplay.resolve(
                storedName: "stored", stationID: "st:jp:1", region: nil)
            #expect(!ready.unresolved)
            #expect(ready.primary == "東京")
        }
    }

    @Test func exactOfficialNameWinsOverABase() {
        let plain = RegistryStationRecord(
            cx: "cx:jp:1", group: "G1", codes: ["ISA"], op: "op:jp:1", name: "諫早", lines: ["lp:1"])
        let bracket = StationNameRecord(
            base: "諫早", bracket: "雲仙・島原口", kind: .subname, position: .suffix)
        let island = RegistryStationRecord(
            cx: "cx:jp:2", group: "G2", codes: ["SHIMA"], op: "op:jp:2",
            name: "諫早（雲仙・島原口）", parts: bracket, lines: ["lp:2"])
        let identity = RegistryIdentity(bundle: RegistryBundle(
            region: "jp", run: 1,
            stationCodes: ["ISA": "st:jp:1", "SHIMA": "st:jp:2"],
            stations: ["st:jp:1": plain, "st:jp:2": island],
            complexes: [
                "cx:jp:1": RegistryComplexRecord(group: "G1", name: "諫早", stations: ["st:jp:1"], lon: 0, lat: 0),
                "cx:jp:2": RegistryComplexRecord(group: "G2", name: "諫早（雲仙・島原口）", stations: ["st:jp:2"], lon: 0, lat: 0),
            ],
            lineParts: [
                "lp:1": RegistryLinePartRecord(packageLine: "a", name: "長崎本線", op: "op:jp:1", rank: 1),
                "lp:2": RegistryLinePartRecord(packageLine: "b", name: "島原鉄道線", op: "op:jp:2", rank: 2),
            ],
            baseNameCounts: ["諫早": 2]))
        #expect(identity.stationIDs(named: "諫早") == ["st:jp:1"])
        #expect(identity.stations(for: StationReference(name: "諫早")).map(\.stationID) == ["st:jp:1"])
        #expect(identity.stations(for: StationReference(name: "諫早", line: "島原鉄道線")).map(\.stationID) == [])
        #expect(identity.stations(for: StationReference(name: "諫早", country: "TW")).isEmpty)
    }

    @Test func uniqueBaseSelectsTheBracketedStation() {
        let bracket = StationNameRecord(base: "西鉄福岡", bracket: "天神", kind: .subname, position: .suffix)
        let identity = RegistryIdentity(bundle: RegistryBundle(
            region: "jp", run: 1,
            stationCodes: ["NFT": "st:jp:1"],
            stations: [
                "st:jp:1": RegistryStationRecord(
                    cx: "cx:jp:1", group: "NFT", codes: ["NFT"], op: "op:jp:1",
                    name: "西鉄福岡（天神）", parts: bracket, lines: ["lp:1"]),
            ],
            baseNameCounts: ["西鉄福岡": 1]))
        #expect(identity.stationIDs(named: "西鉄福岡") == ["st:jp:1"])
        #expect(identity.stationIDs(named: "西鉄福岡（天神）") == ["st:jp:1"])
    }

    @Test func containedSpansProposeNamesAndDoNotChoose() {
        let identity = RegistryIdentity(bundle: tokyoBundle())
        #expect(identity.containedNameSpans(in: "09:00 東京発") == ["東京"])
        let spans = identity.containedNameSpans(in: "東京 新大阪")
        #expect(spans == ["東京"])
    }

    @Test func operatorCommitIsExactAndJoint() {
        let identity = RegistryIdentity(bundle: tokyoBundle())
        let one = identity.operatorCommit(forExactText: "JR東日本")
        #expect(one?.ids == ["op:jp:1"])
        #expect(one?.company == "JR東日本")
        #expect(one?.preferredNames == ["JR East"])
        let joint = identity.operatorCommit(forExactText: "JR東日本/JR東海")
        #expect(joint?.ids == ["op:jp:1", "op:jp:2"])
        #expect(joint?.company == "JR東日本/JR東海")
        #expect(identity.operatorCommit(forExactText: "JR東日本/missing") == nil)
        #expect(identity.operatorCommit(forExactText: "not-a-company") == nil)

        var train = Train(id: "t", number: "", origin: "", destination: "", stops: [], region: "jp")
        RegistryIdentityTestGate.withProvider({ region in
            region == "jp" ? identity : nil
        }) {
            #expect(RegistryOperatorCommit.apply(text: "JR東日本・JR東海", region: "jp", to: &train))
            #expect(train.operatorIDs == ["op:jp:1", "op:jp:2"])
            #expect(train.operatorID == nil)
            #expect(train.company == "JR東日本/JR東海")
            #expect(RegistryOperatorCommit.preferredNames(from: ["JR東海", "typed"], region: "jp") == ["JR東海", "typed"])
        }
    }
}
