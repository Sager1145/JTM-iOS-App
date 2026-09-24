import Foundation
import Testing

@testable import RailCore

// ADR 0010: legacy HK/MO codes that embedded the line map to `{OPERATOR}-{STOP}`.
@Suite("legacy station codes resolve to the per-region grammar")
struct StationCodeAliasesTests {
    @Test("the six Hong Kong legacy shapes and the Macao shape map by rule")
    func legacyShapes() {
        #expect(StationCodeAliases.canonical("AEL-MTR-HOK") == "MTR-HOK")
        #expect(StationCodeAliases.canonical("TKL-POA-MTR-NOP") == "MTR-NOP")
        #expect(StationCodeAliases.canonical("EAL-LOW-MTR-ADM") == "MTR-ADM")
        #expect(StationCodeAliases.canonical("LR-505-LR-100") == "LR-100")
        #expect(StationCodeAliases.canonical("LR-614P-LR-1") == "LR-1")
        #expect(StationCodeAliases.canonical("TRAM-HV-105") == "TRAM-105")
        #expect(StationCodeAliases.canonical("TRAM-NP-65E") == "TRAM-65E")
        #expect(StationCodeAliases.canonical("MLM-TAIPA-MLM-BARRA") == "MLM-BARRA")
    }

    @Test("Kaohsiung LRT codes drop their NETWORK segment")
    func klrtNetworkSegment() {
        #expect(StationCodeAliases.canonical("KLRT-NETWORK-C1") == "KLRT-C1")
        #expect(StationCodeAliases.canonical("KLRT-NETWORK-C21A") == "KLRT-C21A")
    }

    @Test("codes already in their region's grammar pass through", arguments: [
        "003700", "TRA-0920", "TRTC-R22", "AFR-Q0000001651", "MTR-ADM", "KLRT-C1", "",
    ])
    func passThrough(_ code: String) {
        #expect(StationCodeAliases.canonical(code) == code)
    }

    @Test("a persisted stop with a legacy code decodes to the new code")
    func decodedStopIsCanonical() throws {
        let json = #"{"name":"金鐘","n02_station_code":"EAL-LOW-MTR-ADM","platform_number":null,"arrival":null,"departure":null,"stop_type":"passenger_stop","ride_segment":false}"#
        let stop = try JSONDecoder().decode(Stop.self, from: Data(json.utf8))
        #expect(stop.n02StationCode == "MTR-ADM")
    }

    @Test("the JSON import path canonicalises a legacy stop code")
    func canonicalStopShapeIsCanonical() throws {
        let value = try TrainValidation.JSON.parse(#"{"name":"金鐘","n02_station_code":"EAL-LOW-MTR-ADM"}"#)
        #expect(TrainValidation.canonicalStopShape(value).n02StationCode == "MTR-ADM")
    }

    @Test("StationIndex.place(code:) resolves a legacy code")
    func stationIndexResolvesLegacyCode() {
        let index = StationIndex([
            .init(
                code: "MTR-ADM", name: "金鐘",
                coordinate: Coordinate(lon: 114.1646, lat: 22.2793),
                line: .init(name: "港島綫", operatorName: "港鐵"))
        ])
        #expect(index.place(code: "EAL-LOW-MTR-ADM")?.code == "MTR-ADM")
        #expect(index.place(code: "MTR-ADM")?.code == "MTR-ADM")
    }

    @Test("a decoded route section exposes canonical codes")
    func decodedRouteSectionIsCanonical() throws {
        let json = #"{"from_n02_station_code":"TKL-POA-MTR-NOP","to_n02_station_code":"LR-614P-LR-1"}"#
        let section = try JSONDecoder().decode(RouteSection.self, from: Data(json.utf8))
        #expect(section.fromN02StationCode == "MTR-NOP")
        #expect(section.toN02StationCode == "LR-1")
    }
}
