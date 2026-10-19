import Foundation
import Testing

@testable import RailCore

struct StationLabelTests {
    @Test("station card status words")
    func stationCardStatusWords() throws {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("RailMap/Localization/StationCardStrings.swift")
        let source = try String(contentsOf: url, encoding: .utf8)
        func entry(_ key: String, language: String, word: String) {
            guard let start = source.range(of: "\"ios.station.status.\(key)\"") else {
                Issue.record("missing \(key)")
                return
            }
            let tail = source[start.lowerBound...]
            guard let end = tail.range(of: "],") else {
                Issue.record("unterminated \(key)")
                return
            }
            let block = String(tail[..<end.upperBound])
            #expect(block.contains(".\(language): \"\(word)\""), "\(key) \(language) \(word)")
        }
        entry("reserved", language: "ja", word: "予備")
        entry("planned", language: "ja", word: "計画中")
        entry("reserved", language: "en", word: "Reserved")
        entry("planned", language: "en", word: "Planned")
        entry("closed", language: "en", word: "Closed")
        entry("suspended", language: "en", word: "Suspended")
        entry("historical", language: "en", word: "Former")
        entry("reserved", language: "zhHans", word: "预留")
        entry("planned", language: "zhHans", word: "规划")
        entry("closed", language: "zhHans", word: "停用")
        entry("suspended", language: "zhHans", word: "暂停")
        entry("historical", language: "zhHans", word: "历史")
        entry("reserved", language: "zhHant", word: "預留")
        entry("planned", language: "zhHant", word: "規劃")
        entry("closed", language: "zhHant", word: "停用")
        entry("suspended", language: "zhHant", word: "暫停")
        entry("historical", language: "zhHant", word: "歷史")
    }

    @Test("a repeated line name takes the operator short label")
    func qualifiedLineNames() {
        #expect(StationLabel.qualifiedLineName("本線", operatorName: "京成電鉄") == "京成本線")
        #expect(StationLabel.qualifiedLineName("本線", operatorName: "阪神電気鉄道") == "阪神本線")
        #expect(StationLabel.qualifiedLineName("東海道線", operatorName: "東海旅客鉄道") == "JR東海 東海道線")
        #expect(StationLabel.qualifiedLineName("京王線", operatorName: "京王電鉄") == "京王線")
        #expect(StationLabel.lineLabel(name: "本線", operatorName: "京成電鉄", uniqueInCountry: true) == "本線")
        #expect(StationLabel.lineLabel(name: "本線", operatorName: "京成電鉄", uniqueInCountry: false) == "京成本線")
    }

    @Test("labels, transfer, search order, and the spoken country")
    func forms() {
        #expect(StationLabel.full(name: "府中", countryCode: "JP", lineLabel: "京王線") == "府中 (JP, 京王線)")
        #expect(StationLabel.transfer(name: "府中", countryCode: "JP", from: "京王線", to: "南武線")
            == "府中 (JP, 京王線 → 南武線)")
        #expect(StationLabel.caption(countryCode: "JP", detail: nil) == "(JP)")
        #expect(StationLabel.caption(countryCode: "JP", detail: "京王線") == "(JP, 京王線)")
        #expect(StationLabel.accessibility(
            name: "府中", countryCode: "JP", spokenDetail: "京王線", countryName: "日本")
            == "府中，日本，京王線")
        #expect(StationLabel.accessibility(
            name: "府中", countryCode: "JP", spokenDetail: "京王線", countryName: nil)
            == "府中，JP，京王線")
        #expect(StationLabel.accessibility(
            name: "府中", countryCode: "JP", spokenDetail: "", countryName: "日本")
            == "府中，日本")

        let lines = [
            StationLabel.LineChoice(id: "n", label: "南武線", rank: 5, name: "南武線"),
            StationLabel.LineChoice(id: "k", label: "京王線", rank: 1, name: "京王線"),
            StationLabel.LineChoice(id: "c", label: "中央線", rank: 0, name: "中央線"),
        ]
        #expect(StationLabel.search(
            name: "府中", countryCode: "JP", lines: lines, contextLineIDs: ["n"])
            == "府中 (JP, 南武線・中央線 +1)")
        #expect(StationLabel.search(
            name: "府中", countryCode: "JP", lines: lines, contextLineIDs: [])
            == "府中 (JP, 中央線・京王線 +1)")
        let ordered = StationLabel.orderedLines(lines + lines, contextLineIDs: ["n"]).map(\.id)
        #expect(ordered == ["n", "c", "k"])
    }

    @Test("a line name is qualified only when the country has two of them")
    func uniquenessInTheCatalog() {
        let catalog = EditorCatalogBuilder.build([
            source("keisei", "本線", "京成電鉄", rank: 3, stations: [("S1", "住吉", 139.8, 35.7)]),
            source("hanshin", "本線", "阪神電気鉄道", rank: 4, stations: [("S2", "住吉", 135.4, 34.7)]),
            source("keio", "京王線", "京王電鉄", rank: 1, stations: [("F1", "府中", 139.48, 35.67)]),
            source("jr-c", "東海道線", "東海旅客鉄道", rank: 2, stations: [("T1", "東京", 139.7, 35.6)]),
            source("jr-e", "東海道線", "東日本旅客鉄道", rank: 2, stations: [("T2", "東京", 140.0, 36.0)]),
        ])
        let labels = StationLabel.lineLabels(in: catalog, regionCode: "jp")
        #expect(labels["keisei"] == "京成本線")
        #expect(labels["hanshin"] == "阪神本線")
        #expect(labels["keio"] == "京王線")
        #expect(labels["jr-c"] == "JR東海 東海道線")
        #expect(labels["jr-e"] == "JR東日本 東海道線")

        let fuchu = catalog.station(StationKey(regionCode: "jp", sourceCode: "F1"))
        let text = StationLabel.text(for: fuchu!, catalog: catalog, labels: labels)
        #expect(text.qualifier == "(JP, 京王線)")
        #expect(text.full == "府中 (JP, 京王線)")
        #expect(text.spokenDetail == "京王線")

        let tokyo = catalog.station(StationKey(regionCode: "jp", sourceCode: "T1"))
        let both = StationLabel.text(for: tokyo!, catalog: catalog, labels: labels)
        #expect(both.full == "東京 (JP, JR東海 東海道線)")
        #expect(StationLabel.qualifiersBySourceCode(in: catalog, regionCode: "jp")["F1"] == "(JP, 京王線)")
    }

    @Test("status shows the base, and copy keeps the official name")
    func statusDisplayAndRoundTrip() {
        let reserved = StationNameRecord(
            base: "洞噶", bracket: "预留", kind: .status, status: .reserved, position: .suffix)
        let qualifier = StationLabel.caption(countryCode: "CN", detail: "某线")
        let face = StationLabel.presented(
            officialName: "洞噶（预留）", qualifier: qualifier, parts: reserved, statusWord: "预留")
        #expect(face.label == "洞噶")
        #expect(face.secondary == "预留 · (CN, 某线)")
        #expect(face.copy == "洞噶（预留） (CN, 某线)")
        let english = StationLabel.presented(
            officialName: "洞噶（预留）", qualifier: qualifier, parts: reserved, statusWord: "Reserved")
        #expect(english.secondary == "Reserved · 预留 · (CN, 某线)")
        #expect(english.copy == face.copy)

        let closed = StationNameRecord(
            base: "旧駅", bracket: "廃止", kind: .status, status: .closed, position: .suffix)
        #expect(StationLabel.presented(
            officialName: "旧駅（廃止）", qualifier: "(JP)", parts: closed, statusWord: "廃止").label == "旧駅")
        let historical = StationNameRecord(
            base: "元町", bracket: "旧", kind: .status, status: .historical, position: .suffix)
        #expect(StationLabel.presented(
            officialName: "元町（旧）", qualifier: "(JP, 山手線)", parts: historical, statusWord: "Historical"
        ).secondary == "Historical · 旧 · (JP, 山手線)")

        let subname = StationNameRecord(
            base: "西鉄福岡", bracket: "天神", kind: .subname, position: .suffix)
        let kept = StationLabel.presented(
            officialName: "西鉄福岡（天神）", qualifier: "(JP, 天神大牟田線)", parts: subname, statusWord: nil)
        #expect(kept.label == "西鉄福岡（天神）")
        #expect(kept.secondary == "(JP, 天神大牟田線)")
        #expect(kept.copy == "西鉄福岡（天神） (JP, 天神大牟田線)")
        let infix = StationNameRecord(
            base: "上環 總站", bracket: "西港城", kind: .subname, position: .infix)
        #expect(StationLabel.presented(
            officialName: "上環 (西港城) 總站", qualifier: "(HK)", parts: infix, statusWord: nil
        ).label == "上環 (西港城) 總站")

        let directory = StationNameDirectory(
            bracketedNames: ["洞噶（预留）": reserved], baseNameCounts: ["洞噶": 1])
        let parsed = StationReference.parse(face.copy, names: directory)
        #expect(parsed?.name == "洞噶（预留）")
        #expect(parsed?.country == "CN")
        #expect(parsed?.line == "某线")
    }

    private func source(
        _ id: String, _ name: String, _ operatorName: String, rank: Int,
        stations: [(String, String, Double, Double)]
    ) -> EditorCatalogLineSource {
        EditorCatalogLineSource(
            regionCode: "jp", lineID: id, name: name, operatorName: operatorName,
            stations: stations.map {
                EditorCatalogStationSource(sourceCode: $0.0, name: $0.1, longitude: $0.2, latitude: $0.3)
            },
            rank: rank)
    }
}
