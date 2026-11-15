import RailPresentation
import Testing

struct OverlaySwapSequencerTests {
    @Test("The old overlays stay until every new renderer reports drawn")
    func oldStaysUntilNewDrawn() {
        var swap = OverlaySwapSequencer(newKeys: ["a", "b"])
        #expect(swap.decision == .holdOld)
        swap.reportDrawn(key: "a")
        #expect(swap.decision == .holdOld)
        swap.reportDrawn(key: "b")
        #expect(swap.decision == .retireOld)
    }

    @Test("Undrawn keys hold well past two frames; the time fallback retires them")
    func timeFallback() {
        var swap = OverlaySwapSequencer(newKeys: ["a"])
        for _ in 0..<10 { swap.elapse(1.0 / 60.0) }
        #expect(swap.decision == .holdOld)
        swap.elapse(OverlaySwapSequencer.fallbackSeconds)
        #expect(swap.decision == .retireOld)
    }

    @Test("Reporting a key twice or an unknown key changes nothing else")
    func reportsAreIdempotent() {
        var swap = OverlaySwapSequencer(newKeys: ["a", "b"])
        swap.reportDrawn(key: "a")
        swap.reportDrawn(key: "a")
        swap.reportDrawn(key: "zzz")
        #expect(swap.undrawn == ["b"])
        #expect(swap.decision == .holdOld)
    }

    @Test("Nothing new to wait for retires at once")
    func emptyRetiresImmediately() {
        #expect(OverlaySwapSequencer(newKeys: [String]()).decision == .retireOld)
    }
}
