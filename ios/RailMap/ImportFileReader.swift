import Foundation

enum ImportFileReader {
    /// The security-scoped grant covers the complete read, including file
    /// provider materialization. None of that work runs on the UI actor.
    static func read(_ url: URL) async throws -> Data {
        let worker = Task.detached(priority: .userInitiated) {
            try Task.checkCancellation()
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            let data = try Data(contentsOf: url)
            try Task.checkCancellation()
            return data
        }
        return try await withTaskCancellationHandler {
            try await worker.value
        } onCancel: { worker.cancel() }
    }
}
