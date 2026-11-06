import Foundation
import RailCore
import Testing
@testable import RailPresentation

struct StatisticsLineCoverageTests {
    private typealias Totals = [(name: String, byMask: [Int: Double])]
    private typealias Ridden = Statistics.OrderedDictionary<String, [Int: Double]>

    @Test(arguments: [Statistics.maskHSR, Statistics.maskMETRO, Statistics.maskCONV, Statistics.maskJR])
    func categoryVisibilityAndMaskSpecificMileage(mask: Int) {
        let totals: Totals = [
            ("ridden", [mask: 10]), ("unridden", [mask: 20]),
            ("zero", [mask: 0]), ("negative", [mask: -1]), ("other mask", [128: 10])
        ]
        var ridden = Ridden()
        ridden["ridden"] = [mask: 2.5, 128: 50]
        ridden["unridden"] = [128: 5]
        let rows = StatisticsLineCoverage.rows(mask: mask, totals: totals, operators: [:], ridden: ridden)
        #expect(rows.map(\.name) == ((mask == Statistics.maskHSR || mask == Statistics.maskMETRO)
            ? ["ridden", "unridden"] : ["ridden"]))
        #expect(rows.first?.total == 10)
        #expect(rows.first?.ridden == 2.5)
        #expect(rows.first?.percent == 25)
    }

    @Test func rawOperatorGroupingNumericOrderAndUnknownLast() {
        let mask = Statistics.maskMETRO
        let totals: Totals = [
            ("unknown", [mask: 1]), ("10号線", [mask: 1]), ("2号線", [mask: 1]),
            ("1号線", [mask: 1]), ("other operator", [mask: 1])
        ]
        let rows = StatisticsLineCoverage.rows(mask: mask, totals: totals,
            operators: ["10号線": "A", "2号線": "A", "1号線": "A", "other operator": "B"],
            ridden: Ridden())
        #expect(rows.map(\.name) == ["1号線", "2号線", "10号線", "other operator", "unknown"])
        #expect(rows.last?.operatorName == "")
        #expect(rows.last?.company == "")
    }

    @Test func rawIdentityCompanyLabelAndUnroundedNumbers() throws {
        let total = 3.7
        let distance = 4.125
        var ridden = Ridden()
        ridden["東海道線"] = [Statistics.maskJR: distance]
        let row = try #require(StatisticsLineCoverage.rows(
            mask: Statistics.maskJR, totals: [("東海道線", [Statistics.maskJR: total])],
            operators: ["東海道線": "東海旅客鉄道"], ridden: ridden).first)
        #expect(row.company == "JR東海")
        #expect(row.operatorName == "東海旅客鉄道")
        #expect(row.id == "東海旅客鉄道\u{001F}東海道線")
        #expect(row.total.bitPattern == total.bitPattern)
        #expect(row.ridden.bitPattern == distance.bitPattern)
        #expect(row.percent.bitPattern == (100 * distance / total).bitPattern)
        #expect(row.percent > 100)
    }

    @Test func widgetCountsPhysicalLinesOnceAcrossOverlappingJapaneseCategories() {
        let totals: Totals = [
            ("Conventional", [Statistics.maskCONV: 20, Statistics.maskJR: 20]),
            ("High speed", [Statistics.maskHSR: 100, Statistics.maskJR: 100]),
            ("Mixed", [Statistics.maskCONV: 10, Statistics.maskHSR: 30, Statistics.maskJR: 40]),
            ("Partly ridden mixed", [Statistics.maskCONV: 20, Statistics.maskHSR: 10, Statistics.maskJR: 30]),
            ("Metro", [Statistics.maskCONV: 20, Statistics.maskMETRO: 20]),
        ]
        var ridden = Ridden()
        ridden["Conventional"] = [Statistics.maskCONV: 10, Statistics.maskJR: 10]
        ridden["High speed"] = [Statistics.maskHSR: 25, Statistics.maskJR: 25]
        ridden["Mixed"] = [Statistics.maskCONV: 5, Statistics.maskHSR: 15, Statistics.maskJR: 20]
        ridden["Partly ridden mixed"] = [Statistics.maskHSR: 10, Statistics.maskJR: 10]
        ridden["Metro"] = [Statistics.maskCONV: 5, Statistics.maskMETRO: 5]
        let rows = StatisticsLineCoverage.widgetRows(
            masks: Statistics.categories(country: "jp").map(\.mask),
            totals: totals, operators: [:], ridden: ridden)
        #expect(rows.count == 5)
        #expect(Set(rows.map(\.id)).count == rows.count)
        #expect(rows.first { $0.name == "Conventional" }?.percent == 50)
        #expect(rows.first { $0.name == "High speed" }?.percent == 25)
        #expect(rows.first { $0.name == "Mixed" }?.total == 40)
        #expect(rows.first { $0.name == "Mixed" }?.ridden == 20)
        #expect(rows.first { $0.name == "Partly ridden mixed" }?.total == 30)
        #expect(rows.first { $0.name == "Partly ridden mixed" }?.ridden == 10)
        #expect(rows.first { $0.name == "Metro" }?.total == 20)
        #expect(rows.first { $0.name == "Metro" }?.ridden == 5)
    }

    @Test func widgetKeepsLargestCategoryMeasureAndForeignMetroInAllRegionVocabulary() {
        let totals: Totals = [
            ("Mixed regional", [Statistics.maskCONV: 20, Statistics.maskMETRO: 10]),
            ("Unridden metro", [Statistics.maskMETRO: 5]),
            ("Unridden conventional", [Statistics.maskCONV: 5]),
        ]
        var ridden = Ridden()
        ridden["Mixed regional"] = [Statistics.maskCONV: 5, Statistics.maskMETRO: 5]
        let rows = StatisticsLineCoverage.widgetRows(
            masks: Statistics.categories(country: "jp").map(\.mask),
            totals: totals, operators: [:], ridden: ridden)
        #expect(rows.count == 2)
        #expect(rows.first { $0.name == "Mixed regional" }?.total == 20)
        #expect(rows.first { $0.name == "Mixed regional" }?.ridden == 5)
        #expect(rows.first { $0.name == "Unridden metro" }?.percent == 0)
    }

    @Test func emptyInputsAndCollatorTiesPreserveEncounterOrder() {
        #expect(StatisticsLineCoverage.rows(mask: Statistics.maskHSR, totals: [],
                                            operators: [:], ridden: Ridden()).isEmpty)
        // Duplicate display keys deliberately exercise an equal-sort-key pair.
        // The mileage values let us observe their original encounter order.
        let rows = StatisticsLineCoverage.rows(mask: Statistics.maskHSR,
            totals: [("same", [Statistics.maskHSR: 2]), ("same", [Statistics.maskHSR: 1])],
            operators: [:], ridden: Ridden())
        #expect(rows.map(\.total) == [2, 1])
    }

    @Test func selectedExistingStatisticsFixtureRetainsKnownLineDetail() throws {
        struct Line: Decodable { let line: String; let byCat: [String: Double] }
        struct Operator: Decodable { let line: String; let `operator`: String }
        struct Index: Decodable {
            let country: String
            let lineTotByCat: [Line]
            let lineOperator: [Operator]
        }
        struct Aggregate: Decodable {
            struct Value: Decodable { let lineRidByCat: [Line] }
            let country: String
            let label: String
            let aggregate: Value
        }
        struct Fixture: Decodable { let indexes: [Index]; let aggregates: [Aggregate] }
        var directory = URL(filePath: #filePath).deletingLastPathComponent()
        for _ in 0..<8 {
            if FileManager.default.fileExists(atPath: directory.appending(path: "port-fixtures").path) {
                break
            }
            directory.deleteLastPathComponent()
        }
        let fixture = try JSONDecoder().decode(Fixture.self, from: Data(contentsOf:
            directory.appending(path: "port-fixtures/stats.json")))
        let index = try #require(fixture.indexes.first { $0.country == "jp" })
        let aggregate = try #require(fixture.aggregates.first { $0.country == "jp" && $0.label == "single" })
        func masks(_ value: [String: Double]) -> [Int: Double] {
            Dictionary(uniqueKeysWithValues: value.compactMap { key, value in
                Int(key).map { ($0, value) }
            })
        }
        let totals: Totals = index.lineTotByCat.map { ($0.line, masks($0.byCat)) }
        let operators = Dictionary(uniqueKeysWithValues: index.lineOperator.map { ($0.line, $0.operator) })
        var ridden = Ridden()
        for line in aggregate.aggregate.lineRidByCat { ridden[line.line] = masks(line.byCat) }
        let expectedCounts = [1: 11, 2: 5, 4: 5, 8: 46, 16: 0, 32: 0]
        for mask in [1, 2, 4, 8, 16, 32] {
            let rows = StatisticsLineCoverage.rows(mask: mask, totals: totals,
                                                   operators: operators, ridden: ridden)
            #expect(rows.count == expectedCounts[mask])
            if mask == Statistics.maskCONV || mask == Statistics.maskJR {
                #expect(rows.map(\.name) == ["山手線", "根岸線", "横浜線", "御殿場線", "東海道線"])
                for row in rows {
                    let source = totals.first { $0.name == row.name }
                    #expect(row.total.bitPattern == source?.byMask[mask]?.bitPattern)
                    #expect(row.ridden.bitPattern == ridden[row.name]?[mask]?.bitPattern)
                    #expect(row.operatorName == operators[row.name])
                }
            }
        }
    }
}
