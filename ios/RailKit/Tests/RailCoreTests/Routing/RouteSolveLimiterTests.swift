import Testing
@testable import RailCore

struct RouteTestObservationTimeout: Error {}

/// Observe actor state without leaving a suspended observer continuation behind.
func waitForRouteTestObservation(
    _ description: String, condition: @Sendable () async -> Bool
) async throws {
    let clock = ContinuousClock()
    let deadline = clock.now.advanced(by: .seconds(5))
    while !(await condition()) {
        try Task.checkCancellation()
        guard clock.now < deadline else {
            Issue.record("Timed out observing \(description)")
            throw RouteTestObservationTimeout()
        }
        await Task.yield()
    }
}

fileprivate actor RouteTestCompletion<Value: Sendable> {
    var result: Result<Value, any Error>?
    func finish(_ value: Result<Value, any Error>) { result = value }
}

/// The operation publishes its own result; waiting never creates another task
/// suspended on a potentially lost production continuation.
struct ControlledRouteTestTask<Value: Sendable>: Sendable {
    fileprivate let task: Task<Void, Never>
    fileprivate let completion: RouteTestCompletion<Value>

    func cancel() { task.cancel() }

    var value: Value {
        get async throws {
            try await waitForRouteTestObservation("controlled task completion") {
                await completion.result != nil
            }
            let result = try #require(await completion.result)
            return try result.get()
        }
    }
}

/// Every exit cancels launched work and opens all gates, including gates that
/// deliberately ignore cancellation to test production permit ownership.
actor ControlledRouteTestWork {
    private var cancellations: [@Sendable () -> Void] = []
    private var completions: [@Sendable () async -> Bool] = []
    private var releases: [@Sendable () async -> Void] = []

    func releaseOnExit(_ action: @escaping @Sendable () async -> Void) {
        releases.append(action)
    }

    func start<Value: Sendable>(
        _ operation: @escaping @Sendable () async throws -> Value
    ) -> ControlledRouteTestTask<Value> {
        let completion = RouteTestCompletion<Value>()
        let task = Task {
            let result: Result<Value, any Error>
            do { result = .success(try await operation()) }
            catch { result = .failure(error) }
            await completion.finish(result)
        }
        cancellations.append { task.cancel() }
        completions.append { await completion.result != nil }
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
        // Cleanup also has a deadline. A lost production continuation can fail
        // this observation, but cannot keep a structured task group alive.
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: .seconds(5))
        while true {
            var finished = true
            for completed in completions where !(await completed()) { finished = false }
            if finished { break }
            guard clock.now < deadline else {
                Issue.record("Controlled route jobs did not finish after cancellation and gate release")
                break
            }
            await Task.yield()
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

    private actor Probe {
        private(set) var started: [Int] = []
        private(set) var active = 0
        private(set) var peak = 0

        func enter(_ id: Int) {
            started.append(id)
            active += 1
            peak = max(peak, active)
        }

        func leave() { active -= 1 }

        func waitForStarts(_ count: Int) async throws {
            try await waitForRouteTestObservation("operation starts >= \(count)") {
                await self.started.count >= count
            }
        }
    }

    private func waitForQueue(_ count: Int, in limiter: RouteSolveLimiter) async throws {
        try await waitForRouteTestObservation("queued permits == \(count)") {
            await limiter.queuedPermitCount == count
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
