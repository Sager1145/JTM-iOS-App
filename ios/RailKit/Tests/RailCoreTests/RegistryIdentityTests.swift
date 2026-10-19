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
    }

    @Test func lookupInstallsAndClears() {
        defer { RegistryIdentityLookup.install(nil) }
        RegistryIdentityLookup.install { region in
            guard region == "jp" else { return nil }
            return RegistryIdentity(bundle: RegistryBundle(region: "jp", run: 1))
        }
        #expect(RegistryIdentityLookup.identity(forRegion: "JP")?.bundle.region == "jp")
        #expect(RegistryIdentityLookup.identity(forRegion: "tw") == nil)
        #expect(RegistryIdentityLookup.identity(forRegion: "") == nil)
        RegistryIdentityLookup.install(nil)
        #expect(RegistryIdentityLookup.identity(forRegion: "jp") == nil)
    }
}
