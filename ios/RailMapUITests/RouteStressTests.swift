import XCTest

/// Real sample routes and the production import, add, export and MapKit paths.
/// Scale from the test runner's environment with RAILMAP_STRESS_COUNT (default
/// 1000), RAILMAP_STRESS_ADDITIONS (100), and RAILMAP_STRESS_SWITCHES (60).
/// Assertion deadlines are bounded readiness polls, never fixed settle sleeps.
@MainActor
final class RouteStressTests: XCTestCase {
    override func setUp() { continueAfterFailure = false }

    func testLargeMultiCountryImportExportRoundtrip() throws {
        let app = launch()
        defer { app.terminate() }
        let status = app.staticTexts["routeStressStatus"]
        let imported = try wait(status, timeout: 300) { $0["phase"] == "ready" }
        try assertCompleteImport(imported)
        attach(imported.raw, name: "large-import-metrics")

        // A loaded model count is insufficient: wait until geometry for the
        // complete large document actually reaches the map coordinator.
        let map = app.staticTexts["railMapRenderStatus"]
        let rendered = try wait(map, timeout: 300) {
            $0.int("rides") == imported.int("expected") && $0.int("rebuilds") > 0
        }
        attach(rendered.raw, name: "large-map-render-metrics")
        app.buttons["routeStressRoundtrip"].tap()
        let roundtrip = try wait(status, timeout: 300) { $0["phase"] == "roundtripped" }
        XCTAssertEqual(roundtrip.int("roundtrip"), 1, "Canonical JSON changed after export and real reimport.")
        XCTAssertEqual(roundtrip.int("stored"), imported.int("expected"))
        XCTAssertEqual(roundtrip.int("loaded"), imported.int("expected"))
        XCTAssertGreaterThan(roundtrip.int("bytes"), 100_000, "The export was unexpectedly small.")
        XCTAssertEqual(roundtrip.int("countries"), 5)
        attach(roundtrip.raw, name: "large-roundtrip-metrics")
    }

    func testRapidAddsAndHighlightDateSwitchesSettleOnLatestRoute() throws {
        let app = launch()
        defer { app.terminate() }
        let status = app.staticTexts["routeStressStatus"]
        let map = app.staticTexts["railMapRenderStatus"]
        let imported = try wait(status, timeout: 300) { $0["phase"] == "ready" }
        try assertCompleteImport(imported)
        _ = try wait(map, timeout: 300) { $0.int("rides") == imported.int("expected") }

        app.buttons["routeStressAdd"].tap()
        let added = try wait(status, timeout: 90) {
            $0["phase"] == "added" && $0.int("stored") == $0.int("expected")
                && $0.int("loaded") == $0.int("expected") && $0["selected"] == $0["requested"]
        }
        XCTAssertGreaterThan(added.int("expected"), imported.int("expected"))
        let selectedAfterAdds = try waitForSelection(map, requested: added, timeout: 90)
        attach(added.raw, name: "rapid-add-metrics")
        attach(selectedAfterAdds.raw, name: "rapid-add-installed-selection")
        app.buttons["routeStressFinish"].tap()

        let started = Date()
        app.buttons["routeStressSwitch"].tap()
        let switched = try wait(status, timeout: 90) { $0["phase"] == "switched" }
        XCTAssertGreaterThanOrEqual(switched.int("switches"), 10)
        let selected = try waitForSelection(map, requested: switched, timeout: 30)
        let settleSeconds = Date().timeIntervalSince(started)
        let scheduledSeconds = Double(switched.int("switches")) * 0.025
        XCTAssertLessThan(settleSeconds, scheduledSeconds + 30,
                          "The final route remained stale after the rapid selection stream ended.")
        app.buttons["routeStressFinish"].tap()
        let finished = try wait(status, timeout: 10) { $0["phase"] == "finished" }
        XCTAssertGreaterThan(finished.int("frames"), 20, "No meaningful main display-link sample was recorded.")
        let maximumGap = Int(ProcessInfo.processInfo.environment["RAILMAP_STRESS_MAX_FRAME_GAP_MS"] ?? "") ?? 500
        XCTAssertLessThanOrEqual(finished.int("maxFrameGapMs"), maximumGap,
                                 "The main display link stalled during rapid highlight/date changes.")
        attach(finished.raw + ";settleSeconds:\(settleSeconds)", name: "rapid-switch-responsiveness")
        attach(selected.raw, name: "rapid-switch-installed-selection")
        let screenshot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        screenshot.name = "stress-final-selected-route"
        screenshot.lifetime = .keepAlways
        add(screenshot)
    }

    private func launch() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchEnvironment["RAILMAP_UI_TEST_STORAGE_ID"] = UUID().uuidString
        app.launchArguments = ["-AppleLanguages", "(en)", "-AppleLocale", "en_US",
                               "-appearance", "light", "-map-follows-selected-date", "NO",
                               "-auto-focus-zoom", "NO"]
        app.launchEnvironment["RAILMAP_UI_TEST_STRESS"] = "1"
        app.launchEnvironment["RAILMAP_UI_TEST_TAB"] = "all"
        app.launchEnvironment["RAILMAP_UI_TEST_STATS_REGION"] = "all"
        app.launchEnvironment["RAILMAP_UI_TEST_STAGE"] = "compact"
        // Frame Japan at launch so the first large ride render is on-screen.
        app.launchEnvironment["RAILMAP_UI_TEST_CAMERA"] = "37,138,24"
        for key in ["RAILMAP_STRESS_COUNT", "RAILMAP_STRESS_ADDITIONS", "RAILMAP_STRESS_SWITCHES"] {
            if let value = ProcessInfo.processInfo.environment[key] { app.launchEnvironment[key] = value }
        }
        app.launch()
        return app
    }

    private func assertCompleteImport(_ status: Status) throws {
        XCTAssertGreaterThanOrEqual(status.int("expected"), 50)
        XCTAssertEqual(status.int("stored"), status.int("expected"))
        XCTAssertEqual(status.int("loaded"), status.int("expected"))
        XCTAssertEqual(status.int("countries"), 5, "A country was lost during real import.")
        XCTAssertGreaterThanOrEqual(status.int("dates"), 5, "The dataset did not exercise distinct real sample dates.")
        XCTAssertEqual(status["error"], "none")
    }

    private func waitForSelection(_ element: XCUIElement, requested: Status, timeout: TimeInterval) throws -> Status {
        let settled = try wait(element, timeout: timeout) {
            $0["submittedSelection"] == requested["requested"]
                && $0["submittedDate"] == requested["date"]
                && $0.int("selectionExpectedParts") > 0
                && $0.int("selectionParts") == $0.int("selectionExpectedParts")
                && $0.int("selectionCasingParts") == $0.int("selectionParts")
                && $0.int("selectionRenderers") > 0 && $0.int("selectionSettled") == 1
        }
        XCTAssertEqual(settled["submittedSelection"], requested["requested"])
        return settled
    }

    private func wait(_ element: XCUIElement, timeout: TimeInterval,
                      condition: @escaping (Status) -> Bool) throws -> Status {
        XCTAssertTrue(element.waitForExistence(timeout: min(timeout, 30)), "Missing DEBUG stress/readiness probe.")
        var latest = Status(raw: element.label)
        let predicate = NSPredicate { _, _ in
            latest = Status(raw: element.label)
            if latest["phase"] == "failed" { return true }
            return condition(latest)
        }
        let result = XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: predicate, object: element)], timeout: timeout)
        guard result == .completed, latest["phase"] != "failed", condition(latest) else {
            attach(latest.raw, name: "stress-readiness-failure")
            XCTFail("Stress readiness did not settle: \(latest.raw)")
            throw ReadinessFailure()
        }
        return latest
    }

    private struct Status {
        let raw: String
        var fields: [String: String] {
            Dictionary(raw.split(separator: ";").compactMap { field in
                let pair = field.split(separator: ":", maxSplits: 1).map(String.init)
                return pair.count == 2 ? (pair[0], pair[1]) : nil
            }, uniquingKeysWith: { _, last in last })
        }
        subscript(_ key: String) -> String? { fields[key] }
        func int(_ key: String) -> Int { Int(fields[key] ?? "") ?? -1 }
    }
    private struct ReadinessFailure: Error {}
    private func attach(_ value: String, name: String) {
        let attachment = XCTAttachment(string: value)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
