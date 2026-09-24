import Foundation
import Testing

@testable import RailCore

struct EditorCatalogTests {

    @Test func sameDisplayNameWithDifferentLineIDsStaysTwoLines() {
        let catalog = EditorCatalogBuilder.build([
            sourceLine("line-a", name: "本線", operatorName: "JR East"),
            sourceLine("line-b", name: "本線", operatorName: "Tokyo Metro"),
        ])

        #expect(catalog.line(id: "line-a", regionCode: "jp")?.name == "本線")
        #expect(catalog.line(id: "line-b", regionCode: "jp")?.name == "本線")
        #expect(catalog.operators(in: "jp").map(\.id) == ["jp|JR East", "jp|Tokyo Metro"])
        let east = catalog.lines(operatorID: "jp|JR East").map(\.id)
        let metro = catalog.lines(operatorID: "jp|Tokyo Metro").map(\.id)
        #expect(east == ["line-a"])
        #expect(metro == ["line-b"])
        #expect(east.allSatisfy { !metro.contains($0) })
    }

    @Test func linesInRegionReturnsBothLinesThatShareADisplayName() {
        let catalog = EditorCatalogBuilder.build([
            sourceLine("line-b", name: "本線", operatorName: "Tokyo Metro"),
            sourceLine("line-a", name: "本線", operatorName: "JR East"),
            sourceLine("other", region: "us", name: "本線", operatorName: "Metro"),
        ])

        let lines = catalog.lines(in: "jp")
        #expect(lines.map(\.id) == ["line-a", "line-b"])
        #expect(lines.map(\.name) == ["本線", "本線"])
    }

    @Test func linesInRegionOrdersByNameThenID() {
        let catalog = EditorCatalogBuilder.build([
            sourceLine("z-line", name: "山手線", operatorName: "JR East"),
            sourceLine("a-line", name: "中央線", operatorName: "JR East"),
            sourceLine("m-line", name: "中央線", operatorName: "Tokyo Metro"),
        ])

        #expect(catalog.lines(in: "jp").map(\.id) == ["a-line", "m-line", "z-line"])
        #expect(catalog.stations(in: "jp").isEmpty)
    }

    @Test func oneStationOnTwoLinesKeepsArrayOrder() {
        let sharedOnLaterLine = station("S1", name: "中央", longitude: 10, latitude: 1)
        let sharedOnEarlierID = station("S1", name: "中央駅", nameRoma: "Chuo", longitude: 20, latitude: 2)
        let catalog = EditorCatalogBuilder.build([
            sourceLine("m-line", operatorName: "JR East", stations: [sharedOnLaterLine]),
            sourceLine(
                "a-line", operatorName: "Metro",
                stations: [
                    station("E", name: "東", longitude: 140, latitude: 35),
                    station("W", name: "西", longitude: 130, latitude: 36),
                    sharedOnEarlierID,
                ]),
        ])

        let key = StationKey(regionCode: "jp", sourceCode: "S1")
        #expect(catalog.memberships(stationKey: key).map(\.lineID) == ["a-line", "m-line"])
        #expect(catalog.memberships(stationKey: key).map(\.membershipID) == [
            "jp|a-line|S1|2", "jp|m-line|S1|0",
        ])
        #expect(catalog.station(key)?.longitude == 20)
        #expect(catalog.station(key)?.latitude == 2)
        #expect(catalog.station(key)?.aliases == ["Chuo"])

        let along = catalog.memberships(lineID: "a-line", regionCode: "jp")
        #expect(along.map(\.sequence) == [0, 1, 2])
        #expect(along.map(\.longitude) == [140, 130, 20])
        #expect(along.map(\.stationKey.sourceCode) == ["E", "W", "S1"])
        #expect(catalog.memberships(lineID: "m-line", regionCode: "jp").map(\.sequence) == [0])
    }

    @Test func sameSourceCodeInTwoRegionsIsTwoStations() {
        let catalog = EditorCatalogBuilder.build([
            sourceLine("yamanote", region: "jp", operatorName: "JR East", stations: [
                station("S1", name: "Central", nameRoma: "Sentoraru"),
            ]),
            sourceLine("red", region: "us", operatorName: "Metro", stations: [
                station("S1", name: "Central"),
            ]),
        ])

        let japan = StationKey(regionCode: "jp", sourceCode: "S1")
        let states = StationKey(regionCode: "us", sourceCode: "S1")
        #expect(japan != states)
        #expect(catalog.station(japan)?.key.sourceCode == "S1")
        #expect(catalog.station(states)?.key.sourceCode == "S1")

        let both = catalog.candidates(named: "  central ", regionCode: nil)
        #expect(both.map(\.key) == [japan, states])
        #expect(catalog.candidates(named: "Central", regionCode: "jp").map(\.key) == [japan])
        #expect(catalog.candidates(named: "Sentoraru", regionCode: nil).map(\.key) == [japan])
        #expect(catalog.candidates(named: "Central", regionCode: "us").map(\.key) == [states])
    }

    @Test func indexesHaveNoDanglingReferencesAndBuildIsStable() {
        let sources = [
            sourceLine("line-a", name: "本線", nameNorm: "本", nameRoma: "Main", operatorName: "JR East", operatorShort: "JR", stations: [
                station("S1", name: "東京", nameRoma: "Tokyo", longitude: 139.7, latitude: 35.7),
                station("S2", name: "品川", longitude: 139.7, latitude: 35.6),
            ]),
            sourceLine("line-b", name: "南北線", operatorName: "Tokyo Metro", stations: [
                station("S1", name: "東京", longitude: 139.8, latitude: 35.7),
            ]),
            sourceLine("red", region: "us", operatorName: "Metro", stations: [
                station("S9", name: "Union", longitude: -122.0, latitude: 47.0),
            ]),
        ]
        let catalog = EditorCatalogBuilder.build(sources)
        let again = EditorCatalogBuilder.build(sources)

        #expect(catalog.issues.isEmpty)
        #expect(!catalog.issues.contains(.dangling))
        let regions = ["jp", "us"]
        #expect(identity(catalog, regions: regions) == identity(again, regions: regions))

        var membershipIDs: [String] = []
        for region in regions {
            for op in catalog.operators(in: region) {
                for line in catalog.lines(operatorID: op.id) where line.regionCode == region {
                    #expect(catalog.line(id: line.id, regionCode: region) != nil)
                    for membership in catalog.memberships(lineID: line.id, regionCode: region) {
                        #expect(catalog.station(membership.stationKey) != nil)
                        #expect(catalog.line(id: membership.lineID, regionCode: membership.regionCode) != nil)
                        #expect(membership.regionCode == region)
                        membershipIDs.append(membership.membershipID)
                        for back in catalog.memberships(stationKey: membership.stationKey) {
                            #expect(catalog.line(id: back.lineID, regionCode: back.regionCode) != nil)
                            #expect(catalog.station(back.stationKey) != nil)
                        }
                    }
                }
            }
        }
        #expect(Set(membershipIDs).count == membershipIDs.count)
        #expect(catalog.line(id: "line-a", regionCode: "jp")?.aliases == ["Main", "本"])
    }

    @Test func operatorShortIsAnAliasNotAnotherOperator() {
        let catalog = EditorCatalogBuilder.build([
            sourceLine("line-a", operatorName: "JR East", operatorShort: "JR"),
            sourceLine("line-b", operatorName: "JR East", operatorShort: "JR East"),
        ])

        #expect(catalog.operators(in: "jp").map(\.id) == ["jp|JR East"])
        #expect(catalog.operators(in: "jp").first?.shortName == "JR")
        #expect(catalog.operators(in: "jp").first?.aliases == ["JR"])
        #expect(catalog.lines(operatorID: "jp|JR East").map(\.id) == ["line-a", "line-b"])
        #expect(catalog.lines(operatorID: "jp|JR").isEmpty)
    }

    @Test func whitespaceInTheOfficialNameIsOneOperator() {
        let catalog = EditorCatalogBuilder.build([
            sourceLine("line-a", operatorName: "JR  East"),
            sourceLine("line-b", operatorName: " JR East "),
        ])
        #expect(catalog.operators(in: "jp").map(\.id) == ["jp|JR East"])
        #expect(catalog.lines(operatorID: "jp|JR East").map(\.id) == ["line-a", "line-b"])
    }

    @Test func redirectReplacesTheSynthesizedOperatorID() {
        let catalog = EditorCatalogBuilder.build(
            [sourceLine("line-a", operatorName: "Old Co", stations: [station("S1", name: "A")])],
            operatorRedirects: [
                OperatorRedirect(regionCode: "jp", fromOfficialName: "Old Co", operatorID: "jp|New Co"),
            ]
        )
        #expect(catalog.issues.isEmpty)
        #expect(catalog.line(id: "line-a", regionCode: "jp")?.operatorIDs == ["jp|New Co"])
        #expect(catalog.lines(operatorID: "jp|New Co").map(\.id) == ["line-a"])
        #expect(catalog.lines(operatorID: "jp|Old Co").isEmpty)
        #expect(catalog.operators(in: "jp").map(\.id) == ["jp|New Co"])
    }

    @Test func redirectChainUsesTheGivenIDWhenItTerminates() {
        let catalog = EditorCatalogBuilder.build(
            [sourceLine("line-a", operatorName: "A")],
            operatorRedirects: [
                OperatorRedirect(regionCode: "jp", fromOfficialName: "A", operatorID: "jp|B"),
                OperatorRedirect(regionCode: "jp", fromOfficialName: "B", operatorID: "jp|Real Co"),
            ]
        )
        #expect(catalog.issues.isEmpty)
        #expect(catalog.line(id: "line-a", regionCode: "jp")?.operatorIDs == ["jp|B"])
    }

    @Test func cyclicRedirectFallsBackToTheSynthesizedID() {
        let catalog = EditorCatalogBuilder.build(
            [sourceLine("line-a", operatorName: "A", stations: [station("S1", name: "駅")])],
            operatorRedirects: [
                OperatorRedirect(regionCode: "jp", fromOfficialName: "A", operatorID: "jp|B"),
                OperatorRedirect(regionCode: "jp", fromOfficialName: "B", operatorID: "jp|A"),
            ]
        )
        #expect(catalog.issues.contains(.redirectCycle(regionCode: "jp", fromOfficialName: "A")))
        #expect(catalog.issues.contains(.redirectCycle(regionCode: "jp", fromOfficialName: "B")))
        #expect(catalog.line(id: "line-a", regionCode: "jp")?.operatorIDs == ["jp|A"])
        #expect(catalog.operators(in: "jp").map(\.id) == ["jp|A"])
    }

    @Test func blankOperatorsDoNotMergeAcrossLines() {
        let catalog = EditorCatalogBuilder.build([
            sourceLine("line-a", operatorName: nil, stations: [station("S1", name: "A")]),
            sourceLine("line-b", operatorName: "   ", stations: [station("S2", name: "B")]),
        ])
        #expect(Set(catalog.operators(in: "jp").map(\.id)) == [
            "jp|__line__|line-a", "jp|__line__|line-b",
        ])
        #expect(catalog.lines(operatorID: "jp|__line__|line-a").map(\.id) == ["line-a"])
        #expect(catalog.lines(operatorID: "jp|__line__|line-b").map(\.id) == ["line-b"])
    }

    @Test func duplicateLineIDKeepsTheFirstStationList() {
        let catalog = EditorCatalogBuilder.build([
            sourceLine("line-a", operatorName: "A", stations: [station("S1", name: "Kept")]),
            sourceLine("line-a", operatorName: "B", stations: [station("S2", name: "Dropped")]),
        ])
        #expect(catalog.issues.contains(.duplicateLineID(regionCode: "jp", lineID: "line-a")))
        #expect(catalog.station(StationKey(regionCode: "jp", sourceCode: "S1"))?.name == "Kept")
        #expect(catalog.station(StationKey(regionCode: "jp", sourceCode: "S2")) == nil)
        #expect(catalog.line(id: "line-a", regionCode: "jp")?.operatorIDs == ["jp|A"])
        #expect(catalog.lines(operatorID: "jp|B").isEmpty)
    }

    @Test func packageSourcesDoNotNeedSegments() throws {
        let json = Data(
            """
            {"format":"compact-v1","version":"1","country":"jp","lines":[
              {"id":"yamanote","name":"山手線","rank":1,"operator":"JR East",
               "stations":[["S1","東京",139.7,35.6,"Tokyo"]],"segments":[]}
            ]}
            """.utf8)
        let package = try JSONDecoder().decode(CompactPackage.self, from: json)
        let sources = EditorCatalogBuilder.sources(regionCode: "jp", package: package)
        #expect(sources.count == 1)
        #expect(sources[0].stations.map(\.sourceCode) == ["S1"])
        #expect(sources[0].stations.map(\.longitude) == [139.7])

        let catalog = EditorCatalogBuilder.build(sources)
        let key = StationKey(regionCode: "jp", sourceCode: "S1")
        #expect(catalog.station(key)?.name == "東京")
        #expect(catalog.memberships(lineID: "yamanote", regionCode: "jp").map(\.sequence) == [0])
    }

    @Test func stationDirectoryIndexesLinesThatOmitSegments() throws {
        let json = Data(
            """
            {"format":"compact-v1","version":"1","country":"jp","lines":[
              {"id":"yamanote","name":"山手線","nameNorm":"山手","nameRoma":"Yamanote",
               "operator":"JR East","operatorShort":"JR",
               "stations":[["S1","東京",139.7,35.6,"Tokyo"]]}
            ]}
            """.utf8)
        let directory = try JSONDecoder().decode(CompactPackage.StationDirectory.self, from: json)
        let sources = directory.lineSources()
        #expect(sources.map(\.regionCode) == ["jp"])
        #expect(sources[0].nameNorm == "山手")
        #expect(sources[0].stations.map(\.sourceCode) == ["S1"])

        let catalog = EditorCatalogBuilder.build(sources)
        let key = StationKey(regionCode: "jp", sourceCode: "S1")
        #expect(catalog.station(key)?.name == "東京")
        #expect(catalog.station(key)?.aliases == ["Tokyo"])
        #expect(catalog.station(key)?.longitude == 139.7)
        #expect(catalog.line(id: "yamanote", regionCode: "jp")?.aliases == ["Yamanote", "山手"])
        #expect(catalog.operators(in: "jp").map(\.id) == ["jp|JR East"])
        #expect(catalog.memberships(lineID: "yamanote", regionCode: "jp").map(\.membershipID) == [
            "jp|yamanote|S1|0",
        ])
    }
}

private func sourceLine(
    _ id: String,
    region: String = "jp",
    name: String = "本線",
    nameNorm: String? = nil,
    nameRoma: String? = nil,
    operatorName: String? = nil,
    operatorShort: String? = nil,
    stations: [EditorCatalogStationSource] = []
) -> EditorCatalogLineSource {
    EditorCatalogLineSource(
        regionCode: region, lineID: id, name: name, nameNorm: nameNorm, nameRoma: nameRoma,
        operatorName: operatorName, operatorShort: operatorShort, stations: stations)
}

private func station(
    _ sourceCode: String,
    name: String,
    nameRoma: String? = nil,
    longitude: Double = 0,
    latitude: Double = 0
) -> EditorCatalogStationSource {
    EditorCatalogStationSource(
        sourceCode: sourceCode, name: name, nameRoma: nameRoma, longitude: longitude, latitude: latitude)
}

private func identity(_ catalog: EditorCatalog, regions: [String]) -> [String] {
    regions.sorted().flatMap { region in
        catalog.operators(in: region).flatMap { op in
            [op.id] + catalog.lines(operatorID: op.id).filter { $0.regionCode == region }.flatMap { line in
                [region + "|" + line.id] + catalog.memberships(lineID: line.id, regionCode: region)
                    .map(\.membershipID)
            }
        }
    }
}
