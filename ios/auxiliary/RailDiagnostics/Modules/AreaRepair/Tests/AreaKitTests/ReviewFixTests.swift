import Foundation
import RailCore
import Testing
@testable import AreaKit
import RailInspection

/// Guards for the independent-review findings: interrupted writes, scratch
/// directories that alias repository data, one op-disposition decision,
/// junction proposal kinds, canonical inverse rows, loop spans, stroke
/// metrics and the heavy-job lock script.
@Suite(.serialized)
struct InterruptedWriteTests {
    struct Injected: Error {}
    static let passing = "Test run with 12 tests in 3 suites passed after 1.2 seconds."

    private func setUp() throws -> (URL, WriteTransaction, AreaPatch) {
        let repo = try Fixture.repo()
        let data = try Fixture.load(DataRoot(repo: repo))
        let problem = try #require(try Fixture.detect(.missingJunction, data).first { $0.proposal != nil })
        let runner = FakeGuardRunner { command, repo in
            if command.shell == GuardRunner.topologyRegenerate {
                try? Data("{\"regenerated\": true}\n".utf8).write(to: repo.appending(path: WriteTransaction.topologyFile))
                return .init(exitCode: 0, output: "wrote topology")
            }
            return .init(exitCode: 0, output: Self.passing)
        }
        let transaction = WriteTransaction(repo: repo, patchDirectory: repo.appending(path: ".patches/p"), guards: GuardRunner(runner: runner))
        return (repo, transaction, AreaPatch(id: "p", area: Fixture.everything, ops: [Fixture.provenance(problem.proposal!)]))
    }

    private func bytes(_ repo: URL, _ path: String) throws -> Data { try Data(contentsOf: repo.appending(path: path)) }

    private func receipts(_ transaction: WriteTransaction) throws -> [WriteReceipt] {
        let root = transaction.patchDirectory.appending(path: "receipts")
        return try FileManager.default.contentsOfDirectory(atPath: root.path).map {
            try JSONDecoder().decode(WriteReceipt.self, from: Data(contentsOf: root.appending(path: $0).appending(path: "receipt.json")))
        }
    }

    @Test func throwAfterTheFirstFileWriteRestoresAndIsNotWritten() throws {
        let (repo, setUpTransaction, patch) = try setUp()
        var transaction = setUpTransaction
        let junctions = try bytes(repo, DataFile.junctions.relativePath)
        let topology = try bytes(repo, WriteTransaction.topologyFile)
        transaction.afterFileWrite = { _ in throw Injected() }
        #expect(throws: Injected.self) { try transaction.write(patch, confirm: true) }
        #expect(try bytes(repo, DataFile.junctions.relativePath) == junctions)
        #expect(try bytes(repo, WriteTransaction.topologyFile) == topology)
        let receipt = try #require(try receipts(transaction).first)
        #expect(receipt.status == .reverted)
        #expect(receipt.files.map(\.relativePath) == [DataFile.junctions.relativePath, WriteTransaction.topologyFile])
        #expect(throws: AreaRepairError.self) { try transaction.undo(receiptAt: receipt.receiptURL, confirm: true) }
    }

    /// A write killed after the junction file landed but before the topology
    /// rebuild leaves a `.pending` receipt; undo restores it.
    @Test func pendingReceiptUndoRestores() throws {
        let (repo, transaction, patch) = try setUp()
        let junctions = try bytes(repo, DataFile.junctions.relativePath)
        let topology = try bytes(repo, WriteTransaction.topologyFile)
        var receipt = try transaction.write(patch, confirm: true)
        #expect(receipt.status == .written)
        // Rewind to the interrupted state: topology never rebuilt, receipt still pending.
        try topology.write(to: repo.appending(path: WriteTransaction.topologyFile))
        receipt.status = .pending
        receipt.guards = []
        receipt.files[1].sha256After = nil
        try JSONEncoder().encode(receipt).write(to: receipt.receiptURL)
        #expect(try bytes(repo, DataFile.junctions.relativePath) != junctions)

        let undone = try transaction.undo(receiptAt: receipt.receiptURL, confirm: true)
        #expect(undone.status == .undone)
        #expect(try bytes(repo, DataFile.junctions.relativePath) == junctions)
        #expect(try bytes(repo, WriteTransaction.topologyFile) == topology)
    }

    @Test func pendingReceiptWithNothingWrittenIsANoOpAndForeignBytesAreRefused() throws {
        let (repo, transaction, patch) = try setUp()
        let junctions = try bytes(repo, DataFile.junctions.relativePath)
        var receipt = try transaction.write(patch, confirm: true)
        let written = try bytes(repo, DataFile.junctions.relativePath)
        try junctions.write(to: repo.appending(path: DataFile.junctions.relativePath))
        receipt.status = .pending
        try JSONEncoder().encode(receipt).write(to: receipt.receiptURL)
        // Neither original nor written bytes → refused, nothing changes.
        try Data("{}".utf8).write(to: repo.appending(path: DataFile.junctions.relativePath))
        #expect(throws: AreaRepairError.changedSinceWrite(DataFile.junctions.relativePath)) {
            try transaction.undo(receiptAt: receipt.receiptURL, confirm: true)
        }
        #expect(try bytes(repo, DataFile.junctions.relativePath) == Data("{}".utf8))
        // Original bytes already in place → no-op.
        try junctions.write(to: repo.appending(path: DataFile.junctions.relativePath))
        #expect(try transaction.undo(receiptAt: receipt.receiptURL, confirm: true).status == .undone)
        #expect(try bytes(repo, DataFile.junctions.relativePath) == junctions)
        #expect(written != junctions)
    }
}

struct ScratchDirectoryTests {
    private func snapshot(_ repo: URL) throws -> [Data] {
        try DataFile.allCases.map { try Data(contentsOf: repo.appending(path: $0.relativePath)) }
    }

    @Test func materializeRefusesTheRepositoryAndItsDataTree() throws {
        let repo = try Fixture.repo()
        let before = try snapshot(repo)
        let patch = AreaPatch(id: "s", area: Fixture.everything, ops: [JunctionRuleTests.shortLink(metres: 12)])
        let link = FileManager.default.temporaryDirectory.appending(path: "areakit-link-\(UUID().uuidString)")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: repo)
        for directory in [repo, repo.appending(path: "."), repo.deletingLastPathComponent(), repo.appending(path: "app"),
                          repo.appending(path: "app/data"), repo.appending(path: "app/new-scratch"), link] {
            #expect(throws: AreaRepairError.self, "\(directory.path)") {
                try ScratchOverlay.materialize(repo: repo, patches: [patch], into: directory)
            }
        }
        #expect(try snapshot(repo) == before)
        // A scratch directory beside the data stays allowed.
        try ScratchOverlay.materialize(repo: repo, patches: [patch], into: repo.appending(path: ".scratch"))
        #expect(try snapshot(repo) == before)
    }

    @Test func materializeRefusesTargetsThatSymlinkIntoRepositoryData() throws {
        let repo = try Fixture.repo()
        let before = try snapshot(repo)
        let scratch = FileManager.default.temporaryDirectory.appending(path: "areakit-scratch-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: scratch.appending(path: "app"), withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(at: scratch.appending(path: "app/data"), withDestinationURL: repo.appending(path: "app/data"))
        let patch = AreaPatch(id: "s", area: Fixture.everything, ops: [JunctionRuleTests.shortLink(metres: 12)])
        #expect(throws: AreaRepairError.self) { try ScratchOverlay.materialize(repo: repo, patches: [patch], into: scratch) }
        #expect(try snapshot(repo) == before)
    }
}

struct OpDispositionTests {
    static func op(_ kind: PatchOp.Kind, writable: Bool) -> PatchOp {
        let value: AreaJSON = switch kind.file {
        case .history: .object([("history_id", .string("k"))])
        default: .object([("id", .string("k"))])
        }
        var op = PatchOp(op: kind, key: "k", before: kind.isAdd ? nil : value, after: kind.isRemove ? nil : value,
                         reason: "r", source: ["s"])
        op.writable = writable
        return op
    }

    /// The dry-run plan and the write check agree for every op kind × flag.
    @Test func planAndCheckAgreeForEveryOpKindAndFlag() throws {
        let repo = try Fixture.repo()
        for kind in PatchOp.Kind.allCases {
            for allowGenerated in [false, true] {
                for writable in [false, true] {
                    let transaction = WriteTransaction(repo: repo, patchDirectory: repo, allowGenerated: allowGenerated)
                    let patch = AreaPatch(id: "d", area: Fixture.everything, ops: [Self.op(kind, writable: writable)])
                    let disposition = try #require(transaction.plan(patch).first?.disposition)
                    let checked = (try? transaction.check(patch)) != nil
                    let label = "\(kind.rawValue) allowGenerated=\(allowGenerated) writable=\(writable)"
                    #expect(checked == (disposition.status == .writable), "\(label)")
                    switch kind.file {
                    case .package: #expect(disposition.status == .refused, "\(label)")
                    case .history:
                        #expect(disposition.status == (allowGenerated ? .writable : .generatedNeedsFlag), "\(label)")
                        #expect((disposition.generatorFix?.contains("app/scripts/railway/jp-rail-history-events.json") == true) == allowGenerated, "\(label)")
                    default: #expect(disposition.status == (writable ? .writable : .refused), "\(label)")
                    }
                }
            }
        }
    }
}

struct JunctionProposalKindTests {
    /// Moves 支線's first surveyed vertex (beside 本線 at 駅二) and returns the proposal.
    private func proposal(firstBranchVertex: [Double]) throws -> PatchOp {
        let repo = try Fixture.repo()
        let url = repo.appending(path: DataFile.sections.relativePath)
        let text = try String(contentsOf: url, encoding: .utf8)
        #expect(text.contains("[140.01,35.0001]"))
        try text.replacingOccurrences(of: "[140.01,35.0001]", with: "[\(firstBranchVertex[0]),\(firstBranchVertex[1])]")
            .write(to: url, atomically: true, encoding: .utf8)
        let data = try Fixture.load(DataRoot(repo: repo))
        let problem = try #require(try Fixture.detect(.missingJunction, data).first { $0.lineIDs.contains(Fixture.branch) })
        let op = Fixture.provenance(try #require(problem.proposal))
        try JunctionRowRules.validate(try #require(op.after), op: op)
        try ScratchOverlay.materialize(repo: repo, patches: [AreaPatch(id: "k", area: Fixture.everything, ops: [op])],
                                       into: repo.appending(path: ".scratch"))
        return op
    }

    /// Distinct vertices under 1 m apart (the smallest 5-decimal step, ~0.9 m) are a shortLink, not a zeroLength row.
    @Test func subMetreGapProposesAValidShortLink() throws {
        let op = try proposal(firstBranchVertex: [140.01001, 35.0])
        #expect(op.after?["kind"]?.stringValue == "shortLink")
    }

    @Test func identicalVerticesProposeAValidZeroLengthRow() throws {
        let op = try proposal(firstBranchVertex: [140.01, 35.0])
        #expect(op.after?["kind"] == nil)
        #expect(op.after?["from"]?["coordinate"] == op.after?["to"]?["coordinate"])
    }
}

struct CanonicalInverseTests {
    @Test func inverseOfANonCanonicalAddAppliesCleanly() throws {
        let original = try Data(contentsOf: try Fixture.repo().appending(path: DataFile.junctions.relativePath))
        var row = try #require(try JunctionFileEditor.rows(in: original).first)
        row["id"] = .string("area-noncanonical")
        guard case .object(let pairs) = row else { Issue.record("row is not an object"); return }
        let reversed = AreaJSON.object(Array(pairs.reversed()))
        #expect(reversed != JunctionFileEditor.canonicalised(reversed))
        let add = PatchOp(op: .junctionAdd, key: "area-noncanonical", before: nil, after: reversed)
        let added = try JunctionFileEditor.apply(add, to: original)
        #expect(try JunctionFileEditor.apply(add.inverse, to: added) == original)
        let patch = AreaPatch(id: "c", area: Fixture.everything, ops: [add])
        #expect(try DataFileEditor.apply(patch.inverse.ops, file: .junctions, to: added) == original)
    }
}

struct LoopSpanTests {
    static let loop = "jp-テスト鉄道-環線"
    static let codes = ["200001", "200002", "200003", "200004"]

    /// The fixture plus a four-station square loop at 140.2E 35.2N (outside `Fixture.everything`).
    static func loopRepo() throws -> URL {
        let repo = try Fixture.repo()
        let url = repo.appending(path: DataFile.package.relativePath)
        var tree = try AreaJSON.parse(Data(contentsOf: url))
        let corners: [(Double, Double)] = [(140.2, 35.2), (140.21, 35.2), (140.21, 35.21), (140.2, 35.21)]
        func n(_ v: Double) -> AreaJSON { .number(String(v)) }
        let stations = zip(codes, corners).enumerated().map { i, pair in
            AreaJSON.array([.string(pair.0), .string("環\(i)"), n(pair.1.0), n(pair.1.1), .string(""), .number("1")])
        }
        let segments = corners.indices.map { i -> AreaJSON in
            let a = corners[i], b = corners[(i + 1) % corners.count]
            return .array([.number("1.1"), .number("0"),
                           .array([.array([n(a.0), n(a.1)]), .array([n((a.0 + b.0) / 2), n((a.1 + b.1) / 2)]), .array([n(b.0), n(b.1)])])])
        }
        var lines = tree["lines"]?.arrayValue ?? []
        lines.append(.object([("id", .string(loop)), ("name", .string("環線")), ("operator", .string("テスト鉄道")), ("rank", .number("2")),
                              ("isLoop", .number("1")), ("stations", .array(stations)), ("segments", .array(segments))]))
        tree["lines"] = .array(lines)
        try Data(tree.serialized(style: .compact).utf8).write(to: url)
        return repo
    }

    @Test func spanTakesTheShorterWayRoundOnlyOnLoops() {
        #expect(StationSpan.intervals(0, 3, stationCount: 4, isLoop: true) == [3])
        #expect(StationSpan.intervals(3, 0, stationCount: 4, isLoop: true) == [3])
        #expect(StationSpan.intervals(0, 3, stationCount: 4, isLoop: false) == [0, 1, 2])
        #expect(StationSpan.intervals(1, 9, stationCount: 10, isLoop: true) == [9, 0])
        #expect(StationSpan.intervals(0, 2, stationCount: 4, isLoop: true) == [0, 1])
        #expect(StationSpan.stations([9, 0], stationCount: 10) == [9, 0, 1])
    }

    @Test func wrapStationPairSelectsOnlyTheWrapInterval() throws {
        let data = try Fixture.load(DataRoot(repo: try Self.loopRepo()))
        #expect(data.linesByID[Self.loop]?.isLoop == true)
        let scope = try AreaScope.resolve(AreaSelection(mode: .stationPair(lineID: Self.loop, fromStationID: Self.codes[0],
                                                                          toStationID: Self.codes[3]), marginMetres: 10), data: data)
        // Interval 3 is the west side (lon 140.2); the long way round would reach lon 140.21.
        #expect(scope.bbox.maxLon < 140.205, "\(scope.bbox)")
        #expect(scope.bbox.maxLat > 35.209)
    }

    @Test func legAcrossTheWrapMatchesItsInterval() throws {
        let data = try Fixture.load(DataRoot(repo: try Self.loopRepo()))
        // A box on the middle of the west side: only interval 3, no station.
        let scope = try AreaScope.resolve(AreaSelection(mode: .rect(minLon: 140.1999, minLat: 35.2049, maxLon: 140.2001, maxLat: 35.2051),
                                                        marginMetres: 0), data: data)
        #expect(scope.line(Self.loop)?.intervalIndices == [3])
        func crosses(_ a: Int, _ b: Int) -> Bool {
            RideSelection.sectionCrosses(RouteSection(fromN02StationCode: Self.codes[a], toN02StationCode: Self.codes[b]), scope: scope, data: data)
        }
        #expect(crosses(3, 0))
        #expect(crosses(0, 3))
        #expect(!crosses(0, 1))
        #expect(!crosses(1, 2))
    }

    @Test func pairedSideSamplesOnlyInsideTheArea() throws {
        let data = try Fixture.load(DataRoot(repo: try Fixture.repo()))
        #expect(PairedDirectionSideDetector.measure(data, lineID: Fixture.paired) != nil)
        let everything = try AreaScope.resolve(Fixture.everything, data: data).bbox
        #expect(PairedDirectionSideDetector.measure(data, lineID: Fixture.paired, within: everything) != nil)
        let elsewhere = AreaBBox(minLon: 141, minLat: 36, maxLon: 141.01, maxLat: 36.01)
        #expect(PairedDirectionSideDetector.measure(data, lineID: Fixture.paired, within: elsewhere) == nil)
    }
}

struct StrokeMetricTests {
    /// RailStyle: strokeCornerRadius = stationDiameter (6) × 0.6, scaled by the weight ramp.
    @Test func cornerRadiusIsRailStylesExpressionBitForBit() {
        for zoom in [0.0, 8, 14, 15, 17, 18, 22] {
            let w = StrokeStyle.weight(atZoom: zoom)
            let style = StrokeStyle.diagnosticsDefault(zoom: zoom)
            let stationDiameter = 6.0
            #expect(style.cornerRadius == stationDiameter * 0.6 * w)
            #expect(style.railWidth == stationDiameter * 0.25 * w)
            #expect(style.laneGap == (stationDiameter * 0.25 + 1.2) * w)
            // RailStyle.hardCornerMaxDeviation(atScale:) = railWidth × scale / 2 (v8 sharp corners).
            #expect(style.hardCornerMaxDeviation == stationDiameter * 0.25 * w / 2)
        }
    }
}

#if os(macOS)
struct HeavyJobLockTests {
    private func run(_ script: String, lockCommand: String) throws -> (Int32, String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = ["-c", script]
        process.environment = ["JTM_LOCK_CMD": lockCommand, "PATH": "/usr/bin:/bin"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        try process.run()
        let output = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return (process.terminationStatus, String(decoding: output, as: UTF8.self))
    }

    /// A lock whose pid file names a dead process is cleared; the holder
    /// records pid and cmd; the exit trap removes all of it.
    @Test func lockedScriptClearsADeadHolderRecordsItselfAndCleansUp() throws {
        let lock = FileManager.default.temporaryDirectory.appending(path: "areakit-lock-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: lock, withIntermediateDirectories: true)
        let dead = Process()
        dead.executableURL = URL(fileURLWithPath: "/usr/bin/true")
        try dead.run()
        dead.waitUntilExit()
        try "\(dead.processIdentifier)\n".write(to: lock.appending(path: "pid"), atomically: true, encoding: .utf8)
        try "old job\n".write(to: lock.appending(path: "cmd"), atomically: true, encoding: .utf8)

        let script = ProcessGuardCommandRunner.lockedScript(#"cat "$LOCK/cmd"; test "$(cat "$LOCK/pid")" = "$$" && echo pid-ok"#, lock: lock.path)
        let (status, output) = try run(script, lockCommand: "bash ios/verify.sh swift --filter 'X'")
        #expect(status == 0, "\(output)")
        #expect(output == "bash ios/verify.sh swift --filter 'X'\npid-ok\n")
        #expect(!FileManager.default.fileExists(atPath: lock.path))
    }
}
#endif
