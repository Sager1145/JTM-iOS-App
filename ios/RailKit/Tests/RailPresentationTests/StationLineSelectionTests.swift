import Foundation
import RailCore
import Testing

@testable import RailPresentation

struct StationLineSelectionTests {
    private let catalog = Fixture.catalog
    private let tyo = StationKey(regionCode: "jp", sourceCode: "TYO")
    private let kan = StationKey(regionCode: "jp", sourceCode: "KAN")
    private let nam = StationKey(regionCode: "jp", sourceCode: "NAM")
    private let umd = StationKey(regionCode: "jp", sourceCode: "UMD")
    private let usTYO = StationKey(regionCode: "us", sourceCode: "TYO")

    private let first = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
    private let second = UUID(uuidString: "00000000-0000-0000-0000-000000000002")!
    private let third = UUID(uuidString: "00000000-0000-0000-0000-000000000003")!

    @Test func selectNameOfALineIsNotAStationAndAUniqueStationFillsItsLine() {
        let blank = stop(first)
        let lineName = JourneyDraftSelection.reduce(
            stops: [blank],
            event: .selectName(occurrenceID: first, query: "本線", regionCode: nil),
            catalog: catalog
        )
        #expect(lineName.stops == [blank])
        #expect(lineName.prompt == nil)

        let named = JourneyDraftSelection.reduce(
            stops: [blank],
            event: .selectName(occurrenceID: first, query: "Kanda", regionCode: nil),
            catalog: catalog
        )
        #expect(named.prompt == nil)
        #expect(named.stops.count == 1)
        #expect(named.stops[0].stationKey == kan)
        #expect(named.stops[0].displayName == "Kanda")
        #expect(named.stops[0].lineID == "yamanote")
        #expect(named.stops[0].operatorID == "jp|JR East")
        #expect(named.stops[0].membershipID == "jp|yamanote|KAN|1")
        #expect(named.stops[0].conflict == nil)
    }

    @Test func selectNameOfADuplicatedNameAcrossRegionsStaysAmbiguous() {
        let blank = stop(first, name: "typed")
        let result = JourneyDraftSelection.reduce(
            stops: [blank],
            event: .selectName(occurrenceID: first, query: "Tokyo", regionCode: nil),
            catalog: catalog
        )
        #expect(result.stops == [blank])
        #expect(result.stops[0].stationKey == nil)
        #expect(
            result.prompt
                == .ambiguousName(occurrenceID: first, query: "Tokyo", candidates: [tyo, usTYO])
        )
    }

    @Test func selectStationWithSeveralLinesPromptsAndDoesNotPick() {
        let result = JourneyDraftSelection.reduce(
            stops: [stop(first)],
            event: .selectStation(occurrenceID: first, stationKey: tyo),
            catalog: catalog
        )
        #expect(result.stops[0].stationKey == tyo)
        #expect(result.stops[0].displayName == "Tokyo")
        #expect(result.stops[0].lineID == nil)
        #expect(result.stops[0].operatorID == nil)
        #expect(result.stops[0].membershipID == nil)
        #expect(result.stops[0].conflict == nil)
        guard case .chooseLine(let occurrenceID, let choices) = result.prompt else {
            Issue.record("expected chooseLine")
            return
        }
        #expect(occurrenceID == first)
        #expect(choices.map(\.lineID) == ["chuo", "yamanote"])
        #expect(choices.map(\.operatorName) == ["JR East", "JR East"])
    }

    @Test func selectStationOnASingleLineFillsThatMembership() {
        let result = JourneyDraftSelection.reduce(
            stops: [stop(first)],
            event: .selectStation(occurrenceID: first, stationKey: kan),
            catalog: catalog
        )
        #expect(result.prompt == nil)
        #expect(result.stops[0].stationKey == kan)
        #expect(result.stops[0].lineID == "yamanote")
        #expect(result.stops[0].membershipID == "jp|yamanote|KAN|1")
        #expect(result.stops[0].operatorID == "jp|JR East")
        #expect(result.stops[0].conflict == nil)
    }

    @Test func selectStationKeepsALineTheStationBelongsTo() {
        let result = JourneyDraftSelection.reduce(
            stops: [stop(first, line: "yamanote", operatorID: "jp|JR East")],
            event: .selectStation(occurrenceID: first, stationKey: tyo),
            catalog: catalog
        )
        #expect(result.prompt == nil)
        #expect(result.stops[0].stationKey == tyo)
        #expect(result.stops[0].lineID == "yamanote")
        #expect(result.stops[0].membershipID == "jp|yamanote|TYO|0")
        #expect(result.stops[0].operatorID == "jp|JR East")
        #expect(result.stops[0].conflict == nil)
    }

    @Test func selectStationKeepsALineTheStationIsNotOn() {
        let original = stop(first, line: "midosuji", operatorID: "jp|Osaka Metro")
        let result = JourneyDraftSelection.reduce(
            stops: [original],
            event: .selectStation(occurrenceID: first, stationKey: kan),
            catalog: catalog
        )
        #expect(result.prompt == nil)
        #expect(result.stops.count == 1)
        #expect(result.stops[0].stationKey == kan)
        #expect(result.stops[0].displayName == "Kanda")
        #expect(result.stops[0].lineID == "midosuji")
        #expect(result.stops[0].operatorID == "jp|Osaka Metro")
        #expect(result.stops[0].membershipID == nil)
        #expect(result.stops[0].conflict == .stationNotOnLine(stationKey: kan, lineID: "midosuji"))
    }

    @Test func selectLineClearsConflictWhenTheStationIsAMember() {
        let result = JourneyDraftSelection.reduce(
            stops: [
                stop(
                    first, station: kan, name: "Kanda", line: "midosuji",
                    conflict: .stationNotOnLine(stationKey: kan, lineID: "midosuji"))
            ],
            event: .selectLine(occurrenceID: first, regionCode: "jp", lineID: "yamanote"),
            catalog: catalog
        )
        #expect(result.prompt == nil)
        #expect(result.stops[0].stationKey == kan)
        #expect(result.stops[0].lineID == "yamanote")
        #expect(result.stops[0].membershipID == "jp|yamanote|KAN|1")
        #expect(result.stops[0].operatorID == "jp|JR East")
        #expect(result.stops[0].conflict == nil)
    }

    @Test func selectLineKeepsTheStationWhenItIsNotAMember() {
        let result = JourneyDraftSelection.reduce(
            stops: [stop(first, station: kan, name: "Kanda", line: "yamanote")],
            event: .selectLine(occurrenceID: first, regionCode: "jp", lineID: "chuo"),
            catalog: catalog
        )
        #expect(result.prompt == nil)
        #expect(result.stops.count == 1)
        #expect(result.stops[0].stationKey == kan)
        #expect(result.stops[0].displayName == "Kanda")
        #expect(result.stops[0].lineID == "chuo")
        #expect(result.stops[0].operatorID == "jp|JR East")
        #expect(result.stops[0].membershipID == nil)
        #expect(result.stops[0].conflict == .stationNotOnLine(stationKey: kan, lineID: "chuo"))
    }

    @Test func sharedLineIDsAreTheSortedIntersection() {
        #expect(JourneyDraftSelection.sharedLineIDs(tyo, kan, catalog: catalog) == ["yamanote"])
        #expect(JourneyDraftSelection.sharedLineIDs(tyo, nam, catalog: catalog).isEmpty)
    }

    @Test func reconcileFillsTheOnlySharedLine() {
        let result = JourneyDraftSelection.reconcileNeighbors(
            earlierOccurrenceID: first,
            laterOccurrenceID: second,
            stops: [
                stop(first, station: tyo, name: "Tokyo"),
                stop(second, station: kan, name: "Kanda"),
            ],
            catalog: catalog
        )
        #expect(result.prompt == nil)
        #expect(result.stops.map(\.lineID) == ["yamanote", "yamanote"])
        #expect(result.stops.map(\.membershipID) == ["jp|yamanote|TYO|0", "jp|yamanote|KAN|1"])
        #expect(result.stops.map(\.stationKey) == [tyo, kan])
    }

    @Test func reconcileWithNoSharedLineIsAPossibleTransfer() {
        let result = JourneyDraftSelection.reconcileNeighbors(
            earlierOccurrenceID: first,
            laterOccurrenceID: second,
            stops: [
                stop(first, station: tyo, name: "Tokyo"),
                stop(second, station: nam, name: "Namba"),
            ],
            catalog: catalog
        )
        #expect(
            result.prompt
                == .possibleTransfer(earlierOccurrenceID: first, laterOccurrenceID: second)
        )
        #expect(result.stops.map(\.stationKey) == [tyo, nam])
        #expect(result.stops.map(\.lineID) == [nil, nil])
    }

    @Test func nambaPromptsForBothLinesAndSharedLinesDoNotAutoPick() {
        let selected = JourneyDraftSelection.reduce(
            stops: [stop(first)],
            event: .selectStation(occurrenceID: first, stationKey: nam),
            catalog: catalog
        )
        guard case .chooseLine(_, let choices) = selected.prompt else {
            Issue.record("expected chooseLine")
            return
        }
        #expect(Set(choices.map(\.lineID)) == ["kintetsu", "midosuji"])
        #expect(selected.stops[0].lineID == nil)

        let result = JourneyDraftSelection.reconcileNeighbors(
            earlierOccurrenceID: first,
            laterOccurrenceID: second,
            stops: [
                stop(first, station: umd, name: "Umeda"),
                stop(second, station: nam, name: "Namba"),
            ],
            catalog: catalog
        )
        guard case .chooseLine(let occurrenceID, let shared) = result.prompt else {
            Issue.record("expected chooseLine for the later stop")
            return
        }
        #expect(occurrenceID == second)
        #expect(Set(shared.map(\.lineID)) == ["kintetsu", "midosuji"])
        #expect(shared.count == 2)
        #expect(result.stops.map(\.lineID) == [nil, nil])
        #expect(result.stops.map(\.stationKey) == [umd, nam])
    }

    @Test func listEditsKeepDistinctOccurrencesOfTheSameStation() {
        let alpha = stop(first, station: tyo, name: "Tokyo")
        let beta = stop(second, station: tyo, name: "Tokyo")
        let inserted = JourneyDraftEdits.insert(stop(third, name: "extra"), at: 99, in: [alpha, beta])
        #expect(inserted.map(\.occurrenceID) == [first, second, third])
        let clamped = JourneyDraftEdits.insert(stop(third, name: "extra"), at: -1, in: [alpha])
        #expect(clamped.map(\.occurrenceID) == [third, first])

        let deleted = JourneyDraftEdits.delete(at: IndexSet(integer: 0), in: [alpha, beta])
        #expect(deleted.stops.map(\.occurrenceID) == [second])
        #expect(deleted.deleted.map(\.offset) == [0])
        let restored = JourneyDraftEdits.undo(deleted.deleted, in: deleted.stops)
        #expect(restored.map(\.occurrenceID) == [first, second])
        #expect(restored.map(\.stationKey) == [tyo, tyo])

        let moved = JourneyDraftEdits.move(from: IndexSet(integer: 0), to: 2, in: [alpha, beta])
        #expect(moved.map(\.occurrenceID) == [second, first])
        #expect(moved.map(\.stationKey) == [tyo, tyo])
    }

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

    private func stop(
        _ occurrenceID: UUID,
        station: StationKey? = nil,
        name: String = "",
        line: String? = nil,
        operatorID: String? = nil,
        membership: String? = nil,
        conflict: JourneyDraftConflict? = nil
    ) -> JourneyDraftStop {
        JourneyDraftStop(
            occurrenceID: occurrenceID,
            stationKey: station,
            displayName: name,
            lineID: line,
            operatorID: operatorID,
            membershipID: membership,
            conflict: conflict
        )
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
        line("L", region: "us", name: "L", operatorName: "CTA", stations: [
            station("TYO", name: "Toyko CTA", nameRoma: "Tokyo"),
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
