import Testing

@testable import RailPresentation

@Suite("MemoryPressureNetworkPolicy")
struct MemoryPressureNetworkPolicyTests {
    private let built = DisplayRectValue(x: 0, y: 0, width: 100, height: 100)

    @Test func noRectsMeansNothingToProtect() {
        #expect(MemoryTrimProtection.protectedRects(lastBuilt: nil, visible: nil).isEmpty)
    }

    @Test func eitherRectAloneIsProtected() {
        #expect(MemoryTrimProtection.protectedRects(lastBuilt: built, visible: nil) == [built])
        #expect(MemoryTrimProtection.protectedRects(lastBuilt: nil, visible: built) == [built])
    }

    @Test func aVisibleRectInsideTheBuiltOneAddsNothing() {
        let inside = DisplayRectValue(x: 10, y: 10, width: 50, height: 50)
        #expect(MemoryTrimProtection.protectedRects(lastBuilt: built, visible: inside) == [built])
    }

    @Test func aVisibleRectOutsideTheBuiltOneIsProtectedToo() {
        let moved = DisplayRectValue(x: 80, y: 0, width: 100, height: 100)
        #expect(MemoryTrimProtection.protectedRects(lastBuilt: built, visible: moved) == [built, moved])
    }

    @Test func prefetchStaysSuspendedForTheSameRequestAndLiftsOnADifferentOne() {
        let request = DisplayCameraRequest(rect: built, cameraZoom: 9)
        var gate = MemoryPressurePrefetchGate()
        #expect(!gate.isPrefetchSuspended)
        gate.suspend(after: request)
        #expect(gate.isPrefetchSuspended)
        gate.noteRequest(request)
        #expect(gate.isPrefetchSuspended)
        gate.noteRequest(DisplayCameraRequest(rect: built, cameraZoom: 10))
        #expect(!gate.isPrefetchSuspended)
    }

    @Test func aDifferentRectLiftsTheSuspensionAndItStaysLifted() {
        let request = DisplayCameraRequest(rect: built, cameraZoom: 9)
        var gate = MemoryPressurePrefetchGate()
        gate.suspend(after: request)
        let panned = DisplayCameraRequest(
            rect: DisplayRectValue(x: 5, y: 0, width: 100, height: 100), cameraZoom: 9)
        gate.noteRequest(panned)
        #expect(!gate.isPrefetchSuspended)
        gate.noteRequest(request)
        #expect(!gate.isPrefetchSuspended)
    }

    @Test func aWarningBeforeAnyRequestLiftsOnTheFirstRequest() {
        var gate = MemoryPressurePrefetchGate()
        gate.suspend(after: nil)
        #expect(gate.isPrefetchSuspended)
        gate.noteRequest(DisplayCameraRequest(rect: built, cameraZoom: 5))
        #expect(!gate.isPrefetchSuspended)
    }

    @Test func resetClearsTheSuspension() {
        var gate = MemoryPressurePrefetchGate()
        gate.suspend(after: DisplayCameraRequest(rect: built, cameraZoom: 5))
        gate.reset()
        #expect(!gate.isPrefetchSuspended)
    }
}
