import Foundation
@testable import AreaKit
import RailInspection

/// A writable copy of the synthetic fixture repository (regenerate with
/// Fixtures/make_fixtures.py; six lines of
/// テスト鉄道 near 140.0E 35.0N, two retirements, three real junction rows).
enum Fixture {
    static let main = "jp-テスト鉄道-本線"
    static let paired = "jp-テスト鉄道-本線-p1"
    static let branch = "jp-テスト鉄道-支線"
    static let east = "jp-テスト鉄道-東線"
    static let corner = "jp-テスト鉄道-角線"
    static let gentle = "jp-テスト鉄道-緩線"

    /// Every fixture line, with a small margin.
    static let everything = AreaSelection(mode: .rect(minLon: 139.999, minLat: 34.999, maxLon: 140.041, maxLat: 35.041), marginMetres: 100)

    static func repo() throws -> URL {
        guard let source = Bundle.module.url(forResource: "Fixtures", withExtension: nil)?.appending(path: "repo") else {
            throw AreaRepairError.repositoryNotFound("Fixtures")
        }
        let target = FileManager.default.temporaryDirectory.appending(path: "areakit-\(UUID().uuidString)")
        try FileManager.default.copyItem(at: source, to: target)
        return target
    }

    static func load(_ root: DataRoot) throws -> AreaData { try AreaData.load(root) }

    static func detect(_ kind: Problem.Kind, _ data: AreaData, thresholds: AreaThresholds = .default) throws -> [Problem] {
        let scope = try AreaScope.resolve(everything, data: data)
        return AreaProblems.detect(scope: scope, data: data, thresholds: thresholds, kinds: [kind])
    }

    /// Applies ops on a scratch overlay and reloads.
    static func patched(_ repo: URL, _ ops: [PatchOp]) throws -> AreaData {
        let patch = AreaPatch(id: "fixture", area: everything, ops: ops)
        let root = try ScratchOverlay.materialize(repo: repo, patches: [patch], into: repo.appending(path: ".scratch"))
        return try load(root)
    }

    /// Fills the op's reason and source and, for a drafted junction row, the
    /// row evidence the reviewer would add (the registry rules require it).
    static func provenance(_ op: PatchOp) -> PatchOp {
        var op = op
        op.reason = "fixture repair"
        op.source = ["https://example.org/evidence"]
        if op.op.file == .junctions, var row = op.after, row["evidence"]?.arrayValue?.isEmpty != false {
            row["evidence"] = .array(op.source.map(AreaJSON.string))
            op.after = row
        }
        return op
    }
}

/// Records commands and answers with scripted results.
final class FakeGuardRunner: GuardCommandRunning, @unchecked Sendable {
    var commands: [GuardCommand] = []
    let answer: (GuardCommand, URL) -> GuardCommandResult
    init(_ answer: @escaping (GuardCommand, URL) -> GuardCommandResult) { self.answer = answer }
    func run(_ command: GuardCommand, repo: URL) throws -> GuardCommandResult {
        commands.append(command)
        return answer(command, repo)
    }
}
