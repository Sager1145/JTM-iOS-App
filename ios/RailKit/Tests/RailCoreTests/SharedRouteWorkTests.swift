import Testing
@testable import RailCore

struct SharedRouteWorkTests {
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
        private(set) var starts = 0

        func enter() {
            starts += 1
        }

        func waitForStarts(_ count: Int) async throws {
            try await waitForRouteTestObservation("operation starts >= \(count)") {
                await self.starts >= count
            }
        }
    }

    private func waitForSubscribers(_ count: Int, in work: SharedRouteWork<String, Int>) async throws {
        try await waitForRouteTestObservation("subscriberCount == \(count)") {
            await work.snapshot().subscriberCount == count
        }
    }

    private func waitForCompletions(_ count: Int, in work: SharedRouteWork<String, Int>) async throws {
        try await waitForRouteTestObservation("completedOperationCount == \(count)") {
            await work.snapshot().completedOperationCount == count
        }
    }

    private func expectCancellation(_ task: ControlledRouteTestTask<Int>) async throws {
        do {
            _ = try await task.value
            Issue.record("Expected cancellation")
        } catch is CancellationError {
        } catch is RouteTestObservationTimeout {
            throw RouteTestObservationTimeout()
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }

    @Test("Equal cold requests share one operation and subsequent requests hit the cache")
    func sharesColdWork() async throws {
        let control = ControlledRouteTestWork()
        do {
            let work = SharedRouteWork<String, Int>(maxEntries: 2, maxCost: 2)
            let probe = Probe()
            let gate = Gate()
            await control.releaseOnExit { await gate.open() }
            let first = await control.start {
                try await work.value(for: "route") {
                    await probe.enter()
                    await gate.wait()
                    return 42
                }
            }
            try await probe.waitForStarts(1)
            let second = await control.start { try await work.value(for: "route") { await probe.enter(); return 99 } }
            try await waitForSubscribers(2, in: work)
            #expect(await probe.starts == 1)
            await gate.open()
            #expect(try await first.value == 42)
            #expect(try await second.value == 42)
            #expect(try await control.run { try await work.value(for: "route") { 99 } } == 42)
            let snapshot = await work.snapshot()
            #expect(snapshot.startedOperationCount == 1)
            #expect(snapshot.joinedRequestCount == 1)
            #expect(snapshot.cacheHitCount == 1)
            #expect(snapshot.cachedEntryCount == 1)
            #expect(snapshot.inFlightCount == 0)
            await control.finish()
        } catch {
            await control.finish()
            throw error
        }
    }

    @Test("One subscriber cancels promptly while the other receives the shared result")
    func independentCancellation() async throws {
        let control = ControlledRouteTestWork()
        do {
            let work = SharedRouteWork<String, Int>(maxEntries: 2, maxCost: 2)
            let probe = Probe()
            let gate = Gate()
            await control.releaseOnExit { await gate.open() }
            let cancelled = await control.start {
                try await work.value(for: "route") {
                    await probe.enter()
                    await gate.wait()
                    try Task.checkCancellation()
                    return 7
                }
            }
            try await probe.waitForStarts(1)
            let surviving = await control.start { try await work.value(for: "route") { 99 } }
            try await waitForSubscribers(2, in: work)
            cancelled.cancel()
            try await expectCancellation(cancelled) // Gate remains closed, proving prompt detachment.
            #expect(await work.snapshot().subscriberCount == 1)
            await gate.open()
            #expect(try await surviving.value == 7)
            #expect(await work.snapshot().cachedEntryCount == 1)
            #expect(await probe.starts == 1)
            await control.finish()
        } catch {
            await control.finish()
            throw error
        }
    }

    @Test("Last cancellation allows a fresh retry and an old completion cannot remove it")
    func retryWhileCancelledProducerWindsDown() async throws {
        let control = ControlledRouteTestWork()
        do {
            let work = SharedRouteWork<String, Int>(maxEntries: 2, maxCost: 2)
            let probe = Probe()
            let oldGate = Gate()
            await control.releaseOnExit { await oldGate.open() }
            let newGate = Gate()
            await control.releaseOnExit { await newGate.open() }
            let old = await control.start {
                try await work.value(for: "route") {
                    await probe.enter()
                    await oldGate.wait() // Deliberately does not cooperate with cancellation.
                    return 1
                }
            }
            try await probe.waitForStarts(1)
            old.cancel()
            try await expectCancellation(old)
            #expect(await work.snapshot().inFlightCount == 0)
            let replacement = await control.start {
                try await work.value(for: "route") {
                    await probe.enter()
                    await newGate.wait()
                    return 2
                }
            }
            try await probe.waitForStarts(2)
            await oldGate.open()
            try await waitForCompletions(1, in: work)
            #expect(await work.snapshot().inFlightCount == 1)
            #expect(await work.snapshot().cachedEntryCount == 0)
            let joining = await control.start { try await work.value(for: "route") { 99 } }
            try await waitForSubscribers(2, in: work)
            await newGate.open()
            #expect(try await replacement.value == 2)
            #expect(try await joining.value == 2)
            #expect(await work.snapshot().startedOperationCount == 2)
            #expect(try await control.run { try await work.value(for: "route") { 99 } } == 2)
            await control.finish()
        } catch {
            await control.finish()
            throw error
        }
    }

    private enum ExpectedFailure: Error { case operation }

    @Test("Errors are delivered to every subscriber and never retained")
    func failureAllowsRetry() async throws {
        let control = ControlledRouteTestWork()
        do {
            let work = SharedRouteWork<String, Int>(maxEntries: 2, maxCost: 2)
            let probe = Probe()
            let gate = Gate()
            await control.releaseOnExit { await gate.open() }
            let first = await control.start {
                try await work.value(for: "route") {
                    await probe.enter()
                    await gate.wait()
                    throw ExpectedFailure.operation
                }
            }
            try await probe.waitForStarts(1)
            let second = await control.start { try await work.value(for: "route") { 99 } }
            try await waitForSubscribers(2, in: work)
            await gate.open()
            for task in [first, second] {
                do {
                    _ = try await task.value
                    Issue.record("Expected the operation error")
                } catch ExpectedFailure.operation {
                } catch is RouteTestObservationTimeout {
                    throw RouteTestObservationTimeout()
                } catch {
                    Issue.record("Unexpected error: \(error)")
                }
            }
            #expect(await work.snapshot().cachedEntryCount == 0)
            #expect(try await control.run { try await work.value(for: "route") { 3 } } == 3)
            #expect(await work.snapshot().startedOperationCount == 2)
            await control.finish()
        } catch {
            await control.finish()
            throw error
        }
    }

    @Test("Distinct keys run independently and explicit resource generations do not share")
    func distinctKeys() async throws {
        let control = ControlledRouteTestWork()
        do {
            let work = SharedRouteWork<String, Int>(maxEntries: 2, maxCost: 2)
            let probe = Probe()
            let gate = Gate()
            await control.releaseOnExit { await gate.open() }
            let first = await control.start {
                try await work.value(for: "route:revision1") {
                    await probe.enter()
                    await gate.wait()
                    return 1
                }
            }
            try await probe.waitForStarts(1)
            let second = await control.start {
                try await work.value(for: "route:revision2") {
                    await probe.enter()
                    await gate.wait()
                    return 2
                }
            }
            try await probe.waitForStarts(2)
            #expect(await work.snapshot().inFlightCount == 2)
            await gate.open()
            #expect(try await first.value == 1)
            #expect(try await second.value == 2)
            await control.finish()
        } catch {
            await control.finish()
            throw error
        }
    }

    @Test("Retention obeys both entry and cost limits and cache hits refresh LRU order")
    func boundedLRU() async throws {
        let control = ControlledRouteTestWork()
        do {
            let work = SharedRouteWork<String, Int>(maxEntries: 2, maxCost: 5, cost: { $0 })
            #expect(try await control.run { try await work.value(for: "a") { 2 } } == 2)
            #expect(try await control.run { try await work.value(for: "b") { 2 } } == 2)
            #expect(try await control.run { try await work.value(for: "a") { 99 } } == 2)
            #expect(try await control.run { try await work.value(for: "c") { 2 } } == 2) // Entry bound evicts b.
            #expect(try await control.run { try await work.value(for: "a") { 99 } } == 2)
            #expect(await work.snapshot().retainedCost == 4)
            #expect(try await control.run { try await work.value(for: "b") { 3 } } == 3) // Cost bound evicts c.
            #expect(await work.snapshot().retainedCost == 5)
            #expect(try await control.run { try await work.value(for: "c") { 5 } } == 5) // Cost bound evicts both a and b.
            #expect(await work.snapshot().cachedEntryCount == 1)
            #expect(await work.snapshot().retainedCost == 5)
            #expect(await work.snapshot().startedOperationCount == 5)
            await control.finish()
        } catch {
            await control.finish()
            throw error
        }
    }

    @Test("Admission can exclude negative results and values larger than the budget")
    func declinedAdmission() async throws {
        let control = ControlledRouteTestWork()
        do {
            let work = SharedRouteWork<String, Int>(maxEntries: 2, maxCost: 5, cost: { $0 > 0 ? $0 : nil })
            #expect(try await control.run { try await work.value(for: "empty") { 0 } } == 0)
            #expect(try await control.run { try await work.value(for: "empty") { 0 } } == 0)
            #expect(try await control.run { try await work.value(for: "large") { 6 } } == 6)
            #expect(try await control.run { try await work.value(for: "large") { 6 } } == 6)
            #expect(await work.snapshot().cachedEntryCount == 0)
            #expect(await work.snapshot().startedOperationCount == 4)
            await control.finish()
        } catch {
            await control.finish()
            throw error
        }
    }

    @Test("An already cancelled subscriber never starts work")
    func alreadyCancelledSubscriber() async throws {
        let control = ControlledRouteTestWork()
        do {
            let work = SharedRouteWork<String, Int>(maxEntries: 2, maxCost: 2)
            let gate = Gate()
            await control.releaseOnExit { await gate.open() }
            let pending = await control.start {
                await gate.wait()
                return try await work.value(for: "route") { 1 }
            }
            pending.cancel()
            await gate.open()
            try await expectCancellation(pending)
            #expect(await work.snapshot().startedOperationCount == 0)
            #expect(await work.snapshot().subscriberCount == 0)
            await control.finish()
        } catch {
            await control.finish()
            throw error
        }
    }

    @Test("Zero retention capacities still share concurrent requests")
    func zeroRetentionStillShares() async throws {
        let control = ControlledRouteTestWork()
        do {
            for work in [
                SharedRouteWork<String, Int>(maxEntries: 0, maxCost: 2),
                SharedRouteWork<String, Int>(maxEntries: 2, maxCost: 0),
            ] {
                let probe = Probe()
                let gate = Gate()
                await control.releaseOnExit { await gate.open() }
                let first = await control.start {
                    try await work.value(for: "route") {
                        await probe.enter()
                        await gate.wait()
                        return 1
                    }
                }
                try await probe.waitForStarts(1)
                let second = await control.start { try await work.value(for: "route") { 99 } }
                try await waitForSubscribers(2, in: work)
                await gate.open()
                #expect(try await first.value == 1)
                #expect(try await second.value == 1)
                #expect(await work.snapshot().cachedEntryCount == 0)
                #expect(try await control.run { try await work.value(for: "route") { 2 } } == 2)
                #expect(await work.snapshot().startedOperationCount == 2)
            }
            await control.finish()
        } catch {
            await control.finish()
            throw error
        }
    }

    @Test("Clear cancels subscribers and old work cannot repopulate the cleared cache")
    func clearInvalidatesWork() async throws {
        let control = ControlledRouteTestWork()
        do {
            let work = SharedRouteWork<String, Int>(maxEntries: 2, maxCost: 2)
            #expect(try await control.run { try await work.value(for: "cached") { 7 } } == 7)
            let probe = Probe()
            let gate = Gate()
            await control.releaseOnExit { await gate.open() }
            let pending = await control.start {
                try await work.value(for: "pending") {
                    await probe.enter()
                    await gate.wait()
                    return 8
                }
            }
            try await probe.waitForStarts(1)
            await work.clear()
            try await expectCancellation(pending)
            #expect(await work.snapshot().cachedEntryCount == 0)
            #expect(await work.snapshot().inFlightCount == 0)
            #expect(try await control.run { try await work.value(for: "pending") { 9 } } == 9)
            await gate.open()
            try await waitForCompletions(3, in: work)
            #expect(try await control.run { try await work.value(for: "pending") { 99 } } == 9)
            #expect(await work.snapshot().retainedCost == 1)
            await control.finish()
        } catch {
            await control.finish()
            throw error
        }
    }
}
