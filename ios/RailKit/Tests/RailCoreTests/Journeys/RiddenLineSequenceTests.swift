import Foundation
import Testing
@testable import RailCore

/// Line ids, station codes and service codes below are the bundled
/// `japan-through-services.json` ones, so the default through-service lookup
/// really matches. Taiwan ids follow the package `tw-<operator>-<line>` form
/// with 彰化 = TRA-3360 from `app/data/stations-tw.json`.
struct RiddenLineSequenceTests {
    typealias Selection = RideRouteResolution.PhysicalRouteSelection

    // MARK: - Fixtures

    struct Hop {
        let lineID: String
        let from: String
        let to: String
        var occurrence: Int? = nil
        var code: String {
            lineID + "@" + [from, to].sorted().joined(separator: ":") + (occurrence.map { "~\($0)" } ?? "")
        }
    }

    static let east = "東日本旅客鉄道"
    static let central = "東海旅客鉄道"
    static let west = "西日本旅客鉄道"

    /// Names and operators by line id, as `RouteNetwork.resolvedLines` gives them.
    static let catalog: [String: (name: String, operatorName: String)] = [
        "jp-東日本旅客鉄道-東北線": ("東北線", east),
        "jp-東日本旅客鉄道-東北線-2": ("東北線", east),
        "jp-東日本旅客鉄道-赤羽線": ("赤羽線", east),
        "jp-東日本旅客鉄道-山手線": ("山手線", east),
        "jp-東日本旅客鉄道-大崎支線": ("大崎支線", east),
        "jp-東日本旅客鉄道-総武線-3": ("総武線", east),
        "jp-東日本旅客鉄道-東海道線": ("東海道線", east),
        "jp-東海旅客鉄道-東海道線": ("東海道線", central),
        "jp-東急電鉄-東横線": ("東横線", "東急電鉄"),
        "jp-横浜高速鉄道-みなとみらい21線": ("みなとみらい線", "横浜高速鉄道"),
        "jp-東京地下鉄-11号線半蔵門線": ("半蔵門線", "東京地下鉄"),
        "jp-東急電鉄-田園都市線": ("田園都市線", "東急電鉄"),
        "jp-東日本旅客鉄道-東北新幹線": ("東北新幹線", east),
        "jp-北海道旅客鉄道-北海道新幹線": ("北海道新幹線", "北海道旅客鉄道"),
        "jp-東日本旅客鉄道-上越新幹線": ("上越新幹線", east),
        "jp-東日本旅客鉄道-北陸新幹線": ("北陸新幹線", east),
        "jp-西日本旅客鉄道-北陸新幹線": ("北陸新幹線", west),
        "tw-國營臺灣鐵路股份有限公司-臺中線": ("臺中線", "國營臺灣鐵路股份有限公司"),
        "tw-國營臺灣鐵路股份有限公司-縱貫線南段": ("縱貫線南段", "國營臺灣鐵路股份有限公司"),
    ]

    static func selection(_ hops: [Hop], lines: [String]? = nil) -> Selection {
        let ids = lines ?? hops.reduce(into: [String]()) { if !$0.contains($1.lineID) { $0.append($1.lineID) } }
        return Selection(
            fromStationCode: hops.first?.from ?? "", toStationCode: hops.last?.to ?? "",
            intervals: hops.map { .init(lineID: $0.lineID, code: $0.code, direction: 1) },
            lines: ids.map { id in
                ResolvedRailLine(lineID: id, name: catalog[id]?.name ?? id,
                                 operatorName: catalog[id]?.operatorName, km: 1)
            },
            provenance: .explicit)
    }

    /// One recorded section per hop list, chained through recorded stops.
    static func train(
        number: String = "テスト1号", type: String? = "快速", date: String? = "2024-05-01",
        codes: [String], recordedLines: [[String]]? = nil, region: String = "jp"
    ) -> Train {
        let sections = zip(codes, codes.dropFirst()).enumerated().map { index, pair in
            RouteSection(from: "S\(pair.0)", to: "S\(pair.1)",
                         fromN02StationCode: pair.0, toN02StationCode: pair.1,
                         lineNames: recordedLines?[index])
        }
        return Train(id: "t", date: date, number: number, trainType: type,
                     origin: "S\(codes.first ?? "")", destination: "S\(codes.last ?? "")",
                     routeSections: sections,
                     stops: codes.map { Stop(name: "S\($0)", n02StationCode: $0) }, region: region)
    }

    static func names(_ runs: [RiddenLineSequence.Line]) -> [String] { runs.map(\.name) }

    static func codes(_ kind: RiddenLineSequence.BoundaryKind) -> [String] {
        if case .throughService(let codes) = kind { return codes }
        return []
    }

    // MARK: - Through services

    @Test func shonanShinjukuJoinsAreThroughServicesAndCaptionStaysOut() throws {
        let ride = Self.train(number: "湘南新宿ライン 快速 3521Y",
                              codes: ["002200", "003155", "003390", "004135", "004300"])
        let selections: [Int: Selection] = [
            0: Self.selection([Hop(lineID: "jp-東日本旅客鉄道-東北線", from: "002200", to: "003155")]),
            1: Self.selection([Hop(lineID: "jp-東日本旅客鉄道-赤羽線", from: "003155", to: "003390")]),
            2: Self.selection([Hop(lineID: "jp-東日本旅客鉄道-山手線", from: "003390", to: "004135")]),
            3: Self.selection([
                Hop(lineID: "jp-東日本旅客鉄道-大崎支線", from: "004135", to: "004235"),
                Hop(lineID: "jp-東日本旅客鉄道-総武線-3", from: "004235", to: "004300"),
            ]),
        ]
        let sequence = RiddenLineSequence(train: ride, selections: selections, drawnSections: [0, 1, 2, 3],
                                          solveSettled: true)
        #expect(Self.names(sequence.summary.runs) == ["東北線", "赤羽線", "山手線", "大崎支線", "総武線"])
        #expect(sequence.summary.boundaries.count == 4)
        for (index, station) in [(1, "003155"), (2, "003390"), (3, "004135")] {
            let join = try #require(sequence.joins[index])
            #expect(join.stationCode == station)
            #expect(join.stopIndex == index)
            #expect(Self.codes(join.kind).contains("JS-utsunomiya-zushi"), "join at \(station)")
        }
        let inner = sequence.sections[3].boundaries
        #expect(inner.map(\.stationCode) == ["004235"])
        #expect(Self.codes(inner[0].kind).contains("JS-utsunomiya-zushi"))
        #expect(sequence.serviceCaption == "湘南新宿ライン 快速 3521Y")
        #expect(!Self.names(sequence.summary.runs).contains(sequence.serviceCaption))
        #expect(sequence.sections.allSatisfy { $0.status == .resolved(certified: true) && $0.source == .solved })
    }

    @Test func shinagawaTsurumiCorridorShowsAsYokosukaLine() throws {
        let ride = Self.train(number: "湘南新宿ライン", codes: ["004135", "004496"])
        let sequence = RiddenLineSequence(train: ride, selections: [0: Self.selection([
            Hop(lineID: "jp-東日本旅客鉄道-大崎支線", from: "004135", to: "004235"),
            Hop(lineID: "jp-東日本旅客鉄道-総武線-3", from: "004235", to: "004496"),
        ])], drawnSections: [0], solveSettled: true)
        let corridor = try #require(sequence.sections[0].runs.last)
        #expect(corridor.lineID == "jp-東日本旅客鉄道-総武線-3")
        #expect(corridor.displayName(language: "ja") == "横須賀線")
        #expect(corridor.displayName(language: "zh-Hant") == "橫須賀線")
        #expect(corridor.displayName(language: "zh-Hans") == "横须贺线")
        #expect(corridor.displayName(language: "en") == "Yokosuka Line")
        #expect(sequence.sections[0].runs.first?.displayName(language: "ja") == "大崎支線")
    }

    @Test func uenoTokyoLineThroughAtTokyoThenOperatorChangeAtAtami() throws {
        let ride = Self.train(number: "上野東京ライン", codes: ["003100", "003766", "005685", "005689"])
        let selections: [Int: Selection] = [
            0: Self.selection([
                Hop(lineID: "jp-東日本旅客鉄道-東北線", from: "003100", to: "003155"),
                Hop(lineID: "jp-東日本旅客鉄道-東北線-2", from: "003155", to: "003766"),
            ]),
            1: Self.selection([Hop(lineID: "jp-東日本旅客鉄道-東海道線", from: "003766", to: "005685")]),
            2: Self.selection([Hop(lineID: "jp-東海旅客鉄道-東海道線", from: "005685", to: "005689")]),
        ]
        let sequence = RiddenLineSequence(train: ride, selections: selections, drawnSections: [0, 1, 2],
                                          solveSettled: true)
        // 東北線 and 東北線-2 share a name and an operator: one run.
        #expect(sequence.sections[0].runs.count == 1)
        #expect(sequence.sections[0].boundaries.isEmpty)
        let tokyo = try #require(sequence.joins[1])
        #expect(tokyo.stationCode == "003766")
        #expect(Self.codes(tokyo.kind).contains("utl-utsunomiya-numazu"))
        let atami = try #require(sequence.joins[2])
        #expect(atami.stationCode == "005685")
        // Same canonical name, different operator: an operator change, even
        // though the catalog also lists the pair as a through service.
        #expect(atami.kind == .operatorChange)
        #expect(Self.names(sequence.summary.runs) == ["東北線", "東海道線", "東海道線"])
        #expect(sequence.summary.runs.map(\.operatorName) == [Self.east, Self.east, Self.central])
    }

    @Test func toyokoMinatomiraiInnerBoundaryAtYokohamaBothDirections() throws {
        let names = ["004633": "横浜"]
        let forward = Self.train(codes: ["003922", "004704"])
        let down = RiddenLineSequence(train: forward, selections: [0: Self.selection([
            Hop(lineID: "jp-東急電鉄-東横線", from: "003922", to: "004500"),
            Hop(lineID: "jp-東急電鉄-東横線", from: "004500", to: "004633"),
            Hop(lineID: "jp-横浜高速鉄道-みなとみらい21線", from: "004633", to: "004704"),
        ])], drawnSections: [0], solveSettled: true, stationName: { names[$0] })
        #expect(Self.names(down.sections[0].runs) == ["東横線", "みなとみらい線"])
        let boundary = try #require(down.sections[0].boundaries.first)
        #expect(boundary.stationCode == "004633")
        #expect(boundary.stationName == "横浜")
        #expect(Self.codes(boundary.kind).contains("toyoko-minatomirai"))

        // Reversed travel: the interval codes are the same symmetric codes.
        let backward = Self.train(codes: ["004704", "003922"])
        let up = RiddenLineSequence(train: backward, selections: [0: Self.selection([
            Hop(lineID: "jp-横浜高速鉄道-みなとみらい21線", from: "004704", to: "004633"),
            Hop(lineID: "jp-東急電鉄-東横線", from: "004633", to: "004500"),
            Hop(lineID: "jp-東急電鉄-東横線", from: "004500", to: "003922"),
        ])], drawnSections: [0], solveSettled: true, stationName: { names[$0] })
        #expect(Self.names(up.sections[0].runs) == ["みなとみらい線", "東横線"])
        #expect(up.sections[0].boundaries.first?.stationCode == "004633")
        #expect(Self.codes(up.sections[0].boundaries[0].kind).contains("toyoko-minatomirai"))
    }

    @Test func hanzomonDenentoshiAtShibuyaBothDirections() {
        let north = Self.train(codes: ["003812", "003922", "004430"])
        let a = RiddenLineSequence(train: north, selections: [
            0: Self.selection([Hop(lineID: "jp-東京地下鉄-11号線半蔵門線", from: "003812", to: "003922")]),
            1: Self.selection([Hop(lineID: "jp-東急電鉄-田園都市線", from: "003922", to: "004430")]),
        ], drawnSections: [0, 1], solveSettled: true)
        #expect(Self.names(a.summary.runs) == ["半蔵門線", "田園都市線"])
        #expect(a.joins[1]?.stationCode == "003922")
        #expect(Self.codes(a.joins[1]!.kind).contains("denentoshi-hanzomon"))

        let south = Self.train(codes: ["004430", "003922", "003812"])
        let b = RiddenLineSequence(train: south, selections: [
            0: Self.selection([Hop(lineID: "jp-東急電鉄-田園都市線", from: "004430", to: "003922")]),
            1: Self.selection([Hop(lineID: "jp-東京地下鉄-11号線半蔵門線", from: "003922", to: "003812")]),
        ], drawnSections: [0, 1], solveSettled: true)
        #expect(Self.names(b.summary.runs) == ["田園都市線", "半蔵門線"])
        #expect(Self.codes(b.joins[1]!.kind).contains("denentoshi-hanzomon"))
    }

    @Test func kagayakiJoetsuToHokurikuAtTakasakiThenOperatorChangeAtJoetsuMyoko() {
        let ride = Self.train(number: "かがやき505号", type: "新幹線", codes: ["002914", "001700"])
        let sequence = RiddenLineSequence(train: ride, selections: [0: Self.selection([
            Hop(lineID: "jp-東日本旅客鉄道-上越新幹線", from: "002914", to: "002389"),
            Hop(lineID: "jp-東日本旅客鉄道-北陸新幹線", from: "002389", to: "001643"),
            Hop(lineID: "jp-西日本旅客鉄道-北陸新幹線", from: "001643", to: "001700"),
        ])], drawnSections: [0], solveSettled: true)
        let section = sequence.sections[0]
        #expect(Self.names(section.runs) == ["上越新幹線", "北陸新幹線", "北陸新幹線"])
        #expect(section.boundaries.map(\.stationCode) == ["002389", "001643"])
        #expect(Self.codes(section.boundaries[0].kind).contains("hokuriku-shinkansen-tsuruga"))
        #expect(section.boundaries[1].kind == .operatorChange)
    }

    @Test func tohokuToHokkaidoShinkansenAtShinAomori() {
        let ride = Self.train(number: "はやぶさ1号", type: "新幹線", codes: ["000700", "000531", "000429"])
        let sequence = RiddenLineSequence(train: ride, selections: [
            0: Self.selection([Hop(lineID: "jp-東日本旅客鉄道-東北新幹線", from: "000700", to: "000531")]),
            1: Self.selection([Hop(lineID: "jp-北海道旅客鉄道-北海道新幹線", from: "000531", to: "000429")]),
        ], drawnSections: [0, 1], solveSettled: true)
        #expect(Self.names(sequence.summary.runs) == ["東北新幹線", "北海道新幹線"])
        #expect(sequence.joins[1]?.stationCode == "000531")
        #expect(Self.codes(sequence.joins[1]!.kind).contains("hokkaido-shinkansen-hayabusa"))
    }

    // MARK: - Outside Japan

    @Test func taiwanLineChangeAtChanghuaAndLoopKeepsBothRuns() {
        let taichung = "tw-國營臺灣鐵路股份有限公司-臺中線"
        let trunk = "tw-國營臺灣鐵路股份有限公司-縱貫線南段"
        let ride = Self.train(number: "自強 101", type: "自強", codes: ["TRA-3230", "TRA-3360", "TRA-3420"],
                              region: "tw")
        let sequence = RiddenLineSequence(train: ride, selections: [
            0: Self.selection([Hop(lineID: taichung, from: "TRA-3230", to: "TRA-3360")]),
            1: Self.selection([Hop(lineID: trunk, from: "TRA-3360", to: "TRA-3420")]),
        ], drawnSections: [0, 1], solveSettled: true)
        #expect(Self.names(sequence.summary.runs) == ["臺中線", "縱貫線南段"])
        #expect(sequence.joins[1]?.stationCode == "TRA-3360")
        #expect(sequence.joins[1]?.kind == .lineChange)

        let loop = Self.train(number: "環島", type: "自強", codes: ["TRA-1", "TRA-2", "TRA-3", "TRA-4"],
                              region: "tw")
        let around = RiddenLineSequence(train: loop, selections: [
            0: Self.selection([Hop(lineID: taichung, from: "TRA-1", to: "TRA-2")]),
            1: Self.selection([Hop(lineID: trunk, from: "TRA-2", to: "TRA-3")]),
            2: Self.selection([Hop(lineID: taichung, from: "TRA-3", to: "TRA-4")]),
        ], drawnSections: [0, 1, 2], solveSettled: true)
        #expect(Self.names(around.summary.runs) == ["臺中線", "縱貫線南段", "臺中線"])
        #expect(around.summary.boundaries.count == 2)
        #expect(around.resolvedLineIDs == [taichung, trunk])
    }

    // MARK: - Evidence precedence

    @Test func unprovenSectionUsesRecordedNamesAndIsNotResolved() {
        let ride = Self.train(codes: ["A", "B", "C"], recordedLines: [["一線"], ["二線"]])
        let sequence = RiddenLineSequence(
            train: ride,
            selections: [0: Self.selection([Hop(lineID: "x-一", from: "A", to: "B")]),
                         1: Self.selection([Hop(lineID: "x-二", from: "B", to: "C")])],
            drawnSections: [0, 1],
            gaps: [.init(segmentIndex: 1, isBoundary: false, isUnproven: true)],
            geometryLines: [1: [.init(name: "幾何線", operatorName: nil, km: 3)]],
            solveSettled: true, continuations: nil)
        #expect(sequence.sections[1].status == .unproven)
        #expect(sequence.sections[1].source == .recorded)
        #expect(Self.names(sequence.sections[1].runs) == ["二線"])
        #expect(sequence.resolvedLineIDs == ["x-一"])
    }

    @Test func geometryForMiddleSectionStaysInOrder() {
        let ride = Self.train(type: "特急", codes: ["A", "B", "C", "D"])
        let sequence = RiddenLineSequence(
            train: ride,
            selections: [0: Self.selection([Hop(lineID: "x-一", from: "A", to: "B")]),
                         2: Self.selection([Hop(lineID: "x-三", from: "C", to: "D")])],
            drawnSections: [0, 1, 2],
            geometryLines: [1: [.init(name: "中線", operatorName: "会社", km: 3)]],
            solveSettled: true, continuations: nil)
        #expect(Self.names(sequence.summary.runs) == ["x-一", "中線", "x-三"])
        #expect(sequence.sections.map(\.source) == [.solved, .geometry, .solved])
        #expect(sequence.sections[1].status == .resolved(certified: false))
    }

    @Test func ordinaryServiceKeepsRecordedNameOverGeometry() {
        let ride = Self.train(number: "1234M", type: "普通", codes: ["A", "B"], recordedLines: [["山手線"]])
        let sequence = RiddenLineSequence(
            train: ride, drawnSections: [0],
            geometryLines: [0: [.init(name: "東北線", operatorName: "会社", km: 5)]],
            solveSettled: true, continuations: nil)
        #expect(Self.names(sequence.sections[0].runs) == ["山手線"])
        #expect(sequence.sections[0].source == .recorded)
        #expect(sequence.resolvedLineIDs.isEmpty)
    }

    @Test func pendingConfirmationClaimsNoRuns() {
        var ride = Self.train(codes: ["A", "B"], recordedLines: [["山手線"]])
        ride.routeConfirmation = .pending
        ride.routePolicy = RoutePolicy(preferredLineNames: ["東海道線"])
        let sequence = RiddenLineSequence(
            train: ride, selections: [0: Self.selection([Hop(lineID: "x-一", from: "A", to: "B")])],
            drawnSections: [0], solveSettled: true, continuations: nil)
        #expect(sequence.sections.allSatisfy { $0.status == .pending && $0.runs.isEmpty && $0.source == .none })
        #expect(sequence.summary.runs.isEmpty)
    }

    @Test func policyNamesOnlyWhenNoSectionHasAny() {
        var ride = Self.train(codes: ["A", "B"])
        ride.routePolicy = RoutePolicy(preferredLineNames: ["日豊線", "日南線"])
        let unsolved = RiddenLineSequence(train: ride, continuations: nil)
        #expect(unsolved.sections.map(\.source) == [.policy])
        #expect(unsolved.sections[0].status == .pending)
        #expect(unsolved.sections[0].stopInterval == nil)
        #expect(Self.names(unsolved.summary.runs) == ["日豊線", "日南線"])

        let settled = RiddenLineSequence(train: ride, solveSettled: true, continuations: nil)
        #expect(settled.sections[0].status == .unresolved)

        ride.routeSections?[0].lineNames = ["日豊線"]
        let recorded = RiddenLineSequence(train: ride, continuations: nil)
        #expect(recorded.sections.map(\.source) == [.recorded])
        #expect(Self.names(recorded.summary.runs) == ["日豊線"])
    }

    @Test func emptyIntervalsFallBackToSelectionLines() {
        let ride = Self.train(codes: ["A", "B"])
        let selection = Selection(
            fromStationCode: "A", toStationCode: "B", intervals: [],
            lines: [ResolvedRailLine(lineID: "x-一", name: "一線", operatorName: "甲", km: 1),
                    ResolvedRailLine(lineID: "x-二", name: "二線", operatorName: "甲", km: 1)],
            provenance: .matchedGeometry)
        let sequence = RiddenLineSequence(train: ride, selections: [0: selection], drawnSections: [0],
                                          continuations: nil)
        #expect(Self.names(sequence.sections[0].runs) == ["一線", "二線"])
        #expect(sequence.sections[0].boundaries.map(\.stationCode) == [nil])
        #expect(sequence.sections[0].boundaries[0].kind == .lineChange)
    }

    @Test func repeatedIntervalCodeStillLocatesTheBoundary() {
        let repeated = RailIntervalCodes.stationCodes(ofIntervalCode: "x-一@A:B~2")
        #expect(repeated?.0 == "A" && repeated?.1 == "B")
        let nested = RailIntervalCodes.stationCodes(ofIntervalCode: "jp-a@b@004633:004704")
        #expect(nested?.0 == "004633" && nested?.1 == "004704")
        #expect(RailIntervalCodes.stationCodes(ofIntervalCode: "broken") == nil)
        let ride = Self.train(codes: ["A", "C"])
        let sequence = RiddenLineSequence(train: ride, selections: [0: Self.selection([
            Hop(lineID: "x-一", from: "A", to: "B", occurrence: 2),
            Hop(lineID: "x-二", from: "B", to: "C"),
        ])], drawnSections: [0], continuations: nil)
        #expect(sequence.sections[0].boundaries.map(\.stationCode) == ["B"])
    }

    @Test func partsOfOneSectionMergeIntoOneSelection() {
        let first = Self.selection([Hop(lineID: "x-一", from: "A", to: "B")])
        let second = Self.selection([Hop(lineID: "x-二", from: "B", to: "C")])
        let merged = RiddenLineSequence.selections([(0, first), (0, first), (0, second), (1, nil)])
        #expect(merged.keys.sorted() == [0])
        #expect(merged[0]?.fromStationCode == "A")
        #expect(merged[0]?.toStationCode == "C")
        #expect(merged[0]?.intervals.map(\.lineID) == ["x-一", "x-二"])
    }
}
