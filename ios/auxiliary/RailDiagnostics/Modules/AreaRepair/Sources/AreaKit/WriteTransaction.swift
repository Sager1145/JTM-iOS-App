import CryptoKit
import Foundation

/// The record of one repository write, kept beside its backups under
/// `<patchDirectory>/receipts/<timestamp>/receipt.json`.
public struct WriteReceipt: Codable, Equatable, Sendable {
    public static let format = "jtm-area-receipt-v1"
    public struct FileRecord: Codable, Equatable, Sendable {
        public var relativePath: String
        /// Backup path relative to the receipt directory.
        public var backup: String
        public var sha256Before: String
        public var sha256After: String
    }
    public enum Status: String, Codable, Sendable {
        /// Written and every guard passed.
        case written
        /// A guard or the topology rebuild failed; the backups were restored.
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

/// Writes a reviewed patch to the repository: explicit confirmation, writable
/// ops only, backups + inverse patch first, topology rebuild when junctions
/// change, regression guards, automatic revert on any failure, and undo.
public struct WriteTransaction: Sendable {
    public static let topologyFile = "app/data/physical-rail-topology.json"
    public var repo: URL
    /// Receipts go to `<patchDirectory>/receipts/<timestamp>/`.
    public var patchDirectory: URL
    public var guards: GuardRunner
    /// Allows ops on generated rail-history.json (never the package).
    public var allowGenerated: Bool

    public init(repo: URL, patchDirectory: URL, guards: GuardRunner = GuardRunner(), allowGenerated: Bool = false) {
        self.repo = repo; self.patchDirectory = patchDirectory; self.guards = guards; self.allowGenerated = allowGenerated
    }

    /// Checks the patch is writable without touching anything.
    public func check(_ patch: AreaPatch) throws {
        try patch.validate(requireProvenance: true)
        for op in patch.ops {
            switch op.op.file {
            case .package:
                throw AreaRepairError.refused("\(op.op.rawValue) \(op.key) targets generated app/public/rail/jp-2025.json; mirror it into \(op.mirror ?? "its source") in the website repository instead.")
            case .history where !allowGenerated:
                throw AreaRepairError.refused("\(op.op.rawValue) \(op.key) targets generated app/data/rail-history.json; pass --allow-generated, and mirror it into \(op.mirror ?? "its source").")
            case .junctions where !op.writable:
                throw AreaRepairError.refused("\(op.op.rawValue) \(op.key) is marked not writable.")
            default: break
            }
        }
        try JunctionRowRules.validateLineIDs(patch.ops, packageURL: repo.appending(path: DataFile.package.relativePath))
    }

    /// Writes `patch`. Returns the receipt; `status == .reverted` means a
    /// guard failed and the repository was restored byte for byte.
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
        var backedUp = newContents.map { ($0.0, $0.1) }
        if junctionsChanged {
            backedUp.append((Self.topologyFile, try Data(contentsOf: repo.appending(path: Self.topologyFile))))
        }

        let directory = try makeReceiptDirectory()
        for (path, data) in backedUp {
            let backup = directory.appending(path: "files").appending(path: path)
            try fm.createDirectory(at: backup.deletingLastPathComponent(), withIntermediateDirectories: true)
            try data.write(to: backup)
        }
        try patch.encoded().write(to: directory.appending(path: "patch.json"))
        try patch.inverse.encoded().write(to: directory.appending(path: "inverse.json"))

        var receipt = WriteReceipt(
            format: WriteReceipt.format, patchID: patch.id, createdAt: ISO8601DateFormatter().string(from: Date()),
            directory: directory.path, files: [], topologyRegenerated: false, guards: [], status: .written, undoGuards: nil)
        try save(receipt)

        for (path, _, after) in newContents { try after.write(to: repo.appending(path: path), options: .atomic) }
        var failed = false
        if junctionsChanged {
            let rebuild = guards.evaluate(GuardCommand(guardClass: nil, shell: GuardRunner.topologyRegenerate, isSwiftTest: false), repo: repo)
            receipt.guards.append(rebuild)
            receipt.topologyRegenerated = rebuild.passed
            failed = !rebuild.passed
        }
        if !failed {
            let outcomes = guards.run(guardClasses(patch), repo: repo)
            receipt.guards += outcomes
            failed = outcomes.contains { !$0.passed }
        }
        receipt.files = try backedUp.map { path, before in
            .init(relativePath: path, backup: "files/\(path)", sha256Before: Self.sha256(before),
                  sha256After: Self.sha256(try Data(contentsOf: repo.appending(path: path))))
        }
        if failed {
            try restore(receipt, from: directory)
            receipt.status = .reverted
        }
        try save(receipt)
        return receipt
    }

    /// Restores the files of a `.written` receipt from its backups (refusing
    /// if any changed since the write), then re-runs the patch's guards.
    public func undo(receiptAt url: URL, confirm: Bool) throws -> WriteReceipt {
        guard confirm else { throw AreaRepairError.confirmationRequired }
        var receipt = try JSONDecoder().decode(WriteReceipt.self, from: Data(contentsOf: url))
        guard receipt.status == .written else {
            throw AreaRepairError.refused("receipt \(receipt.patchID) is \(receipt.status.rawValue), not written.")
        }
        for file in receipt.files {
            let current = try Data(contentsOf: repo.appending(path: file.relativePath))
            guard Self.sha256(current) == file.sha256After else { throw AreaRepairError.changedSinceWrite(file.relativePath) }
        }
        let directory = url.deletingLastPathComponent()
        try restore(receipt, from: directory)
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
