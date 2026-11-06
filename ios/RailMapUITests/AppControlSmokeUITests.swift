#if DEBUG
import RailPresentation
import XCTest

/// The test control channel end to end on the simulator: `state` and
/// `loadSamples` sent as `railmap-test://` URLs reach the DEBUG app, run on
/// an isolated store, and report back. The app mirrors each finished result
/// as `<id>:<status>` on a hidden `appControlLastResult` element.
@MainActor
final class AppControlSmokeUITests: XCTestCase {
    override func setUp() async throws {
        continueAfterFailure = false
    }

    func testStateAndLoadSamplesOverTheControlChannel() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-AppleLanguages", "(en)", "-AppleLocale", "en_US", "-interface-language", "en"]
        UITestLaunchSupport.launch(app)
        // Results persist in the container across runs and a finished ID is
        // never run twice, so every run uses fresh request IDs.
        let run = UUID().uuidString.prefix(8)

        try send(AppControlRequest(id: "smoke-state-\(run)", command: "state", args: ["trips": false]), to: app)
        try send(AppControlRequest(id: "smoke-load-\(run)", command: "loadSamples",
                                   args: ["samples": "tokyo-limited-express-loop"]), to: app)
        try send(AppControlRequest(id: "smoke-wait-\(run)", command: "wait",
                                   args: ["condition": "trips>=1", "timeoutMs": 30_000]), to: app)
        XCTAssertEqual(app.state, .runningForeground)
    }

    private func send(_ request: AppControlRequest, to app: XCUIApplication) throws {
        app.open(try AppControlURL.make(request))
        // iOS 26+ may confirm a custom-scheme URL ("Open in “RailMap”?").
        let confirm = XCUIApplication(bundleIdentifier: "com.apple.springboard").buttons["Open"]
        if confirm.waitForExistence(timeout: 3) { confirm.tap() }
        let result = app.descendants(matching: .any)["appControlLastResult"]
        let expected = "\(request.id):ok"
        let done = NSPredicate { _, _ in
            result.exists && (result.label.hasPrefix("\(request.id):"))
        }
        wait(for: [XCTNSPredicateExpectation(predicate: done, object: nil)], timeout: 60)
        XCTAssertEqual(result.label, expected, "\(request.command) did not succeed")
    }
}
#endif
