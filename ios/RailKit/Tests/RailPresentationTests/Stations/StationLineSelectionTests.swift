import Foundation
import RailCore
import Testing

@testable import RailPresentation

struct StationLineSelectionTests {
    private let catalog = Fixture.catalog

    @Test func preferencesKeepKeihanMainLineDistinctFromTheOtherMainLine() {
        let keihan = catalog.operators(in: "jp").first { $0.id == "jp|Keihan" }
        #expect(keihan?.name == "Keihan")

        let only = CatalogLinePreferenceMapping.preferences(
            lineIDs: ["keihan-honsen"], regionCode: "jp", catalog: catalog)
        #expect(only.lineNames == ["本線"])
        #expect(only.operatorNames == [keihan?.name ?? ""])

        let matched = CatalogLinePreferenceMapping.matching(
            lineNames: only.lineNames, operatorNames: only.operatorNames,
            regionCode: "jp", catalog: catalog)
        #expect(matched.lineIDs == ["keihan-honsen"])
        #expect(matched.unresolvedNames.isEmpty)
    }

    @Test func preferencesCollapseTwoMainLinesToOneNameAndBothOperators() {
        let both = CatalogLinePreferenceMapping.preferences(
            lineIDs: ["midosuji", "keihan-honsen"], regionCode: "jp", catalog: catalog)
        #expect(both.lineNames == ["本線"])
        #expect(both.operatorNames == ["Keihan", "Osaka Metro"])

        let matched = CatalogLinePreferenceMapping.matching(
            lineNames: both.lineNames, operatorNames: both.operatorNames,
            regionCode: "jp", catalog: catalog)
        #expect(matched.lineIDs == ["keihan-honsen", "midosuji"])
        #expect(matched.unresolvedNames.isEmpty)
    }

    @Test func matchingUnresolvedWhenMainLineHasNoOperatorAndTwoLinesShareIt() {
        let matched = CatalogLinePreferenceMapping.matching(
            lineNames: ["本線"], operatorNames: [], regionCode: "jp", catalog: catalog)
        #expect(matched.lineIDs.isEmpty)
        #expect(matched.unresolvedNames == ["本線"])
    }
}

private enum Fixture {
    static let catalog = EditorCatalogBuilder.build([
        line("yamanote", name: "山手線", operatorName: "JR East", stations: [
            station("TYO", name: "Tokyo"),
            station("KAN", name: "Kanda"),
        ]),
        line("chuo", name: "中央線", operatorName: "JR East", stations: [
            station("TYO", name: "Tokyo"),
            station("SJK", name: "Shinjuku"),
        ]),
        line("midosuji", name: "本線", operatorName: "Osaka Metro", stations: [
            station("NAM", name: "Namba"),
            station("UMD", name: "Umeda"),
        ]),
        line("keihan-honsen", name: "本線", operatorName: "Keihan", stations: [
            station("YOD", name: "淀屋橋"),
        ]),
        line("kintetsu", name: "なんば線", operatorName: "Kintetsu", stations: [
            station("NAM", name: "Namba"),
            station("UMD", name: "Umeda"),
        ]),
        line("L", region: "tw", name: "L", operatorName: "Metro", stations: [
            station("TYO", name: "Tokyo Metro", nameRoma: "Tokyo"),
        ]),
    ])

    private static func line(
        _ id: String,
        region: String = "jp",
        name: String,
        operatorName: String,
        stations: [EditorCatalogStationSource]
    ) -> EditorCatalogLineSource {
        EditorCatalogLineSource(
            regionCode: region, lineID: id, name: name, operatorName: operatorName, stations: stations)
    }

    private static func station(
        _ sourceCode: String, name: String, nameRoma: String? = nil
    ) -> EditorCatalogStationSource {
        EditorCatalogStationSource(
            sourceCode: sourceCode, name: name, nameRoma: nameRoma, longitude: 0, latitude: 0)
    }
}
