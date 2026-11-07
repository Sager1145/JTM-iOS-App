import CryptoKit
import Foundation

/// The record of one repository write, kept beside its backups under
/// `<patchDirectory>/receipts/<timestamp>/receipt.json`. It is saved as
/// `.pending`, listing every file with its backup and hashes, before the
/// first repository byte changes, so an interrupted write can be undone.
public struct WriteReceipt: Codable, Equatable, Sendable {
    public static let format = "jtm-area-receipt-v1"
    public struct FileRecord: Codable, Equatable, Sendable {
        public var relativePath: String
        /// Backup path relative to the receipt directory.
        public var backup: String
        public var sha256Before: String
        /// The bytes the write puts there; nil for the regenerated topology
        /// file until its rebuild has run (undo then restores it from backup).
        public var sha256After: String?
    }
    public enum Status: String, Codable, Sendable {
        /// Recorded before the first repository write; the write has not
        /// finished (it is running, or it was interrupted). `undo` recovers it.
        case pending
        /// Written and every guard passed.
        case written
        /// A guard, the topology rebuild or the write itself failed; the backups were restored.
        case reverted
        /// Undone from the backups.
        case undone
    }
    public var format: String
    public var patchID: String
    public var createdAt: String
    public var directory: String
    public var files: [FileRecord]
    public var topologyRegenerated: Bool
    public var guards: [GuardOutcome]
    public var status: Status
    public var undoGuards: [GuardOutcome]?

    public var receiptURL: URL { URL(fileURLWithPath: directory).appending(path: "receipt.json") }
}

/// What a write does with one op: the single decision both the dry-run plan
/// and ``WriteTransaction/check(_:)`` use.
public struct OpDisposition: Equatable, Sendable {
    public enum Status: String, Sendable {
        case writable
        /// An op on generated app/data/rail-history.json without --allow-generated.
        case generatedNeedsFlag = "generated-needs-flag"
        case refused
    }
    public var status: Status
    public var note: String?
    /// For a writable op on a generated file: the generator source the same
    /// change must be mirrored into, or the next rebuild overwrites it.
    public var generatorFix: String?

    /// rail-history.json ops are writable only with `allowGenerated` (and then
    /// carry their generator fix); jp-2025.json ops are always refused;
    /// junction ops follow their `writable` flag.
    public static func of(_ op: PatchOp, allowGenerated: Bool) -> OpDisposition {
        let mirror = op.mirror ?? "its source"
        switch op.op.file {
        case .package:
            return .init(status: .refused, note: "targets generated \(DataFile.package.relativePath); mirror it into \(mirror) in the website repository instead")
        case .history where !allowGenerated:
            return .init(status: .generatedNeedsFlag, note: "targets generated \(DataFile.history.relativePath); pass --allow-generated with --confirm, and mirror it into \(mirror)")
        case .history:
            return .init(status: .writable, note: "generated file: mirror the same change into \(mirror) or the next history build overwrites it",
                         generatorFix: "\(op.op.rawValue) \(op.key) → \(mirror)")
        case .junctions where !op.writable:
            return .init(status: .refused, note: "marked not writable")
        default:
            return .init(status: .writable, note: op.mirror.map { "mirror into \($0)" })
        }
    }
}

/// Writes a reviewed patch to the repository: explicit confirmation, writable
/// ops only, backups + inverse patch + pending receipt first, topology rebuild
/// when junctions change, regression guards, automatic revert on any failure
/// (thrown or guard), and undo.
public struct WriteTransaction: Sendable {
    public static let topologyFile = "app/data/physical-rail-topology.json"
    public var repo: URL
    /// Receipts go to `<patchDirectory>/receipts/<timestamp>/`.
    public var patchDirectory: URL
    public var guards: GuardRunner
    /// Allows ops on generated rail-history.json (never the package).
    public var allowGenerated: Bool
    /// Test hook: called after each repository file write (fault injection).
    var afterFileWrite: (@Sendable (String) throws -> Void)?

    public init(repo: URL, patchDirectory: URL, guards: GuardRunner = GuardRunner(), allowGenerated: Bool = false) {
        self.repo = repo; self.patchDirectory = patchDirectory; self.guards = guards; self.allowGenerated = allowGenerated
    }

    /// Each op's disposition, in patch order.
    public func plan(_ patch: AreaPatch) -> [(op: PatchOp, disposition: OpDisposition)] {
        patch.ops.map { ($0, OpDisposition.of($0, allowGenerated: allowGenerated)) }
    }

    /// Generator sources the written patch's generated-file ops must be mirrored into.
    public func generatorFixes(_ patch: AreaPatch) -> [String] { plan(patch).compactMap(\.disposition.generatorFix) }

    /// Checks the patch is writable without touching anything.
    public func check(_ patch: AreaPatch) throws {
        try patch.validate(requireProvenance: true)
        for (op, disposition) in plan(patch) where disposition.status != .writable {
            throw AreaRepairError.refused("\(op.op.rawValue) \(op.key) \(disposition.note ?? disposition.status.rawValue).")
        }
        try JunctionRowRules.validateLineIDs(patch.ops, packageURL: repo.appending(path: DataFile.package.relativePath),
                                              historyURL: repo.appending(path: DataFile.history.relativePath))
    }

    /// Writes `patch`. Returns the receipt; `status == .reverted` means a
    /// guard failed and the repository was restored byte for byte. A thrown
    /// error after the first repository write restores the backups too (the
    /// receipt is then `.reverted`, or stays `.pending` if the restore itself
    /// failed, for `undo`) and is rethrown.
    public func write(_ patch: AreaPatch, confirm: Bool) throws -> WriteReceipt {
        guard confirm else { throw AreaRepairError.confirmationRequired }
        try check(patch)
        let fm = FileManager.default
        var newContents: [(String, Data, Data)] = []  // path, before, after
        for file in patch.files {
            let url = repo.appending(path: file.relativePath)
            let before = try Data(contentsOf: url)
            let after = try DataFileEditor.apply(patch.ops.filter { $0.op.file == file }, file: file, to: before)
            newContents.append((file.relativePath, before, after))
        }
        let junctionsChanged = patch.files.contains(.junctions)
        var backedUp: [(path: String, before: Data, after: Data?)] = newContents.map { ($0.0, $0.1, $0.2) }
        if junctionsChanged {
            backedUp.append((Self.topologyFile, try Data(contentsOf: repo.appending(path: Self.topologyFile)), nil))
        }

        let directory = try makeReceiptDirectory()
        for file in backedUp {
            let backup = directory.appending(path: "files").appending(path: file.path)
            try fm.createDirectory(at: backup.deletingLastPathComponent(), withIntermediateDirectories: true)
            try file.before.write(to: backup)
        }
        try patch.encoded().write(to: directory.appending(path: "patch.json"))
        try patch.inverse.encoded().write(to: directory.appending(path: "inverse.json"))

        var receipt = WriteReceipt(
            format: WriteReceipt.format, patchID: patch.id, createdAt: ISO8601DateFormatter().string(from: Date()),
            directory: directory.path,
            files: backedUp.map { .init(relativePath: $0.path, backup: "files/\($0.path)", sha256Before: Self.sha256($0.before),
                                        sha256After: $0.after.map(Self.sha256)) },
            topologyRegenerated: false, guards: [], status: .pending, undoGuards: nil)
        try save(receipt)

        var failed = false
        do {
            for (path, _, after) in newContents {
                try after.write(to: repo.appending(path: path), options: .atomic)
                try afterFileWrite?(path)
            }
            if junctionsChanged {
                let rebuild = guards.evaluate(GuardCommand(guardClass: nil, shell: GuardRunner.topologyRegenerate, isSwiftTest: false), repo: repo)
                receipt.guards.append(rebuild)
                receipt.topologyRegenerated = rebuild.passed
                failed = !rebuild.passed
                if let i = receipt.files.firstIndex(where: { $0.relativePath == Self.topologyFile }) {
                    receipt.files[i].sha256After = Self.sha256(try Data(contentsOf: repo.appending(path: Self.topologyFile)))
                }
            }
            if !failed {
                let outcomes = guards.run(guardClasses(patch), repo: repo)
                receipt.guards += outcomes
                failed = outcomes.contains { !$0.passed }
            }
        } catch {
            try restore(receipt, from: directory)
            receipt.status = .reverted
            try save(receipt)
            throw error
        }
        if failed { try restore(receipt, from: directory) }
        receipt.status = failed ? .reverted : .written
        try save(receipt)
        return receipt
    }

    /// Restores the files of a `.written` or `.pending` (interrupted) receipt
    /// from its backups, then re-runs the patch's guards. A file holding its
    /// written bytes is restored; one already holding its original bytes is
    /// left alone; one matching neither is refused before anything changes.
    public func undo(receiptAt url: URL, confirm: Bool) throws -> WriteReceipt {
        guard confirm else { throw AreaRepairError.confirmationRequired }
        var receipt = try JSONDecoder().decode(WriteReceipt.self, from: Data(contentsOf: url))
        guard receipt.status == .written || receipt.status == .pending else {
            throw AreaRepairError.refused("receipt \(receipt.patchID) is \(receipt.status.rawValue), not written or pending.")
        }
        var restoring: [WriteReceipt.FileRecord] = []
        for file in receipt.files {
            let current = Self.sha256(try Data(contentsOf: repo.appending(path: file.relativePath)))
            if current == file.sha256Before { continue }
            guard file.sha256After == nil || current == file.sha256After else { throw AreaRepairError.changedSinceWrite(file.relativePath) }
            restoring.append(file)
        }
        let directory = url.deletingLastPathComponent()
        var selected = receipt
        selected.files = restoring
        try restore(selected, from: directory)
        let patch = try AreaPatch.decode(Data(contentsOf: directory.appending(path: "patch.json")))
        receipt.undoGuards = guards.run(guardClasses(patch), repo: repo)
        receipt.status = .undone
        try save(receipt)
        return receipt
    }

    func guardClasses(_ patch: AreaPatch) -> [GuardClass] {
        var classes = patch.guards
        for implied in AreaPatch.guards(for: patch.ops) where !classes.contains(implied) { classes.append(implied) }
        return classes
    }

    func restore(_ receipt: WriteReceipt, from directory: URL) throws {
        for file in receipt.files {
            let backup = try Data(contentsOf: directory.appending(path: file.backup))
            try backup.write(to: repo.appending(path: file.relativePath), options: .atomic)
        }
    }

    func makeReceiptDirectory() throws -> URL {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.dateFormat = "yyyyMMdd'T'HHmmss.SSS'Z'"
        var directory = patchDirectory.appending(path: "receipts").appending(path: formatter.string(from: Date()))
        var suffix = 1
        while FileManager.default.fileExists(atPath: directory.path) {
            directory = directory.deletingLastPathComponent().appending(path: formatter.string(from: Date()) + "-\(suffix)")
            suffix += 1
        }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    func save(_ receipt: WriteReceipt) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        try encoder.encode(receipt).write(to: receipt.receiptURL, options: .atomic)
    }

    public static func sha256(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}
