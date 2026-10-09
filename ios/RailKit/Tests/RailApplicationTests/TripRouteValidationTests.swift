import RailApplication
import RailCore
import Testing

struct TripRouteValidationTests {
    private static func train(id: String = "trip", date: String? = "2026-10-08") -> Train {
        Train(id: id, date: date, number: "Local", origin: "A", destination: "B",
              stops: [Stop(name: "A"), Stop(name: "B")])
    }

    @Test func oneOrderedBatchMapsProofAndClosureAcrossMissingDrafts() async throws {
        let first = Self.train(id: "first")
        let closed = Self.train(id: "closed", date: "2020-01-01")
        let unproven = Self.train(id: "unproven", date: nil)
        let resolver = Resolver([
            .init(datedResolved: true, undatedResolved: true),
            .init(datedResolved: false, undatedResolved: true),
            .init(datedResolved: false, undatedResolved: false),
        ])
        let result = try await TripRouteValidation.validate(
            candidates: [.init(id: "first", train: first), .init(id: "missing", train: nil),
                         .init(id: "closed", train: closed), .init(id: "unproven", train: unproven)],
            resolve: { try await resolver.resolve($0) })
        #expect(result.retainedIDs == ["first", "missing", "unproven"])
        #expect(result.physicallyResolvedIDs == ["first"])
        let calls = await resolver.calls
        #expect(calls.count == 1)
        #expect(calls.first?.map(\.id) == ["first", "closed", "unproven"])
        #expect(calls.first?.map(\.date) == ["2026-10-08", "2020-01-01", nil])
    }

    @Test func datedProofDoesNotRequireUndatedProof() async throws {
        let result = try await TripRouteValidation.validate(
            candidates: [.init(id: "dated", train: Self.train())],
            resolve: { _ in [.init(datedResolved: true, undatedResolved: false)] })
        #expect(result.retainedIDs == ["dated"])
        #expect(result.physicallyResolvedIDs == ["dated"])
    }

    @Test func pendingInputIsConfirmedOnlyInResolverSnapshot() async throws {
        var original = Self.train()
        original.routeConfirmation = .pending
        let candidate = TripRouteValidation.Candidate(id: "corridor", train: original)
        let resolver = Resolver([.init(datedResolved: true, undatedResolved: true)])
        _ = try await TripRouteValidation.validate(
            candidates: [candidate], resolve: { try await resolver.resolve($0) })
        var expected = original
        expected.routeConfirmation = .confirmed
        #expect(await resolver.calls == [[expected]])
        #expect(candidate.train == original)
        #expect(original.routeConfirmation == .pending)
    }

    @Test(arguments: [false, true])
    func noDraftsAvoidResolver(empty: Bool) async throws {
        let resolver = Resolver([])
        let result = try await TripRouteValidation.validate(
            candidates: empty ? [] : [.init(id: "missing", train: nil)],
            resolve: { try await resolver.resolve($0) })
        #expect(result.retainedIDs == (empty ? [] : ["missing"]))
        #expect(result.physicallyResolvedIDs.isEmpty)
        #expect(await resolver.calls.isEmpty)
    }

    @Test(arguments: [0, 1, 3])
    func wrongBatchCountPreservesEntireSnapshot(count: Int) async throws {
        let replies = Array(repeating: TripRouteValidation.Availability(
            datedResolved: true, undatedResolved: true), count: count)
        let result = try await TripRouteValidation.validate(
            candidates: [.init(id: "one", train: Self.train()), .init(id: "missing", train: nil),
                         .init(id: "two", train: Self.train(id: "second"))],
            resolve: { _ in replies })
        #expect(result.retainedIDs == ["one", "missing", "two"])
        #expect(result.physicallyResolvedIDs.isEmpty)
    }

    @Test func ordinaryFailurePreservesEntireSnapshot() async throws {
        let result = try await TripRouteValidation.validate(
            candidates: [.init(id: "one", train: Self.train()), .init(id: "missing", train: nil)],
            resolve: { _ in throw Resolver.Failure.unavailable })
        #expect(result.retainedIDs == ["one", "missing"])
        #expect(result.physicallyResolvedIDs.isEmpty)
    }

    @Test func resolverCancellationIsRethrown() async throws {
        do {
            _ = try await TripRouteValidation.validate(
                candidates: [.init(id: "one", train: Self.train())],
                resolve: { _ in throw CancellationError() })
            Issue.record("Validation accepted resolver cancellation")
        } catch is CancellationError {}
    }

    @Test func cancellationBeforeValidationAvoidsResolver() async throws {
        let gate = ResolverGate()
        let resolver = Resolver([.init(datedResolved: true, undatedResolved: true)])
        let task = Task {
            await gate.suspend()
            return try await TripRouteValidation.validate(
                candidates: [.init(id: "one", train: Self.train())],
                resolve: { try await resolver.resolve($0) })
        }
        await gate.waitUntilSuspended()
        task.cancel()
        await gate.release()
        do {
            _ = try await task.value
            Issue.record("Validation accepted prior cancellation")
        } catch is CancellationError {}
        #expect(await resolver.calls.isEmpty)
    }

    @Test(arguments: [false, true])
    func cancellationRejectsIgnoringResolverResultOrError(throwsOrdinaryError: Bool) async throws {
        let gate = ResolverGate()
        let task = Task {
            try await TripRouteValidation.validate(
                candidates: [.init(id: "one", train: Self.train())],
                resolve: { _ in
                    await gate.suspend()
                    if throwsOrdinaryError { throw Resolver.Failure.unavailable }
                    return [.init(datedResolved: true, undatedResolved: true)]
                })
        }
        await gate.waitUntilSuspended()
        task.cancel()
        await gate.release()
        do {
            _ = try await task.value
            Issue.record("Validation accepted a resolver finishing after cancellation")
        } catch is CancellationError {}
    }
}

private actor Resolver {
    enum Failure: Error { case unavailable }
    private let replies: [TripRouteValidation.Availability]
    private(set) var calls: [[Train]] = []

    init(_ replies: [TripRouteValidation.Availability]) { self.replies = replies }

    func resolve(_ trains: [Train]) throws -> [TripRouteValidation.Availability] {
        calls.append(trains)
        return replies
    }
}

private actor ResolverGate {
    private var suspended = false
    private var continuation: CheckedContinuation<Void, Never>?
    private var observer: CheckedContinuation<Void, Never>?

    func suspend() async {
        await withCheckedContinuation { continuation in
            self.continuation = continuation
            suspended = true
            observer?.resume()
            observer = nil
        }
    }

    func waitUntilSuspended() async {
        guard !suspended else { return }
        await withCheckedContinuation { observer = $0 }
    }

    func release() {
        continuation?.resume()
        continuation = nil
    }
}
