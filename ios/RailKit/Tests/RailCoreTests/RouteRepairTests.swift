import Foundation
import Testing
@testable import RailCore

struct RouteRepairTests {
    @Test("Adjacent section gaps merge, and a boundary covers the joining station")
    func spans() {
        let train = ride(6)
        let adjacent = RouteRepair.failingSpans(train: train, gaps: [
            .init(segmentIndex: 0, isBoundary: false),
            .init(segmentIndex: 1, isBoundary: false),
        ])
        #expect(adjacent == [RouteRepair.Span(fromVisitIndex: 0, toVisitIndex: 2, reason: .section)])

        let boundary = RouteRepair.failingSpans(train: train, gaps: [
            .init(segmentIndex: 1, isBoundary: true, station: "駅"),
        ])
        #expect(boundary == [
            RouteRepair.Span(fromVisitIndex: 0, toVisitIndex: 2, reason: .boundary(station: "駅")),
        ])

        let unsolved = RouteRepair.failingSpans(train: train, gaps: [], unsolved: [3])
        #expect(unsolved == [RouteRepair.Span(fromVisitIndex: 3, toVisitIndex: 4, reason: .unsolved)])

        let mixed = RouteRepair.failingSpans(train: train, gaps: [
            .init(segmentIndex: 1, isBoundary: true, station: "駅"),
            .init(segmentIndex: 2, isBoundary: false),
        ], unsolved: [1])
        #expect(mixed == [
            RouteRepair.Span(fromVisitIndex: 0, toVisitIndex: 3, reason: .boundary(station: "駅")),
        ])
    }

    @Test("A single surveyed path is unique, two paths are ambiguous, and a gap is none")
    func attempt() throws {
        let one = try package([line("only", ["A", "B", "C"])])
        let unique = RouteRepair.attempt(
            span: RouteRepair.Span(fromVisitIndex: 0, toVisitIndex: 1, reason: .section),
            train: ride(["A", "C"]), package: one)
        guard case .unique(let choice) = unique else {
            Issue.record("expected a unique path, got \(unique)")
            return
        }
        #expect(choice.lineIDs == ["only"])
        #expect(choice.stations.map(\.code) == ["A", "B", "C"])

        let two = try package([line("east", ["A", "B", "C"]), line("west", ["A", "B", "C"])])
        let ambiguous = RouteRepair.attempt(
            span: RouteRepair.Span(fromVisitIndex: 0, toVisitIndex: 1, reason: .section),
            train: ride(["A", "C"]), package: two)
        guard case .ambiguous(let choices) = ambiguous else {
            Issue.record("expected two paths, got \(ambiguous)")
            return
        }
        #expect(Set(choices.flatMap(\.lineIDs)) == Set(["east", "west"]))

        let none = RouteRepair.attempt(
            span: RouteRepair.Span(fromVisitIndex: 0, toVisitIndex: 1, reason: .section),
            train: ride(["A", "Z"]), package: one)
        #expect(none == .none)
    }

    @Test("A path found only without line labels stays on the guide")
    func unlabeledFallbackStaysAmbiguous() throws {
        let one = try package([line("only", ["A", "B", "C"])])
        var train = ride(["A", "C"])
        train.routeSections = [
            RouteSection(
                from: "A", to: "C", fromN02StationCode: "A", toN02StationCode: "C",
                operatorNames: ["Not A Real Operator"])
        ]
        let attempt = RouteRepair.attempt(
            span: RouteRepair.Span(fromVisitIndex: 0, toVisitIndex: 1, reason: .section),
            train: train, package: one)
        guard case .ambiguous(let choices) = attempt else {
            Issue.record("expected the guide, got \(attempt)")
            return
        }
        #expect(choices.count == 1)
        #expect(choices.first?.lineIDs == ["only"])
    }

    @Test("サンライズ出雲's 新見→米子 gap is one visit span")
    func sunriseIzumo() throws {
        let url = try PortFixtures.repositoryRoot().appending(path: "app/data/train-store.json")
        let store = try JSONDecoder().decode(TrainStore.self, from: Data(contentsOf: url))
        let train = try #require(store.trains.first { $0.id == "20260729_05_sunrise_izumo" })
        let from = try #require(train.stops.firstIndex { $0.name == "新見" })
        let to = try #require(train.stops.firstIndex { $0.name == "米子" })
        #expect(to == from + 1)
        let spans = RouteRepair.failingSpans(train: train, gaps: [
            .init(segmentIndex: from, isBoundary: false),
        ])
        #expect(spans.contains {
            $0.fromVisitIndex <= from && $0.toVisitIndex >= to && $0.reason == .section
        })
    }

    private func ride(_ count: Int) -> Train {
        ride((0..<count).map(String.init))
    }

    private func ride(_ codes: [String]) -> Train {
        Train(id: "repair", number: "Test", origin: codes.first ?? "", destination: codes.last ?? "",
              stops: codes.map { Stop(name: $0, n02StationCode: $0) })
    }

    private func line(_ id: String, _ codes: [String]) -> [String: Any] {
        [
            "id": id, "name": id, "operator": "Operator", "rank": 3, "kind": "jr_conventional",
            "stations": codes.enumerated().map { [$0.element, $0.element, Double($0.offset), 0] as [Any] },
            "segments": (0..<(codes.count - 1)).map { index in
                [1, 0, [[Double(index), 0], [Double(index + 1), 0]]] as [Any]
            },
        ]
    }

    private func package(_ lines: [[String: Any]]) throws -> CompactPackage {
        try JSONDecoder().decode(CompactPackage.self, from: JSONSerialization.data(withJSONObject: [
            "format": "compact-v1", "version": "test", "country": "jp", "lines": lines,
        ]))
    }
}
