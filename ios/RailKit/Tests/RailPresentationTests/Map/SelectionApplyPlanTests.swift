import RailPresentation
import Testing

struct SelectionApplyPlanTests {
    private func decide(
        _ selected: String?, standalone: String? = "a", cached: Bool = true,
        batches: Bool = true, valid: Bool = true
    ) -> SelectionApplyPlan {
        SelectionApplyPlan.decide(
            selected: selected, standalone: standalone, routeCachedInFrame: cached,
            batchCacheCurrent: batches, contextValid: valid)
    }

    @Test func anInvalidContextAlwaysRebuilds() {
        for selected in [nil, "a", "b"] as [String?] {
            #expect(decide(selected, valid: false) == .rebuild)
        }
    }

    @Test func deselectionAndTheStandaloneRideNeedNoRebatching() {
        #expect(decide(nil, cached: false, batches: false) == .selectionOnly(rebatch: false))
        #expect(decide("a", cached: false, batches: false) == .selectionOnly(rebatch: false))
    }

    @Test func aNewPickIsAnsweredInPlaceOnlyWithItsWholeRouteAndTheBatchesCached() {
        #expect(decide("b") == .selectionOnly(rebatch: true))
        #expect(decide("b", standalone: nil) == .selectionOnly(rebatch: true))
        #expect(decide("b", cached: false) == .rebuild)
        #expect(decide("b", batches: false) == .rebuild)
    }
}
