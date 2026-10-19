import Foundation
import Testing

@testable import RailCore

struct ChinaRegionTests {
    @Test("China starter uses only the China HSR identities and admits both operators")
    func blankItinerary() throws {
        let train = StoreOperations.createBlankTrain(country: "cn")
        #expect(train.region == "cn")
        #expect(train.stops.map(\.n02StationCode) == ["CN-12306-IOQ", "CN-12306-XJA"])
        #expect(train.routeSections?.first?.lineIDs == ["cn-guangshengan-hsr"])
        #expect(train.routeSections?.first?.operatorNames?.isEmpty != false)
        #expect(train.routePolicy?.preferredOperatorNames?.isEmpty != false)
        #expect(train.routePolicy?.allowedInstitutionTypeCodes == ["1"])
        #expect(train.routePolicy?.allowBrowserStraightLineFallback == false)
        try TrainValidation.validateSupportedRegions(train)
    }

    @Test("China journeys survive the JSON import and export boundary")
    func importAndExport() throws {
        var original = StoreOperations.createBlankTrain(country: "cn")
        original.number = "G1"
        let imported = try TrainValidation.normalizeImportedTrain(
            StoreOperations.json(original), country: "cn")
        #expect(imported.region == "cn")
        #expect(imported.stops.map(\.n02StationCode) == original.stops.map(\.n02StationCode))
        #expect(imported.routeSections?.first?.lineIDs == ["cn-guangshengan-hsr"])
        let decoded = try JSONDecoder().decode(Train.self, from: JSONEncoder().encode(imported))
        #expect(decoded.region == "cn")
        #expect(decoded.stops.last?.n02StationCode == "CN-12306-XJA")
    }

    @Test("China institution codes select exclusive railway categories")
    func railwayCategories() {
        let cases: [(String, String, Int)] = [
            ("11", "1", Statistics.maskHSR),
            ("11", "2", Statistics.maskCONV),
            ("11", "3", Statistics.maskMETRO),
            ("11", "4", Statistics.maskPRIV),
            ("21", "3", Statistics.maskTRAM),
            ("31", "4", Statistics.maskPRIV),
        ]
        for (railwayClass, institution, expected) in cases {
            let props = Statistics.SectionProperties(
                n02_001: .string(railwayClass), n02_002: .string(institution))
            #expect(Statistics.classifySectionMask(props, country: "cn") == expected)
        }
        #expect(Statistics.categories(country: "cn").map(\.mask) == [
            Statistics.maskHSR, Statistics.maskCONV, Statistics.maskMETRO,
            Statistics.maskTRAM, Statistics.maskPRIV,
        ])
        #expect(Statistics.filterCategoryForMask(Statistics.maskCONV, country: "cn") == "jr")
    }

    @Test("China service names and numbered prefixes follow the shared web classification")
    func serviceGroups() {
        for text in ["高铁", "高鐵", "高速铁路", "动车", "動車", " G123 ", "d8", "c", "\u{FEFF}g123"] {
            #expect(Statistics.serviceGroupOfTrain(trainType: text, country: "cn") == "hsr")
        }
        for text in ["直达", "直達", "特快", "快速", "z9", "T", "k8"] {
            #expect(Statistics.serviceGroupOfTrain(trainType: text, country: "cn") == "ltd")
        }
        for text in ["地铁", "G123 service", "CG123", "g１２", "普快", ""] {
            #expect(Statistics.serviceGroupOfTrain(trainType: text, country: "cn") == "other")
        }
    }

    @Test("12306 telegraph identities are labeled separately from TDX")
    func stationCodeSource() {
        for code in ["CN-12306-IOQ", "CN-12306-XJA", " CN-12306-XJA "] {
            #expect(Stations.stationCodeSystem(code) == "CN-12306")
            #expect(TrainValidation.stationCodeSystem(code) == "CN-12306")
            #expect(Stations.stationCodeFieldLabel(code) == "12306")
        }
        for code in ["CN-OSM-N123456789", " CN-OSM-N123456789 "] {
            #expect(Stations.stationCodeSystem(code) == "CN-OSM")
            #expect(TrainValidation.stationCodeSystem(code) == "CN-OSM")
            #expect(Stations.stationCodeFieldLabel(code) == "OSM")
        }
        #expect(Stations.stationCodeSystem("CN-OSM-N") == "TDX")
        #expect(TrainValidation.stationCodeSystem("CN-OSM-N") == "TDX")
        #expect(Stations.stationCodeSystem("CN-OSM-N１２") == nil)
        #expect(TrainValidation.stationCodeSystem("CN-OSM-N１２") == nil)
        #expect(Stations.stationCodeSystem("TRA-1000") == "TDX")
        #expect(Stations.stationCodeSystem("MTR-HOK") == "TDX")
        #expect(Stations.stationCodeSystem("CN-12306-XJ") == "TDX")
        #expect(TrainValidation.stationCodeSystem("CN-12306-XJ") == "TDX")
    }

    @Test("China mileage reference date follows Beijing time at the Japan day boundary")
    func statisticsReferenceDay() {
        let evening = Date(timeIntervalSince1970: 1_787_844_600)
        #expect(Statistics.statisticsReferenceDate(country: "cn", now: evening) == "2026-08-27")
        #expect(Statistics.statisticsReferenceDate(country: "jp", now: evening) == "2026-08-28")
    }

    @Test("China station names replace the base name in the selected language")
    func localizedStationNames() throws {
        let row = Localization.StationReadingRow(
            zhHant: "香港西九龍", zhHans: "香港西九龙", ja: "香港西九龍", en: "Hong Kong West Kowloon")
        let table = Localization.StationReadings(country: "cn", byCode: ["CN-12306-XJA": row])
        let catalog = try Localization.Catalog(data: Data(
            #"{"sourceLanguage":"en","version":"1.0","strings":{}}"#.utf8))
        let localization = Localization(catalog: catalog, language: .en, country: "cn", stationReadings: table)
        #expect(localization.country == "cn")
        #expect(table.country == "CN")
        #expect(localization.stationName("香港西九龙", code: "CN-12306-XJA") == "Hong Kong West Kowloon")
        #expect(localization.nameReadingsTyped("香港西九龙", code: "CN-12306-XJA").isEmpty)
        #expect(Stations.Readings(byCode: [:], byName: [:], country: "cn").declaredCountry == "CN")
    }
}
