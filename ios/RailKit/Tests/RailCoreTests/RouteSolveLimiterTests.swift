import Testing
@testable import RailCore

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
        private var observers: [(Int, CheckedContinuation<Void, Never>)] = []

        func enter(_ id: Int) {
            started.append(id)
            active += 1
            peak = max(peak, active)
            let ready = observers.filter { started.count >= $0.0 }
            observers.removeAll { started.count >= $0.0 }
            for (_, continuation) in ready { continuation.resume() }
        }

        func leave() { active -= 1 }

        func waitForStarts(_ count: Int) async {
            if started.count >= count { return }
            await withCheckedContinuation { observers.append((count, $0)) }
        }
    }

    private func waitForQueue(_ count: Int, in limiter: RouteSolveLimiter) async {
        while await limiter.queuedPermitCount != count { await Task.yield() }
    }

    @Test("Saturated work transfers permits in FIFO order and never exceeds the limit")
    func saturationAndFIFO() async throws {
        let limiter = RouteSolveLimiter(limit: 2)
        let probe = Probe()
        let gates = (0..<6).map { _ in Gate() }
        var jobs: [Task<Int, any Error>] = []
        for id in 0..<6 {
            jobs.append(Task {
                try await limiter.withPermit {
                    await probe.enter(id)
                    await gates[id].wait()
                    await probe.leave()
                    return id
                }
            })
            if id < 2 {
                await probe.waitForStarts(id + 1)
            } else {
                await waitForQueue(id - 1, in: limiter)
            }
        }
        #expect(await probe.started == [0, 1])
        for id in 0..<4 {
            await gates[id].open()
            await probe.waitForStarts(id + 3)
            #expect(await probe.started == Array(0...(id + 2)))
        }
        await gates[4].open()
        await gates[5].open()
        for (id, job) in jobs.enumerated() { #expect(try await job.value == id) }
        #expect(await probe.peak == 2)
        #expect(await probe.active == 0)
        #expect(await limiter.queuedPermitCount == 0)
    }

    private enum ExpectedFailure: Error { case operation }

    @Test("An operation failure releases its permit to the next queued operation")
    func failureReleasesPermit() async throws {
        let limiter = RouteSolveLimiter(limit: 1)
        let probe = Probe()
        let gate = Gate()
        let first = Task {
            try await limiter.withPermit {
                await probe.enter(0)
                await gate.wait()
                await probe.leave()
                throw ExpectedFailure.operation
            }
        }
        await probe.waitForStarts(1)
        let next = Task { try await limiter.withPermit { 42 } }
        await waitForQueue(1, in: limiter)
        await gate.open()
        do {
            _ = try await first.value
            Issue.record("Expected the operation error")
        } catch ExpectedFailure.operation {
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
        #expect(try await next.value == 42)
        #expect(try await limiter.withPermit { 43 } == 43)
    }

    @Test("Cancelled queued work exits before the occupied permit is released and never starts")
    func queuedCancellation() async throws {
        let limiter = RouteSolveLimiter(limit: 1)
        let probe = Probe()
        let gate = Gate()
        let running = Task {
            try await limiter.withPermit {
                await probe.enter(0)
                await gate.wait()
                await probe.leave()
            }
        }
        await probe.waitForStarts(1)
        let cancelled = Task {
            try await limiter.withPermit { await probe.enter(1) }
        }
        await waitForQueue(1, in: limiter)
        cancelled.cancel()
        do {
            try await cancelled.value
            Issue.record("Expected cancellation")
        } catch is CancellationError {
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
        #expect(await limiter.queuedPermitCount == 0)
        #expect(await probe.started == [0])
        #expect(await probe.active == 1)
        let next = Task { try await limiter.withPermit { 7 } }
        await waitForQueue(1, in: limiter)
        await gate.open()
        try await running.value
        #expect(try await next.value == 7)
    }

    @Test("Cancelling running work retains its permit until the operation actually exits")
    func runningCancellationDoesNotReleaseEarly() async throws {
        let limiter = RouteSolveLimiter(limit: 1)
        let probe = Probe()
        let gate = Gate()
        let running = Task {
            try await limiter.withPermit {
                await probe.enter(0)
                await gate.wait() // Deliberately ignores cancellation until explicitly released.
                await probe.leave()
                try Task.checkCancellation()
            }
        }
        await probe.waitForStarts(1)
        running.cancel()
        let next = Task {
            try await limiter.withPermit {
                await probe.enter(1)
                await probe.leave()
                return 9
            }
        }
        await waitForQueue(1, in: limiter)
        #expect(await probe.started == [0])
        #expect(await probe.active == 1)
        await gate.open()
        do {
            try await running.value
            Issue.record("Expected cancellation")
        } catch is CancellationError {
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
        #expect(try await next.value == 9)
        #expect(await probe.peak == 1)
        #expect(await probe.active == 0)
    }
}
