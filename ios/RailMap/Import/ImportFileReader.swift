import Foundation

enum ImportFileReaderError: Error, LocalizedError {
    /// A file larger than ``ImportFileReader/maxFileSize`` was offered for
    /// import. Rejected before the read rather than after: an unbounded
    /// `Data(contentsOf:)` on an adversarial or merely huge file would hold
    /// the whole thing in memory first.
    case fileTooLarge(size: Int64, limit: Int64)

    var errorDescription: String? {
        switch self {
        case .fileTooLarge(let size, let limit):
            return "File is too large to import (\(size) bytes; the limit is \(limit) bytes)."
        }
    }
}

enum ImportFileReader {
    /// The largest file this reader will load into memory.
    static let maxFileSize: Int64 = 64 * 1024 * 1024

    /// The security-scoped grant covers the complete read, including file
    /// provider materialization. None of that work runs on the UI actor.
    static func read(_ url: URL) async throws -> Data {
        let worker = Task.detached(priority: .userInitiated) {
            try Task.checkCancellation()
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            if let size = try? FileManager.default.attributesOfItem(atPath: url.path)[.size]
                as? Int64,
                size > maxFileSize
            {
                throw ImportFileReaderError.fileTooLarge(size: size, limit: maxFileSize)
            }
            let data = try Data(contentsOf: url)
            try Task.checkCancellation()
            return data
        }
        return try await withTaskCancellationHandler {
            try await worker.value
        } onCancel: { worker.cancel() }
    }
}
