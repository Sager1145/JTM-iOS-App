import Foundation
import Testing
@testable import RailCore

struct RouteTestObservationTimeout: Error {}

/// A ceiling, not a schedule. Every observation is woken by the event it waits
/// for, so scheduler load only delays it; this bound exists solely so that a lost
/// wakeup fails the test instead of hanging the run.
private let routeTestObservationCeiling: Duration = .seconds(120)

/// Runs an event-driven, cancellable wait; only the ceiling can end it otherwise.
func waitForRouteTestObservation(
    _ description: String, _ wait: @escaping @Sendable () async throws -> Void
) async throws {
    let observed = try await withThrowingTaskGroup(of: Bool.self) { group in
        group.addTask { try await wait(); return true }
        group.addTask { try await Task.sleep(for: routeTestObservationCeiling); return false }
        defer { group.cancelAll() }
        return try await group.next() ?? false
    }
    guard observed else {
        Issue.record("No \(description) within \(routeTestObservationCeiling)")
        throw RouteTestObservationTimeout()
    }
}

/// Test-owned state whose waiters are resumed by the update that satisfies them.
actor RouteTestState<State: Sendable> {
    private(set) var value: State
    private var waiters = StateWaiters<State>()

    init(_ value: State) { self.value = value }

    func update(_ change: @Sendable (inout State) -> Void) {
        change(&value)
        waiters.publish(value)
    }

    func wait(until condition: @escaping @Sendable (State) -> Bool) async throws {
        let id = UUID()
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                waiters.add(id, current: value, condition: condition, continuation: continuation)
            }
        } onCancel: {
            Task { await self.cancelWaiter(id) }
        }
    }

    private func cancelWaiter(_ id: UUID) { waiters.cancel(id) }
}

/// The operation publishes its own result; waiting suspends only on that
/// test-owned state, never on a potentially lost production continuation.
struct ControlledRouteTestTask<Value: Sendable>: Sendable {
    fileprivate let task: Task<Void, Never>
    fileprivate let completion: RouteTestState<Result<Value, any Error>?>

    func cancel() { task.cancel() }

    var value: Value {
        get async throws {
            try await waitForRouteTestObservation("controlled task completion") {
                try await completion.wait { $0 != nil }
            }
            let result = try #require(await completion.value)
            return try result.get()
        }
    }
}

/// Every exit cancels launched work and opens all gates, including gates that
/// deliberately ignore cancellation to test production permit ownership.
actor ControlledRouteTestWork {
    private var cancellations: [@Sendable () -> Void] = []
    private var completions: [@Sendable () async throws -> Void] = []
    private var releases: [@Sendable () async -> Void] = []

    func releaseOnExit(_ action: @escaping @Sendable () async -> Void) {
        releases.append(action)
    }

    func start<Value: Sendable>(
        _ operation: @escaping @Sendable () async throws -> Value
    ) -> ControlledRouteTestTask<Value> {
        let completion = RouteTestState<Result<Value, any Error>?>(nil)
        let task = Task {
            let result: Result<Value, any Error>
            do { result = .success(try await operation()) }
            catch { result = .failure(error) }
            await completion.update { $0 = result }
        }
        cancellations.append { task.cancel() }
        completions.append { try await completion.wait { $0 != nil } }
        return ControlledRouteTestTask(task: task, completion: completion)
    }

    func run<Value: Sendable>(
        _ operation: @escaping @Sendable () async throws -> Value
    ) async throws -> Value {
        try await start(operation).value
    }

    func finish() async {
        for cancel in cancellations { cancel() }
        for release in releases { await release() }
        // Cleanup is bounded by the same ceiling. A lost production continuation
        // fails this observation, but cannot keep a structured task group alive.
        let pending = completions
        try? await waitForRouteTestObservation("controlled route jobs finishing after cancellation and gate release") {
            for completed in pending { try await completed() }
        }
        cancellations.removeAll()
        completions.removeAll()
        releases.removeAll()
    }
}

struct RouteSolveLimiterTests {
    private actor Gate {
        private var isOpen = false
        private var waiters: [CheckedContinuation<Void, Never>] = []

        func wait() async {
            if isOpen { return }
            await withCheckedContinuation { waiters.append($0) }
        }

        func open() {
            isOpen = true
            let pending = waiters
            waiters.removeAll()
            for waiter in pending { waiter.resume() }
        }
    }

    private struct ProbeState: Sendable {
        var started: [Int] = []
        var active = 0
        var peak = 0
    }

    private struct Probe: Sendable {
        private let state = RouteTestState(ProbeState())

        var started: [Int] { get async { await state.value.started } }
        var active: Int { get async { await state.value.active } }
        var peak: Int { get async { await state.value.peak } }

        func enter(_ id: Int) async {
            await state.update {
                $0.started.append(id)
                $0.active += 1
                $0.peak = max($0.peak, $0.active)
            }
        }

        func leave() async { await state.update { $0.active -= 1 } }

        func waitForStarts(_ count: Int) async throws {
            try await waitForRouteTestObservation("operation starts >= \(count)") {
                try await state.wait { $0.started.count >= count }
            }
        }
    }

    private func waitForQueue(_ count: Int, in limiter: RouteSolveLimiter) async throws {
        try await waitForRouteTestObservation("queued permits == \(count)") {
            try await limiter.waitForQueuedPermits(count)
        }
    }

    @Test("Saturated work transfers permits in FIFO order and never exceeds the limit")
    func saturationAndFIFO() async throws {
        let control = ControlledRouteTestWork()
        do {
            let limiter = RouteSolveLimiter(limit: 2)
            let probe = Probe()
            let gates = (0..<6).map { _ in Gate() }
            await control.releaseOnExit { for gate in gates { await gate.open() } }
            var jobs: [ControlledRouteTestTask<Int>] = []
            for id in 0..<6 {
                jobs.append(await control.start {
                    try await limiter.withPermit {
                        await probe.enter(id)
                        await gates[id].wait()
                        await probe.leave()
                        return id
                    }
                })
                if id < 2 {
                    try await probe.waitForStarts(id + 1)
                } else {
                    try await waitForQueue(id - 1, in: limiter)
                }
            }
            #expect(await probe.started == [0, 1])
            for id in 0..<4 {
                await gates[id].open()
                try await probe.waitForStarts(id + 3)
                #expect(await probe.started == Array(0...(id + 2)))
            }
            await gates[4].open()
            await gates[5].open()
            for (id, job) in jobs.enumerated() { #expect(try await job.value == id) }
            #expect(await probe.peak == 2)
            #expect(await probe.active == 0)
            #expect(await limiter.queuedPermitCount == 0)
            await control.finish()
        } catch {
            await control.finish()
            throw error
        }
    }

    private enum ExpectedFailure: Error { case operation }

    @Test("An operation failure releases its permit to the next queued operation")
    func failureReleasesPermit() async throws {
        let control = ControlledRouteTestWork()
        do {
            let limiter = RouteSolveLimiter(limit: 1)
            let probe = Probe()
            let gate = Gate()
            await control.releaseOnExit { await gate.open() }
            let first = await control.start {
                try await limiter.withPermit {
                    await probe.enter(0)
                    await gate.wait()
                    await probe.leave()
                    throw ExpectedFailure.operation
                }
            }
            try await probe.waitForStarts(1)
            let next = await control.start { try await limiter.withPermit { 42 } }
            try await waitForQueue(1, in: limiter)
            await gate.open()
            do {
                _ = try await first.value
                Issue.record("Expected the operation error")
            } catch ExpectedFailure.operation {
            } catch is RouteTestObservationTimeout {
                throw RouteTestObservationTimeout()
            } catch {
                Issue.record("Unexpected error: \(error)")
            }
            #expect(try await next.value == 42)
            #expect(try await control.run { try await limiter.withPermit { 43 } } == 43)
            await control.finish()
        } catch {
            await control.finish()
            throw error
        }
    }

    @Test("Cancelled queued work exits before the occupied permit is released and never starts")
    func queuedCancellation() async throws {
        let control = ControlledRouteTestWork()
        do {
            let limiter = RouteSolveLimiter(limit: 1)
            let probe = Probe()
            let gate = Gate()
            await control.releaseOnExit { await gate.open() }
            let running = await control.start {
                try await limiter.withPermit {
                    await probe.enter(0)
                    await gate.wait()
                    await probe.leave()
                }
            }
            try await probe.waitForStarts(1)
            let cancelled = await control.start {
                try await limiter.withPermit { await probe.enter(1) }
            }
            try await waitForQueue(1, in: limiter)
            cancelled.cancel()
            do {
                try await cancelled.value
                Issue.record("Expected cancellation")
            } catch is CancellationError {
            } catch is RouteTestObservationTimeout {
                throw RouteTestObservationTimeout()
            } catch {
                Issue.record("Unexpected error: \(error)")
            }
            #expect(await limiter.queuedPermitCount == 0)
            #expect(await probe.started == [0])
            #expect(await probe.active == 1)
            let next = await control.start { try await limiter.withPermit { 7 } }
            try await waitForQueue(1, in: limiter)
            await gate.open()
            try await running.value
            #expect(try await next.value == 7)
            await control.finish()
        } catch {
            await control.finish()
            throw error
        }
    }

    @Test("Cancelling running work retains its permit until the operation actually exits")
    func runningCancellationDoesNotReleaseEarly() async throws {
        let control = ControlledRouteTestWork()
        do {
            let limiter = RouteSolveLimiter(limit: 1)
            let probe = Probe()
            let gate = Gate()
            await control.releaseOnExit { await gate.open() }
            let running = await control.start {
                try await limiter.withPermit {
                    await probe.enter(0)
                    await gate.wait() // Deliberately ignores cancellation until explicitly released.
                    await probe.leave()
                    try Task.checkCancellation()
                }
            }
            try await probe.waitForStarts(1)
            running.cancel()
            let next = await control.start {
                try await limiter.withPermit {
                    await probe.enter(1)
                    await probe.leave()
                    return 9
                }
            }
            try await waitForQueue(1, in: limiter)
            #expect(await probe.started == [0])
            #expect(await probe.active == 1)
            await gate.open()
            do {
                try await running.value
                Issue.record("Expected cancellation")
            } catch is CancellationError {
            } catch is RouteTestObservationTimeout {
                throw RouteTestObservationTimeout()
            } catch {
                Issue.record("Unexpected error: \(error)")
            }
            #expect(try await next.value == 9)
            #expect(await probe.peak == 1)
            #expect(await probe.active == 0)
            await control.finish()
        } catch {
            await control.finish()
            throw error
        }
    }
}
