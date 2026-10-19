import Foundation
import Observation

/// Owns one AI request's lifetime. Cancellation keeps the request busy until
/// its suspended work exits, so a second request cannot overlap its cleanup.
/// Authentication, candidate validation and accepting a draft keep their own
/// owners; this object never publishes a candidate or writes a journey.
@MainActor
@Observable
final class JourneyCompletionRequest {
    private(set) var isWorking = false
    @ObservationIgnored private var operation: Task<Void, Never>?

    @discardableResult
    func start(
        _ action: @escaping @MainActor () async throws -> Void,
        onFailure: @escaping @MainActor (String) -> Void
    ) -> Bool {
        guard !isWorking else { return false }
        isWorking = true
        operation = Task { @MainActor in
            defer { isWorking = false; operation = nil }
            do { try await action() }
            catch is CancellationError { }
            catch {
                if !Task.isCancelled { onFailure(error.localizedDescription) }
            }
        }
        return true
    }

    func cancel() { operation?.cancel() }
}
