import Foundation
import Observation

/// Identifies one share operation across suspended image work and deferred
/// presentation. The view's structured task owns cancellation; this owner
/// prevents an older completion from clearing or presenting a newer request.
@MainActor
@Observable
final class ShareRequestController<Input: Equatable> {
    struct Request: Equatable {
        let id: UInt64
        let input: Input
    }

    private(set) var request: Request?
    @ObservationIgnored private var generation: UInt64 = 0

    func begin(_ input: Input) {
        guard request == nil else { return }
        generation &+= 1
        request = Request(id: generation, input: input)
    }

    func cancel() {
        generation &+= 1
        request = nil
    }

    func isLatest(_ ticket: Request) -> Bool { generation == ticket.id }

    func perform<Output>(
        _ ticket: Request,
        isCurrent: @MainActor () -> Bool,
        operation: @MainActor () async -> Output?
    ) async -> Output? {
        guard request == ticket else { return nil }
        defer { if request == ticket { request = nil } }
        guard isCurrent(), !Task.isCancelled else { return nil }
        let output = await operation()
        guard isLatest(ticket), isCurrent(), !Task.isCancelled else { return nil }
        return output
    }
}
