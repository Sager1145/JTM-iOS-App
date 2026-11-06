import Foundation
import Testing
@testable import AreaKit
import RailCore
import RailInspection

@Suite(.serialized)
struct AreaScopeTests {
    let repo: URL
    let data: AreaData
    init() throws {
        repo = try Fixture.repo()
        data = try Fixture.load(DataRoot(repo: repo))
    }

    private func close(_ a: Double, _ b: Double) -> Bool { abs(a - b) < 1e-9 }

    @Test func stationPairResolvesIntervalBoxLinesAndPairing() throws {
        let scope = try AreaScope.resolve(.init(mode: .stationPair(lineID: Fixture.main, fromStationID: "100001", toStationID: "100002")), data: data)
        let expected = AreaBBox(minLon: 140.0, minLat: 35.0, maxLon: 140.01, maxLat: 35.0).padded(metres: 500)
        #expect(close(scope.bbox.minLon, expected.minLon) && close(scope.bbox.maxLon, expected.maxLon))
        #expect(close(scope.bbox.minLat, expected.minLat) && close(scope.bbox.maxLat, expected.maxLat))
        #expect(Set(scope.lines.map(\.lineID)) == [Fixture.main, Fixture.paired, Fixture.branch])
        #expect(scope.line(Fixture.main)?.alignmentPairs.map(\.with) == [Fixture.paired])
        #expect(scope.line(Fixture.paired)?.alignmentOf == Fixture.main)
        #expect(scope.line(Fixture.main)?.intervalIndices == [0, 1])
        #expect(scope.stations.compactMap(\.code).contains("100002"))
        #expect(!scope.sectionFeatureIndices.isEmpty)
        // Reversed order resolves the same area.
        let reversed = try AreaScope.resolve(.init(mode: .stationPair(lineID: Fixture.main, fromStationID: "100002", toStationID: "100001")), data: data)
        #expect(reversed.bbox == scope.bbox && reversed.lines == scope.lines)
    }

    @Test func lineSectionRectAndCentreBoxes() throws {
        let section = try AreaScope.resolve(.init(mode: .lineSection(lineID: Fixture.main, firstInterval: 1, lastInterval: 1), marginMetres: 0), data: data)
        #expect(close(section.bbox.minLon, 140.01) && close(section.bbox.maxLon, 140.02))
        #expect(!section.lines.map(\.lineID).contains(Fixture.east))

        let rect = try AreaScope.resolve(.init(mode: .rect(minLon: 140.029, minLat: 34.999, maxLon: 140.041, maxLat: 35.001), marginMetres: 0), data: data)
        #expect(rect.bbox == AreaBBox(minLon: 140.029, minLat: 34.999, maxLon: 140.041, maxLat: 35.001))
        #expect(rect.lines.map(\.lineID) == [Fixture.east])

        let centre = try AreaScope.resolve(.init(mode: .centre(lon: 140.0, lat: 35.02, radiusMetres: 300), marginMetres: 200), data: data)
        let expected = AreaBBox(minLon: 140.0, minLat: 35.02, maxLon: 140.0, maxLat: 35.02).padded(metres: 300).padded(metres: 200)
        #expect(close(centre.bbox.minLat, expected.minLat) && close(centre.bbox.maxLon, expected.maxLon))
        #expect(centre.lines.map(\.lineID) == [Fixture.corner])
    }

    @Test func invalidIdentifiersFailWithoutWidening() {
        let bad: [AreaSelection] = [
            .init(mode: .stationPair(lineID: "jp-missing", fromStationID: "100001", toStationID: "100002")),
            .init(mode: .stationPair(lineID: Fixture.main, fromStationID: "100001", toStationID: "999999")),
            .init(mode: .lineSection(lineID: Fixture.main, firstInterval: 0, lastInterval: 2)),
            .init(mode: .lineSection(lineID: "jp-missing", firstInterval: 0, lastInterval: 0)),
            .init(mode: .centre(lon: 140, lat: 35, radiusMetres: 0)),
        ]
        for selection in bad {
            #expect(throws: AreaRepairError.self) { try AreaScope.resolve(selection, data: data) }
        }
    }

    @Test func discoverRepoFindsPortFixturesMarker() throws {
        #expect(try DataRoot.discoverRepo(from: repo.appending(path: "app/data/stations.json")).standardizedFileURL.path
                == repo.standardizedFileURL.path)
    }
}

@Suite(.serialized)
struct DetectorTests {
    @Test func missingJunctionDetectedThenClearedByRow() throws {
        let repo = try Fixture.repo()
        let problems = try Fixture.detect(.missingJunction, Fixture.load(DataRoot(repo: repo)))
        let problem = try #require(problems.first { Set($0.lineIDs) == [Fixture.main, Fixture.branch] })
        #expect(problem.stationCode == "100002")
        #expect(abs(problem.measure - 11.1) < 0.5)
        let proposal = try #require(problem.proposal)
        #expect(proposal.op == .junctionAdd && proposal.after?["kind"] == .string("shortLink"))
        let fixed = try Fixture.patched(repo, [Fixture.provenance(proposal)])
        #expect(try Fixture.detect(.missingJunction, fixed).isEmpty)
    }

    @Test func lostHistoryStampsDetectedThenCleared() throws {
        let repo = try Fixture.repo()
        let data = try Fixture.load(DataRoot(repo: repo))
        let problems = try Fixture.detect(.lostHistoryStamp, data)
        let ghost = try #require(problems.first { $0.id == "lostHistoryStamp/jp.test.ghost.closure" })
        #expect(ghost.proposal == nil)
        let straddle = try #require(problems.first { $0.id.hasPrefix("lostHistoryStamp/jp.test.old.closure/") })
        let add = try #require(straddle.proposal)
        #expect(add.op == .historyRetirementAdd && !add.writable && add.mirror?.contains("jp-rail-history-events") == true)

        // Unmatched retirement: re-point it at the real line.
        let before = try #require(try data.historyRows().retirements.first { $0["history_id"] == .string("jp.test.ghost.closure") })
        var after = before
        var match = after["match"]!
        match["line_name"] = .string("旧線")
        match["bbox"] = .array([139.9999, 35.0099, 140.0121, 35.0101].map(AreaJSON.number))
        after["match"] = match
        let update = PatchOp(op: .historyRetirementUpdate, key: "jp.test.ghost.closure", before: before, after: after)
        let fixed = try Fixture.patched(repo, [Fixture.provenance(add), Fixture.provenance(update)])
        #expect(try Fixture.detect(.lostHistoryStamp, fixed).isEmpty)
    }

    @Test func uncertifiedPairedLineDetectedThenCleared() throws {
        let repo = try Fixture.repo()
        let problems = try Fixture.detect(.uncertifiedPairedTrack, Fixture.load(DataRoot(repo: repo)))
        let problem = try #require(problems.first { $0.id == "uncertifiedPairedTrack/\(Fixture.paired)/0" })
        #expect(problem.proposal?.op == .packageAlignmentPairSet)
        #expect(problems.count == 1, "the base line certifies: \(problems.map(\.id))")
        let set = PatchOp(op: .packageAlignmentPairSet, key: Fixture.paired,
                          before: .object([("permittedTraversal", .string("forward"))]),
                          after: .object([("permittedTraversal", .null)]))
        #expect(try Fixture.detect(.uncertifiedPairedTrack, Fixture.patched(repo, [Fixture.provenance(set)])).isEmpty)
    }

    @Test func stationDotOffLineDetectedThenCleared() throws {
        let repo = try Fixture.repo()
        let problems = try Fixture.detect(.stationDotOffLine, Fixture.load(DataRoot(repo: repo)))
        #expect(problems.map(\.id) == ["stationDotOffLine/\(Fixture.east)/100006"])
        let problem = try #require(problems.first)
        #expect(abs(problem.measure - 60) < 1)
        let proposal = try #require(problem.proposal)
        #expect(proposal.after?.arrayValue?.compactMap(\.doubleValue).map { ($0 * 1e6).rounded() / 1e6 } == [140.04, 35.0])
        #expect(try Fixture.detect(.stationDotOffLine, Fixture.patched(repo, [Fixture.provenance(proposal)])).isEmpty)
    }

    @Test func cornerOverRoundedAtThreshold() throws {
        let data = try Fixture.load(DataRoot(repo: try Fixture.repo()))
        var probe = AreaThresholds()
        probe.cornerDeviationMetres = 0
        var gentle: [Double: Double] = [:], right: [Double: Double] = [:]
        for zoom in [8.0, 9, 10, 12, 14, 17] {
            probe.roundingZoom = zoom
            let found = try Fixture.detect(.overRoundedCorner, data, thresholds: probe)
            gentle[zoom] = found.first { $0.lineIDs == [Fixture.gentle] }?.measure ?? 0
            right[zoom] = found.first { $0.lineIDs == [Fixture.corner] }?.measure ?? 0
        }
        print("CORNER deviation by zoom, 25°: \(gentle.sorted { $0.key < $1.key }) 90°: \(right.sorted { $0.key < $1.key })")
        var thresholds = AreaThresholds()
        // The diagnostics smoother keeps a surveyed 90° corner hard at every zoom.
        #expect(right.values.allSatisfy { $0 <= thresholds.cornerDeviationMetres })
        thresholds.roundingZoom = try #require(gentle.filter { $0.value > thresholds.cornerDeviationMetres }.keys.max(),
                                               "no zoom over-rounds the 25° corner: \(gentle)")
        let problem = try #require(try Fixture.detect(.overRoundedCorner, data, thresholds: thresholds).first { $0.lineIDs == [Fixture.gentle] })
        #expect(problem.proposal == nil && problem.severity == .warning)
        // Exactly at the measured deviation the corner passes; just below it fails.
        thresholds.cornerDeviationMetres = problem.measure
        #expect(try Fixture.detect(.overRoundedCorner, data, thresholds: thresholds).isEmpty)
        thresholds.cornerDeviationMetres = problem.measure - 0.01
        #expect(try Fixture.detect(.overRoundedCorner, data, thresholds: thresholds).count == 1)
        // At street zoom the same corner is drawn tight.
        #expect(gentle[17]! <= AreaThresholds().cornerDeviationMetres)
    }

    @Test func pairedTrackOnTheLeftDeclaredUpIsFlaggedDownIsClear() throws {
        let repo = try Fixture.repo()
        let problems = try Fixture.detect(.pairedDirectionSide, Fixture.load(DataRoot(repo: repo)))
        #expect(problems.map(\.id) == ["pairedDirectionSide/\(Fixture.paired)"])
        let problem = try #require(problems.first)
        #expect(problem.severity == .review && problem.measure > 0.7)
        #expect(problem.evidence.first?.contains("left fraction 1.00") == true, "\(problem.evidence)")
        let flip = try #require(problem.proposal)
        #expect(flip.after == .object([("alignmentDirection", .string("down"))]) && !flip.writable)
        #expect(try Fixture.detect(.pairedDirectionSide, Fixture.patched(repo, [Fixture.provenance(flip)])).isEmpty)
    }

    @Test func thresholdsDecodePartialOverrides() throws {
        let decoded = try JSONDecoder().decode(AreaThresholds.self, from: Data(#"{"stationOffLineMetres": 40, "marginMetres": 250}"#.utf8))
        #expect(decoded.stationOffLineMetres == 40 && decoded.marginMetres == 250)
        #expect(decoded.junctionSearchMetres == 300 && decoded.cornerDeviationMetres == 15)
        #expect(try JSONDecoder().decode(AreaThresholds.self, from: JSONEncoder().encode(decoded)) == decoded)
    }

    @Test func previewReportsClearedProblems() throws {
        let repo = try Fixture.repo()
        let baseline = try Fixture.load(DataRoot(repo: repo))
        let scope = try AreaScope.resolve(Fixture.everything, data: baseline)
        let problem = try #require(AreaProblems.detect(scope: scope, data: baseline, kinds: [.stationDotOffLine]).first)
        let patched = try Fixture.patched(repo, [Fixture.provenance(problem.proposal!)])
        let preview = try Preview.run(baseline: baseline, patched: patched, scope: scope)
        #expect(preview.cleared.contains(problem.id))
        #expect(preview.introduced.isEmpty, "\(preview.introduced)")
        #expect(preview.geometryAfter.stations.contains { $0.stationID == "100006" && abs($0.anchor.lat - 35.0) < 1e-6 })
        let evidence = try AreaEvidence.make(data: baseline, scope: scope, rides: preview.ridesBefore, problems: preview.problemsBefore)
        let url = try evidence.write(to: repo.appending(path: ".evidence"))
        let json = try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any]
        #expect(json?["format"] as? String == "jtm-area-evidence-v1")
        #expect((json?["pairedTracks"] as? [Any])?.count == 2)
        #expect((json?["junctions"] as? [Any])?.isEmpty == true)
    }
}
