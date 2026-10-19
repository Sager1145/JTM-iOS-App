import Foundation
import RailCore
import Testing
@testable import RailApplication

struct RouteRepairSessionTests {
    @Test("Missing alias evidence is a load error, not a successful empty repair")
    func aliasFailurePropagates() async throws {
        enum Failure: Error { case aliases }
        let package = try JSONDecoder().decode(CompactPackage.self, from: Data(
            #"{"format":"compact-v1","version":"test","country":"jp","lines":[]}"#.utf8))
        let train = Train(id: "repair", number: "Test", origin: "A", destination: "B",
                          stops: [Stop(name: "A", n02StationCode: "A"), Stop(name: "B", n02StationCode: "B")])
        do {
            _ = try await RouteRepairSession.search(
                train: train, baseline: train, package: package, steps: [],
                loadAliases: { _, _ in throw Failure.aliases })
            Issue.record("Failed alias loading returned a repair result")
        } catch Failure.aliases {
            // The caller can present the load failure without claiming no route exists.
        }
    }

    @Test("An ambiguous first span pauses later repair spans without losing accumulated progress")
    func firstChoicePauses() async throws {
        let lines: [[String: Any]] = ["east", "west"].map { id in
            ["id": id, "name": id, "operator": "Operator", "rank": 3, "kind": "jr_conventional",
             "stations": [["A", "A", 0.0, 0.0], ["B", "B", 1.0, 0.0], ["C", "C", 2.0, 0.0]],
             "segments": [[1, 0, [[0.0, 0.0], [1.0, 0.0]]], [1, 0, [[1.0, 0.0], [2.0, 0.0]]]]]
        }
        let package = try JSONDecoder().decode(CompactPackage.self, from: JSONSerialization.data(withJSONObject: [
            "format": "compact-v1", "version": "test", "country": "jp", "lines": lines,
        ]))
        let baseline = Train(id: "repair", number: "Test", origin: "A", destination: "D",
                             stops: ["A", "C", "D"].map { Stop(name: $0, n02StationCode: $0) })
        let stepped = RouteRepairFlow.steps([
            .init(fromVisitIndex: 0, toVisitIndex: 1, reason: .section),
            .init(fromVisitIndex: 1, toVisitIndex: 2, reason: .section),
        ], in: baseline)
        let result = try await RouteRepairSession.search(
            train: stepped.train, baseline: baseline, package: package, steps: stepped.steps,
            repaired: 1, loadAliases: { _, _ in [:] })
        let pause = try #require(result.advance.pause)
        #expect(pause.choices.count == 2)
        #expect(pause.remaining == [stepped.steps[1]])
        #expect(result.advance.repaired == 1)
        #expect(result.advance.gaps.isEmpty)
    }

    @Test("A repair outcome accepts only its starting record and retains prior progress")
    func baselineAndProgress() async throws {
        let package = try JSONDecoder().decode(CompactPackage.self, from: Data(
            #"{"format":"compact-v1","version":"test","country":"jp","lines":[]}"#.utf8))
        let baseline = Train(id: "repair", number: "Test", origin: "A", destination: "B",
                             stops: [Stop(name: "A", n02StationCode: "A"), Stop(name: "B", n02StationCode: "B")])
        let stepped = RouteRepairFlow.steps(
            [.init(fromVisitIndex: 0, toVisitIndex: 1, reason: .section)], in: baseline)
        let prior = RouteRepairFlow.GapName(from: "Earlier", to: "Gap")
        let result = try await RouteRepairSession.search(
            train: stepped.train, baseline: baseline, package: package, steps: stepped.steps,
            repaired: 2, gaps: [prior], loadAliases: { codes, _ in
                #expect(codes == ["A", "B"])
                return [:]
            })
        #expect(result.accepts(baseline))
        var edited = baseline
        edited.number = "Changed"
        #expect(!result.accepts(edited))
        #expect(!result.accepts(nil))
        #expect(result.advance.repaired == 2)
        #expect(result.advance.gaps == [prior, .init(from: "A", to: "B")])
        #expect(result.advance.pause == nil)
        let summary = result.summary { key, params in
            if key == "ios.route.repairSummary" {
                #expect(params["repaired"] == .number(2))
                #expect(params["choice"] == .number(0))
            }
            return key
        }
        #expect(summary.components(separatedBy: "\n").count == 3)
    }
}
