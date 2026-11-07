import Foundation
import Testing
@testable import AreaKit
import RailInspection
import RailCore

/// Loads the REAL repository data. Skipped (with a message) when the data
/// files are absent, e.g. in a checkout without app/data.
@Suite(.serialized)
struct RealDataTests {
    static let repo: URL? = {
        guard let repo = try? DataRoot.discoverRepo(from: URL(fileURLWithPath: #filePath)) else { return nil }
        let root = DataRoot(repo: repo)
        return DataFile.allCases.allSatisfy { FileManager.default.fileExists(atPath: root.url($0).path) } ? repo : nil
    }()

    @Test(.enabled(if: RealDataTests.repo != nil, "Repository data files (app/data, app/public/rail/jp-2025.json) are absent; skipping the real-data area test."))
    func tateishiNishiyashikiStationPair() throws {
        let clock = ContinuousClock()
        var data: AreaData!
        let loadTime = try clock.measure { data = try AreaData.load(DataRoot(repo: RealDataTests.repo!)) }
        let main = "jp-九州旅客鉄道-日豊線", paired = "jp-九州旅客鉄道-日豊線-p1"
        var scope: AreaScope!
        let scopeTime = try clock.measure {
            scope = try AreaScope.resolve(.init(mode: .stationPair(lineID: main, fromStationID: "009241", toStationID: "009262")), data: data)
        }
        #expect(scope.line(main) != nil && scope.line(paired) != nil)
        #expect(scope.line(main)?.alignmentPairs.contains { $0.with == paired } == true)
        #expect(scope.line(paired)?.alignmentOf == main)
        #expect(scope.line(main)?.intervalIndices.contains(26) == true)
        var problems: [Problem] = []
        let detectTime = clock.measure { problems = AreaProblems.detect(scope: scope, data: data) }
        var trains: [Train] = []
        let rideTime = try clock.measure {
            trains = RideSelection.ridesCrossing(scope, trains: try RideSelection.loadTrains(RideSource.defaults(data.root)), data: data)
        }
        print("REAL-AREA lines: \(scope.lines.map(\.lineID))")
        print("REAL-AREA bbox: \(scope.bbox) junctions: \(scope.junctionIDs.count) history: \(scope.historyIDs)")
        for problem in problems { print("REAL-AREA problem: [\(problem.severity.rawValue)] \(problem.id) — \(problem.message)") }
        print("REAL-AREA crossing rides: \(trains.map(\.id))")
        // The sonic 44 sample (id regenerated with the samples) rides 杵築→宇佐 through the area.
        let outcomes = RideOutcome.resolve(trains, data: data, scope: scope)
        let kitsukiUsa = outcomes.flatMap(\.sections).filter { $0.inArea && $0.from == "杵築" && $0.to == "宇佐" }
        #expect(!kitsukiUsa.isEmpty, "no crossing ride rides 杵築→宇佐: \(trains.map(\.id))")
        for outcome in outcomes {
            for section in outcome.sections where section.inArea {
                print("REAL-AREA ride \(outcome.trainID) [\(outcome.disposition)] #\(section.index) \(section.from ?? "?")(\(section.fromCode ?? "?"))→\(section.to ?? "?")(\(section.toCode ?? "?")): "
                      + "\(section.certified ? "certified" : "UNCERTIFIED \(section.gaps)") provenance \(section.provenance ?? "none") lines \(section.lineIDs)")
            }
        }
        // Every bundled registry row passes the static rules AreaKit enforces on patches.
        let junctionFile = try Data(contentsOf: data.root.url(.junctions))
        let rows = try JunctionFileEditor.rows(in: junctionFile)
        let rowOps = rows.map { PatchOp(op: .junctionAdd, key: $0["id"]?.stringValue ?? "", before: nil, after: $0) }
        var broken: [String] = []
        for op in rowOps {
            do { try JunctionRowRules.validate(op.after!, op: op) } catch { broken.append(error.localizedDescription) }
        }
        #expect(broken.isEmpty, "\(broken.prefix(5))")
        try JunctionRowRules.validateLineIDs(rowOps.filter { op in
            (op.after?["lineIDs"]?.arrayValue ?? []).allSatisfy { data.linesByID[$0.stringValue ?? ""] != nil }
        }, packageURL: data.root.url(.package))
        print("REAL-AREA junction rows checked: \(rows.count), rule failures: \(broken.count), jp rows naming lines absent from the package: \(rowOps.filter { op in op.after?["region"] == .string("jp") && !(op.after?["lineIDs"]?.arrayValue ?? []).allSatisfy { data.linesByID[$0.stringValue ?? ""] != nil } }.count)")
        for line in ["jp-東日本旅客鉄道-奥羽線-p1", "jp-九州旅客鉄道-鹿児島線-p1", "jp-九州旅客鉄道-鹿児島線-2-p1", paired] {
            let m = PairedDirectionSideDetector.measure(data, lineID: line)
            print("REAL-AREA side \(line): declared \(data.linesByID[line]?.alignmentDirection ?? "?") measured \(String(describing: m))")
        }
        print("REAL-AREA timing load \(loadTime) scope \(scopeTime) detect \(detectTime) rides \(rideTime)")
    }
}
