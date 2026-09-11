import RailPresentation
import Testing

struct MapCameraPolicyTests {
    @Test("Opening camera is set once, even after more packages arrive")
    func launchOnlyOnce() {
        var camera = MapCameraPolicy()
        let opened = camera.openAtLaunch()
        #expect(opened)
        #expect(camera.openAtLaunch() == false)
        #expect(camera.takeFocusRequest() == nil)
    }

    @Test("A camera command before data loading completes wins over launch")
    func readerCommandPreventsLateLaunch() {
        var camera = MapCameraPolicy()
        camera.claimCamera()
        #expect(camera.openAtLaunch() == false)
    }

    @Test("A renderer replacement cannot replay journey or date focus", arguments: [
        MapCameraPolicy.FocusTarget.journey("train-a"), .date("2026-09-08"),
    ])
    func focusIsConsumedOnce(target: MapCameraPolicy.FocusTarget) throws {
        var camera = MapCameraPolicy()
        camera.requestFocus(target, enabled: true, playbackIsActive: false)
        let requestValue = camera.takeFocusRequest()
        let request = try #require(requestValue)
        #expect(request.target == target)
        #expect(camera.isCurrent(request))
        // Another map renderer shares the same camera owner.
        #expect(camera.takeFocusRequest() == nil)
        #expect(camera.openAtLaunch() == false)
    }

    @Test("Missing geometry is not a promise to focus when a solve finishes")
    func routeCompletionDoesNotReissueFocus() {
        var camera = MapCameraPolicy()
        camera.requestFocus(.journey("loading"), enabled: true, playbackIsActive: false)
        #expect(camera.takeFocusRequest() != nil)
        // The renderer could not frame the request, then data arrives.
        #expect(camera.takeFocusRequest() == nil)
    }

    @Test("Replacing a renderer between observation and framing keeps the request")
    func replacementBeforeCommitKeepsFocus() {
        var camera = MapCameraPolicy()
        camera.requestFocus(.journey("a"), enabled: true, playbackIsActive: false)
        let oldRendererRequest = camera.pendingFocusRequest
        // The old renderer is dismantled before its deferred camera write.
        let newRendererRequest = camera.pendingFocusRequest
        #expect(oldRendererRequest != nil)
        #expect(newRendererRequest == oldRendererRequest)
        let committed = camera.takeFocusRequest()
        #expect(committed == newRendererRequest)
        #expect(camera.pendingFocusRequest == nil)
        #expect(camera.takeFocusRequest() == nil)
    }

    @Test("Disabled focus and active playback reject user picks", arguments: [
        (false, false), (false, true), (true, true),
    ])
    func focusGuards(flags: (Bool, Bool)) {
        var camera = MapCameraPolicy()
        #expect(camera.requestFocus(
            .journey("a"), enabled: flags.0, playbackIsActive: flags.1) == nil)
        #expect(camera.takeFocusRequest() == nil)
    }

    @Test("A gesture or explicit camera command cancels an enqueued fit")
    func userInterruptsQueuedFocus() throws {
        var camera = MapCameraPolicy()
        camera.requestFocus(.journey("a"), enabled: true, playbackIsActive: false)
        let queuedValue = camera.takeFocusRequest()
        let queued = try #require(queuedValue)
        camera.claimCamera()
        #expect(camera.isCurrent(queued) == false)
    }

    @Test("A later pick supersedes the old target, including disabled focus")
    func latestIntentWins() throws {
        var camera = MapCameraPolicy()
        camera.requestFocus(.journey("a"), enabled: true, playbackIsActive: false)
        let firstValue = camera.takeFocusRequest()
        let first = try #require(firstValue)
        camera.requestFocus(.journey("b"), enabled: true, playbackIsActive: false)
        let secondValue = camera.takeFocusRequest()
        let second = try #require(secondValue)
        #expect(camera.isCurrent(first) == false)
        #expect(camera.isCurrent(second))
        camera.requestFocus(.journey("c"), enabled: false, playbackIsActive: false)
        #expect(camera.isCurrent(second) == false)
        #expect(camera.takeFocusRequest() == nil)
    }

}
