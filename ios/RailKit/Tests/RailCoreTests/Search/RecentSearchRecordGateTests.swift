import Testing
@testable import RailCore

struct RecentSearchRecordGateTests {
    private func state(
        _ query: String = "新宿", tab: Bool = true, current: Bool = true, results: Bool = true
    ) -> RecentSearchRecordGate.State {
        .init(query: query, isSearchTab: tab, isCurrent: current, hasResults: results)
    }

    @Test func submitRecordsAtOnceWhenTheSearchIsCurrent() {
        var gate = RecentSearchRecordGate()
        do { let value = gate.submit(state()); #expect(value) }
        #expect(!gate.pending)
    }

    @Test func returnInsideTheDebounceRecordsOnceWhenTheSearchCatchesUp() {
        var gate = RecentSearchRecordGate()
        do { let value = gate.submit(state(current: false, results: false)); #expect(!value) }
        #expect(gate.pending)
        do { let value = gate.completed(state(current: false)); #expect(!value) }
        do { let value = gate.completed(state()); #expect(value) }
        #expect(!gate.pending)
        do { let value = gate.completed(state()); #expect(!value) } // only once
    }

    @Test func typingMoreForgetsAPendingSubmit() {
        var gate = RecentSearchRecordGate()
        _ = gate.submit(state(current: false, results: false))
        gate.queryChanged()
        do { let value = gate.completed(state()); #expect(!value) }
    }

    @Test func aSearchWithNoResultsRecordsNothingAndClearsPending() {
        var gate = RecentSearchRecordGate()
        _ = gate.submit(state(current: false, results: false))
        do { let value = gate.completed(state(results: false)); #expect(!value) }
        #expect(!gate.pending)
        do { let value = gate.completed(state()); #expect(!value) }
    }

    @Test func neverForAnEmptyQueryOrAnotherTab() {
        var gate = RecentSearchRecordGate()
        do { let value = gate.submit(state("  ")); #expect(!value) }
        #expect(!gate.pending)
        do { let value = gate.submit(state(tab: false)); #expect(!value) }
        #expect(!gate.pending)
        #expect(!RecentSearchRecordGate.recordsOnPick(state("")))
        #expect(!RecentSearchRecordGate.recordsOnPick(state(tab: false)))
        #expect(!RecentSearchRecordGate.recordsOnPick(state(current: false)))
        #expect(!RecentSearchRecordGate.recordsOnPick(state(results: false)))
    }

    @Test func openingAResultOnTheSearchTabRecords() {
        #expect(RecentSearchRecordGate.recordsOnPick(state()))
    }
}
