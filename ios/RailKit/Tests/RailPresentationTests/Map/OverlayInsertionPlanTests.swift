import RailPresentation
import Testing

struct OverlayInsertionPlanTests {
    /// Apply the steps the way MapKit's insertOverlay(_:at:) would.
    private func apply(_ steps: [OverlayInsertionPlan.Step], to mounted: [Int]) -> [Int] {
        var stack = mounted
        for step in steps { stack.insert(step.id, at: step.index) }
        return stack
    }

    @Test("A fresh install lands in target order, so no exchange is needed")
    func freshInstallNeedsNoReorder() {
        let target = [1, 2, 3, 10, 11]  // network batches 1-3 beneath ride 10, 11
        let steps = OverlayInsertionPlan.steps(mounted: [10, 11], target: target, new: [1, 2, 3])
        #expect(apply(steps, to: [10, 11]) == target)
    }

    @Test("Nothing mounted: every overlay inserts in target order")
    func emptyMap() {
        let target = [4, 5, 6]
        let steps = OverlayInsertionPlan.steps(mounted: [], target: target, new: [4, 5, 6])
        #expect(apply(steps, to: []) == target)
    }

    @Test("New overlays interleave with retiring and kept ones at their final index")
    func interleaved() {
        let mounted = [100, 7, 20]  // handoff 100, kept network 7, ride 20
        let target = [100, 7, 8, 9, 20]
        let steps = OverlayInsertionPlan.steps(mounted: mounted, target: target, new: [8, 9])
        #expect(apply(steps, to: mounted) == target)
    }

    @Test("A new overlay MapKit already holds is not inserted twice")
    func alreadyMountedSkipped() {
        let steps = OverlayInsertionPlan.steps(mounted: [1, 2], target: [1, 2, 3], new: [2, 3])
        #expect(steps == [.init(id: 3, index: 2)])
    }

    @Test("Duplicates in the target and a new overlay absent from it do not break indices")
    func duplicatesAndStrays() {
        let steps = OverlayInsertionPlan.steps(mounted: [1], target: [1, 2, 2], new: [2, 9])
        let result = apply(steps, to: [1])
        #expect(result == [1, 2, 9])
        #expect(steps.allSatisfy { $0.index <= result.count })
    }

    @Test("No new overlays means no steps")
    func noNew() {
        #expect(OverlayInsertionPlan.steps(mounted: [1, 2], target: [2, 1], new: []).isEmpty)
    }
}
