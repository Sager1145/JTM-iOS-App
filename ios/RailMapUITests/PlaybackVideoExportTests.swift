import XCTest
import UIKit

@MainActor
final class PlaybackVideoExportTests: XCTestCase {
    override func setUp() {
        super.setUp()
        continueAfterFailure = false
    }

    func testCancelledRecordingOffersThePartialVideo() throws {
        try assertPartialVideo(stoppingPlayback: false)
    }

    func testStoppingPlaybackKeepsThePartialVideoReachable() throws {
        try assertPartialVideo(stoppingPlayback: true)
    }

    func testNaturallyCompletedRecordingOffersTheCompleteVideo() throws {
        try XCTSkipUnless(UIDevice.current.userInterfaceIdiom == .phone)
        XCUIDevice.shared.orientation = .portrait
        let startedAt = Date()
        defer {
            let timing = XCTAttachment(string:
                "Natural completed-video export UI test elapsed: \(Date().timeIntervalSince(startedAt)) seconds")
            timing.name = "complete-video-export-elapsed"
            timing.lifetime = .keepAlways
            add(timing)
            attachScreen(named: "complete-video-export-final")
        }

        let app = XCUIApplication()
        app.launchArguments = [
            "-AppleLanguages", "(en)", "-AppleLocale", "en_US",
            "-playback-video-v1", "{ shape = native; quality = q540; bitrate = small; }",
        ]
        app.launchEnvironment["RAILMAP_UI_TEST_TAB"] = "all"
        app.launchEnvironment["RAILMAP_UI_TEST_STAGE"] = "compact"
        app.launchEnvironment["RAILMAP_UI_TEST_SAMPLE"] = "train-store"
        app.launchEnvironment["RAILMAP_UI_TEST_PLAYBACK"] = "1"
        app.launch()

        let pauseResume = element("playbackPauseResume", in: app)
        XCTAssertTrue(pauseResume.waitForExistence(timeout: 60))
        waitForLabel("Pause", on: pauseResume)
        pauseResume.tap()
        waitForLabel("Play", on: pauseResume)
        let surface = element("playbackTransportSurface", in: app)
        XCTAssertTrue(surface.staticTexts.matching(
            NSPredicate(format: "label CONTAINS %@", "はるか38号")).firstMatch.exists,
            "The export must use the same Haruka sample as the partial-recording tests.")

        let video = element("playbackVideoButton", in: app)
        XCTAssertTrue(video.waitForExistence(timeout: 8))
        video.tap()
        let start = element("videoExportStart", in: app)
        XCTAssertTrue(start.waitForExistence(timeout: 8))
        XCTAssertTrue(start.isEnabled)
        attachScreen(named: "complete-video-export-options")
        start.tap()
        waitForLabel("Cancel video export", on: video, timeout: 20)
        waitForLabel("Pause", on: pauseResume, timeout: 20)
        XCTAssertTrue(pauseResume.isEnabled)
        attachScreen(named: "complete-video-export-recording")

        // Production onFinish fires after the final journey and its closing
        // panorama. No Stop, Cancel, Next or pause action ends this recording.
        let ended = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "exists == true AND enabled == false"),
            object: pauseResume)
        XCTAssertEqual(XCTWaiter.wait(for: [ended], timeout: 35), .completed,
                       "The single default-speed sample must reach its natural end.")
        waitForLabel("Play", on: pauseResume)
        attachScreen(named: "complete-video-export-natural-end")
        waitForLabel("Share video", on: video, timeout: 40)
        XCTAssertFalse(video.label.hasPrefix("Kept the part recorded before it stopped:"))
        XCTAssertNotEqual(video.label, "Share partial video")
        XCTAssertTrue(video.isHittable)
        XCTAssertTrue(app.frame.contains(video.frame))
        XCTAssertFalse(pauseResume.isEnabled)
        attachScreen(named: "complete-video-export-ready-to-share")
        // ShareLink's production URL stays in the app temporary directory.
        // Leave it unopened and do not terminate/dismiss: the existing runner
        // copies RailMap-*.mp4 and verifies the complete H.264 asset separately.
    }

    private func assertPartialVideo(stoppingPlayback: Bool) throws {
        try XCTSkipUnless(UIDevice.current.userInterfaceIdiom == .phone)
        XCUIDevice.shared.orientation = .portrait
        let startedAt = Date()
        defer {
            let elapsed = Date().timeIntervalSince(startedAt)
            let timing = XCTAttachment(string: "Video export UI test elapsed: \(elapsed) seconds")
            timing.name = "partial-video-export-elapsed"
            timing.lifetime = .keepAlways
            add(timing)
            attachScreen(named: "partial-video-export-final")
        }

        let app = XCUIApplication()
        app.launchArguments = [
            "-AppleLanguages", "(en)", "-AppleLocale", "en_US",
            // VideoExportSettings reads one persisted preferences dictionary.
            "-playback-video-v1", "{ shape = native; quality = q540; bitrate = small; }",
        ]
        app.launchEnvironment["RAILMAP_UI_TEST_TAB"] = "all"
        app.launchEnvironment["RAILMAP_UI_TEST_STAGE"] = "compact"
        app.launchEnvironment["RAILMAP_UI_TEST_SAMPLE"] = "train-store"
        app.launchEnvironment["RAILMAP_UI_TEST_PLAYBACK"] = "1"
        app.launch()

        let pauseResume = element("playbackPauseResume", in: app)
        XCTAssertTrue(pauseResume.waitForExistence(timeout: 60))
        waitForLabel("Pause", on: pauseResume)
        pauseResume.tap()
        waitForLabel("Play", on: pauseResume)

        let video = element("playbackVideoButton", in: app)
        XCTAssertTrue(video.waitForExistence(timeout: 8))
        video.tap()
        let start = element("videoExportStart", in: app)
        XCTAssertTrue(start.waitForExistence(timeout: 8))
        XCTAssertTrue(start.isEnabled, "The bundled sample must have a playable export plan.")
        attachScreen(named: "partial-video-export-options")
        start.tap()

        waitForLabel("Cancel video export", on: video, timeout: 20)
        // Recording restarts its queue and begins after the opening overview.
        waitForLabel("Pause", on: pauseResume, timeout: 20)
        let recordingStartedAt = Date()
        let shortRecording = XCTNSPredicateExpectation(
            predicate: NSPredicate { _, _ in
                Date().timeIntervalSince(recordingStartedAt) >= 4
            }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [shortRecording], timeout: 8), .completed)
        pauseResume.tap()
        waitForLabel("Play", on: pauseResume)
        waitForLabel("Cancel video export", on: video)
        attachScreen(named: "partial-video-export-before-cancel")
        if stoppingPlayback {
            element("playbackStopButton", in: app).tap()
        } else {
            video.tap()
        }

        // The shared web catalog currently names this action with the kept
        // portion message. Also accept the native fallback if that key is
        // absent; neither branch accepts a complete-video Share action.
        let partialVideo = XCTNSPredicateExpectation(
            predicate: NSPredicate(
                format: "label BEGINSWITH %@ OR label == %@",
                "Kept the part recorded before it stopped:", "Share partial video"),
            object: video)
        XCTAssertEqual(XCTWaiter.wait(for: [partialVideo], timeout: 40), .completed,
                       "Finishing a cancelled recording must expose its partial video.")
        XCTAssertTrue(video.isHittable)
        XCTAssertTrue(app.frame.contains(video.frame))
        if stoppingPlayback {
            XCTAssertFalse(pauseResume.exists, "Stopped playback must not retain live transport controls.")
            let dismiss = element("playbackExportDismiss", in: app)
            XCTAssertTrue(dismiss.isHittable)
            dismiss.tap()
            let hidden = XCTNSPredicateExpectation(
                predicate: NSPredicate(format: "exists == false"), object: video)
            XCTAssertEqual(XCTWaiter.wait(for: [hidden], timeout: 5), .completed)
        }
        attachScreen(named: "partial-video-export-ready-to-share")
        // Leave the native ShareLink unopened: the file stays in the app's
        // temporary directory for AVAssetReader verification by the harness.
    }

    private func element(_ identifier: String, in app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: identifier).firstMatch
    }

    private func waitForLabel(_ label: String, on element: XCUIElement, timeout: TimeInterval = 15) {
        let expectation = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "label == %@", label), object: element)
        XCTAssertEqual(XCTWaiter.wait(for: [expectation], timeout: timeout), .completed,
                       "Expected \(label); found \(element.label).")
    }

    private func attachScreen(named name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
