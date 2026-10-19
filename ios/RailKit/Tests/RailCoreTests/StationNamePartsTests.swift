import Foundation
import Testing

@testable import RailCore

struct StationNamePartsTests {
    @Test("lookup uses the stored field and folds bracket width")
    func lookupAndWidthFold() {
        let record = StationNameRecord(
            base: "西鉄福岡", bracket: "天神", kind: .subname, position: .suffix)
        let infix = StationNameRecord(
            base: "上環 總站", bracket: "西港城", kind: .subname, position: .infix)
        let directory = StationNameDirectory(
            bracketedNames: [
                "西鉄福岡（天神）": record,
                "上環 (西港城) 總站": infix,
            ],
            baseNameCounts: ["西鉄福岡": 1, "上環 總站": 0])
        #expect(directory.parts(forOfficialName: "西鉄福岡（天神）") == record)
        #expect(directory.parts(forOfficialName: "西鉄福岡(天神)") == record)
        #expect(directory.parts(forOfficialName: "上環 (西港城) 總站")?.position == .infix)
        #expect(directory.parts(forOfficialName: "上環 (西港城) 總站")?.base == "上環 總站")
        let leading = directory.leadingOfficialName(in: "西鉄福岡(天神) (JP, 天神大牟田線)")
        #expect(leading?.official == "西鉄福岡（天神）")
        #expect(leading?.remainder == "(JP, 天神大牟田線)")
        let tight = directory.leadingOfficialName(in: "西鉄福岡（天神）(JP, 天神大牟田線)")
        #expect(tight?.official == "西鉄福岡（天神）")
        #expect(tight?.remainder == "(JP, 天神大牟田線)")
        #expect(directory.officialNames(withBase: "西鉄福岡") == ["西鉄福岡（天神）"])
        #expect(directory.baseNameCounts["上環 總站"] == 0)
        #expect(directory.parts(forOfficialName: "東京") == nil)
    }

    @Test("closed and historical markers decode, and an old bundle still decodes")
    func decodesStatusAndOldBundle() throws {
        let closed = try JSONDecoder().decode(StationNameRecord.self, from: Data("""
        {"base":"旧駅","bracket":"廃止","kind":"status","position":"suffix","status":"closed"}
        """.utf8))
        #expect(closed.kind == .status)
        #expect(closed.status == .closed)
        let historical = try JSONDecoder().decode(StationNameRecord.self, from: Data("""
        {"base":"元町","bracket":"旧","kind":"status","status":"historical","position":"suffix"}
        """.utf8))
        #expect(historical.status == .historical)
        let subname = try JSONDecoder().decode(StationNameRecord.self, from: Data("""
        {"base":"西鉄福岡","bracket":"天神","kind":"subname","position":"suffix"}
        """.utf8))
        #expect(subname.status == nil)
        let bundle = try JSONDecoder().decode(RegistryBundle.self, from: Data("""
        {"schema":"jtm-registry-bundle/1","region":"jp","run":1,"stationCodes":{},"groupCodes":{},"operators":{},"stationOperator":{},"lines":{}}
        """.utf8))
        #expect(bundle.bracketedNames.isEmpty)
        #expect(bundle.baseNameCounts.isEmpty)
        let directory = StationNameDirectory(bundle: RegistryBundle(
            region: "cn", run: 1,
            bracketedNames: ["洞噶（预留）": StationNameRecord(
                base: "洞噶", bracket: "预留", kind: .status, status: .reserved, position: .suffix)],
            baseNameCounts: ["洞噶": 1]))
        #expect(directory.parts(forOfficialName: "洞噶（预留）")?.status == .reserved)
    }
}
