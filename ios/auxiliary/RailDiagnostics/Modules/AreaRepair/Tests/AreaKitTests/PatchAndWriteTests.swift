import Foundation
import Testing
@testable import AreaKit
import RailInspection

struct AreaPatchTests {
    private func junctions(_ repo: URL) throws -> Data {
        try Data(contentsOf: repo.appending(path: DataFile.junctions.relativePath))
    }

    @Test func serializerReproducesTheJunctionFileExactly() throws {
        let data = try junctions(try Fixture.repo())
        #expect(Data((try AreaJSON.parse(data).serialized() + "\n").utf8) == data)
    }

    @Test func junctionAddUpdateRemoveSpliceAndInvertExactly() throws {
        let original = try junctions(try Fixture.repo())
        let rows = try JunctionFileEditor.rows(in: original)
        // add → only an appended row; inverse restores bytes.
        var row = rows[0]
        row["id"] = .string("area-test-row")
        let add = PatchOp(op: .junctionAdd, key: "area-test-row", before: nil, after: row)
        let added = try JunctionFileEditor.apply(add, to: original)
        let tail = Data("\n  ]\n}\n".utf8)
        #expect(added.prefix(original.count - tail.count) == original.prefix(original.count - tail.count))
        #expect(added.suffix(tail.count) == tail)
        #expect(try JunctionFileEditor.apply(add.inverse, to: added) == original)
        // update of a middle row → bytes outside that row unchanged; inverse exact.
        var changed = rows[1]
        changed["reviewedAt"] = .string("2026-11-06")
        let update = PatchOp(op: .junctionUpdate, key: rows[1]["id"]!.stringValue!, before: rows[1], after: changed)
        let updated = try JunctionFileEditor.apply(update, to: original)
        let text = String(decoding: original, as: UTF8.self), newText = String(decoding: updated, as: UTF8.self)
        let start = try #require(text.range(of: "\"id\": \"\(rows[1]["id"]!.stringValue!)\""))
        #expect(newText.hasPrefix(String(text[..<start.lowerBound])))
        #expect(newText.replacingOccurrences(of: "\"reviewedAt\": \"2026-11-06\"", with: "\"reviewedAt\": \"\(rows[1]["reviewedAt"]!.stringValue!)\"") == text)
        #expect(updated.count == original.count)
        #expect(try JunctionFileEditor.apply(update.inverse, to: updated) == original)
        // remove the last row; re-adding it (canonical key order) is exact.
        let last = rows[rows.count - 1]
        let remove = PatchOp(op: .junctionRemove, key: last["id"]!.stringValue!, before: last, after: nil)
        let removed = try JunctionFileEditor.apply(remove, to: original)
        #expect(try JunctionFileEditor.rows(in: removed).count == rows.count - 1)
        #expect(try JunctionFileEditor.apply(remove.inverse, to: removed) == original)
        // a stale before value is refused.
        #expect(throws: AreaRepairError.self) { try JunctionFileEditor.apply(update, to: updated) }
    }

    @Test func historyAndPackageOpsInvertToIdenticalBytes() throws {
        let repo = try Fixture.repo()
        let data = try Fixture.load(DataRoot(repo: repo))
        let scope = try AreaScope.resolve(Fixture.everything, data: data)
        let problems = AreaProblems.detect(scope: scope, data: data, kinds: [.lostHistoryStamp, .stationDotOffLine])
        for problem in problems {
            guard let op = problem.proposal else { continue }
            let file = op.op.file
            let original = try Data(contentsOf: repo.appending(path: file.relativePath))
            let patched = try DataFileEditor.apply([op], file: file, to: original)
            #expect(patched != original)
            #expect(try DataFileEditor.apply([op.inverse], file: file, to: patched) == original, "\(op.op.rawValue)")
        }
        let pairing = PatchOp(op: .packageAlignmentPairSet, key: Fixture.paired,
                              before: .object([("permittedTraversal", .string("forward")), ("alignmentDirection", .string("up"))]),
                              after: .object([("permittedTraversal", .string("reverse")), ("alignmentDirection", .string("down"))]))
        let package = try Data(contentsOf: repo.appending(path: DataFile.package.relativePath))
        let changed = try DataFileEditor.apply([pairing], file: .package, to: package)
        #expect(try DataFileEditor.apply([pairing.inverse], file: .package, to: changed) == package)
        // Removing a field and restoring it is equal in value (the field returns at the row's end).
        let removal = PatchOp(op: .packageAlignmentPairSet, key: Fixture.paired,
                              before: .object([("permittedTraversal", .string("forward"))]), after: .object([("permittedTraversal", .null)]))
        let restored = try DataFileEditor.apply([removal.inverse], file: .package, to: try DataFileEditor.apply([removal], file: .package, to: package))
        #expect(try AreaJSON.parse(restored)["lines"]?.arrayValue?[1]["permittedTraversal"] == .string("forward"))
    }

    @Test func patchRoundTripsAndRequiresProvenance() throws {
        let row = AreaJSON.object([("id", .string("x")), ("region", .string("jp")), ("from", .object([("coordinate", .array([.number("139.81374"), .number("35.70843")]))]))])
        let op = PatchOp(op: .junctionAdd, key: "x", before: nil, after: row)
        let patch = AreaPatch(id: "p", createdAt: "2026-11-06T00:00:00Z", area: Fixture.everything, ops: [op])
        let decoded = try AreaPatch.decode(try patch.encoded())
        #expect(decoded == patch)
        #expect(decoded.guards == [.junction])
        #expect(String(decoding: try patch.encoded(), as: UTF8.self).contains("139.81374"))
        #expect(throws: AreaRepairError.self) { try patch.validate() }
        #expect(throws: AreaRepairError.self) {
            try AreaPatch.decode(Data(#"{"format":"jtm-area-patch-v1","id":"p","createdAt":"t","area":{"kind":"centre","lon":1,"lat":2,"radiusMetres":3},"ops":[],"extra":1}"#.utf8))
        }
        var good = patch
        good.ops = [Fixture.provenance(op)]
        try good.validate()
        #expect(good.inverse.ops.first?.op == .junctionRemove)
    }
}

@Suite(.serialized)
struct WriteTransactionTests {
    static let passing = "Test run with 12 tests in 3 suites passed after 1.2 seconds."

    private func setUp(_ answer: @escaping (GuardCommand, URL) -> GuardCommandResult)
        throws -> (URL, FakeGuardRunner, WriteTransaction, AreaPatch) {
        let repo = try Fixture.repo()
        let data = try Fixture.load(DataRoot(repo: repo))
        let problem = try #require(try Fixture.detect(.missingJunction, data).first { $0.proposal != nil })
        let runner = FakeGuardRunner(answer)
        let transaction = WriteTransaction(repo: repo, patchDirectory: repo.appending(path: ".patches/p"), guards: GuardRunner(runner: runner))
        let patch = AreaPatch(id: "p", area: Fixture.everything, ops: [Fixture.provenance(problem.proposal!)])
        return (repo, runner, transaction, patch)
    }

    private func bytes(_ repo: URL, _ path: String) throws -> Data { try Data(contentsOf: repo.appending(path: path)) }

    /// Simulates the topology rebuild by rewriting the topology file.
    private static func answer(_ swiftOutput: String, exit: Int32 = 0) -> (GuardCommand, URL) -> GuardCommandResult {
        { command, repo in
            if command.shell == GuardRunner.topologyRegenerate {
                try? Data("{\"regenerated\": true}\n".utf8).write(to: repo.appending(path: WriteTransaction.topologyFile))
                return .init(exitCode: 0, output: "wrote topology")
            }
            return command.isSwiftTest ? .init(exitCode: exit, output: swiftOutput) : .init(exitCode: 0, output: "ok")
        }
    }

    @Test func refusesWithoutConfirmation() throws {
        let (repo, runner, transaction, patch) = try setUp(Self.answer(Self.passing))
        let before = try bytes(repo, DataFile.junctions.relativePath)
        #expect(throws: AreaRepairError.confirmationRequired) { try transaction.write(patch, confirm: false) }
        #expect(try bytes(repo, DataFile.junctions.relativePath) == before)
        #expect(runner.commands.isEmpty)
    }

    @Test func refusesGeneratedPackageAndHistoryOps() throws {
        let (repo, _, transaction, _) = try setUp(Self.answer(Self.passing))
        let anchor = Fixture.provenance(PatchOp(op: .packageStationAnchorSet, key: "\(Fixture.east)/100006",
                                                before: .array([.number(140.04), .number(35.00054)]), after: .array([.number(140.04), .number(35.0)])))
        let package = try bytes(repo, DataFile.package.relativePath)
        #expect(throws: AreaRepairError.self) { try transaction.write(AreaPatch(id: "pkg", area: Fixture.everything, ops: [anchor]), confirm: true) }
        #expect(try bytes(repo, DataFile.package.relativePath) == package)
        let history = Fixture.provenance(PatchOp(op: .historyRetirementRemove, key: "jp.test.ghost.closure",
            before: try Fixture.load(DataRoot(repo: repo)).historyRows().retirements[1], after: nil))
        #expect(throws: AreaRepairError.self) { try transaction.write(AreaPatch(id: "h", area: Fixture.everything, ops: [history]), confirm: true) }
    }

    @Test func autoRevertsWhenAGuardFails() throws {
        let (repo, runner, transaction, patch) = try setUp(Self.answer("error: 1 test failed", exit: 1))
        let junctions = try bytes(repo, DataFile.junctions.relativePath)
        let topology = try bytes(repo, WriteTransaction.topologyFile)
        let receipt = try transaction.write(patch, confirm: true)
        #expect(receipt.status == .reverted)
        #expect(receipt.topologyRegenerated)
        #expect(try bytes(repo, DataFile.junctions.relativePath) == junctions)
        #expect(try bytes(repo, WriteTransaction.topologyFile) == topology)
        #expect(runner.commands.contains { $0.shell.contains("ShortLinkJunctionTests") })
        #expect(receipt.guards.contains { !$0.passed && $0.reason == "exit 1" })
    }

    @Test func zeroExecutedTestsIsAFailure() throws {
        let (repo, _, transaction, patch) = try setUp(Self.answer("Test run with 0 tests in 0 suites passed after 0.001 seconds."))
        let junctions = try bytes(repo, DataFile.junctions.relativePath)
        let receipt = try transaction.write(patch, confirm: true)
        #expect(receipt.status == .reverted)
        #expect(receipt.guards.contains { $0.reason.hasPrefix("0 tests executed") })
        #expect(try bytes(repo, DataFile.junctions.relativePath) == junctions)
        #expect(GuardRunner.executedTestCount("no summary here") == nil)
        #expect(GuardRunner.executedTestCount("Executed 4 tests, with 0 failures\n" + Self.passing) == 16)
    }

    @Test func writeThenUndoRestoresBytes() throws {
        let (repo, _, transaction, patch) = try setUp(Self.answer(Self.passing))
        let junctions = try bytes(repo, DataFile.junctions.relativePath)
        let topology = try bytes(repo, WriteTransaction.topologyFile)
        let receipt = try transaction.write(patch, confirm: true)
        #expect(receipt.status == .written, "\(receipt.guards)")
        #expect(try bytes(repo, DataFile.junctions.relativePath) != junctions)
        let directory = URL(fileURLWithPath: receipt.directory)
        #expect(FileManager.default.fileExists(atPath: directory.appending(path: "inverse.json").path))
        #expect(try AreaPatch.decode(Data(contentsOf: directory.appending(path: "inverse.json"))).ops.first?.op == .junctionRemove)
        #expect(throws: AreaRepairError.confirmationRequired) { try transaction.undo(receiptAt: receipt.receiptURL, confirm: false) }
        let undone = try transaction.undo(receiptAt: receipt.receiptURL, confirm: true)
        #expect(undone.status == .undone)
        #expect(try bytes(repo, DataFile.junctions.relativePath) == junctions)
        #expect(try bytes(repo, WriteTransaction.topologyFile) == topology)
        #expect(throws: AreaRepairError.self) { try transaction.undo(receiptAt: receipt.receiptURL, confirm: true) }
    }

    @Test func undoRefusesAFileChangedAfterTheWrite() throws {
        let (repo, _, transaction, patch) = try setUp(Self.answer(Self.passing))
        let receipt = try transaction.write(patch, confirm: true)
        try Data("{}".utf8).write(to: repo.appending(path: DataFile.junctions.relativePath))
        #expect(throws: AreaRepairError.changedSinceWrite(DataFile.junctions.relativePath)) {
            try transaction.undo(receiptAt: receipt.receiptURL, confirm: true)
        }
    }
}
