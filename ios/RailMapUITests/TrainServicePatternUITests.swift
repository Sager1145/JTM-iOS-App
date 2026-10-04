import XCTest

@MainActor
final class TrainServicePatternUITests: XCTestCase {
    override func setUp() async throws {
        try await super.setUp()
        continueAfterFailure = false
        await MainActor.run {
            XCUIDevice.shared.orientation = .portrait
        }
    }

    func testPartialExactTripShowsSourceTimesWithoutOfferingRouteApplication() {
        let app = XCUIApplication()
        app.launchArguments = ["-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        EditorLaunchSupport.launchEditing(app, journey: hachiojiJourney(date: "2026-09-27"))
        XCTAssertTrue(app.descendants(matching: .any)["rideEditorForm"].firstMatch.waitForExistence(timeout: 30))

        let picker = app.buttons["rideEditorServicePattern"]
        XCTAssertTrue(EditorUITestSupport.reveal(picker, in: app, maxDrags: 6), app.debugDescription)
        XCTAssertTrue(picker.waitForExistence(timeout: 8), app.debugDescription)
        EditorUITestSupport.tap(picker, in: app)
        let replaceStops = app.buttons["rideEditorReplaceStops"].firstMatch
        XCTAssertTrue(replaceStops.waitForExistence(timeout: 8), app.debugDescription)
        replaceStops.tap()
        let exactSearch = app.searchFields.firstMatch
        XCTAssertTrue(exactSearch.waitForExistence(timeout: 8))
        exactSearch.tap()
        exactSearch.typeText("しなの\n")

        let row = app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier BEGINSWITH %@",
                                  "timetableIncompleteTrip-jr-central.shinano.1.")).firstMatch
        for _ in 0..<10 {
            if row.waitForExistence(timeout: 1) { break }
            let list = app.collectionViews.firstMatch
            list.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.7))
                .press(forDuration: 0.1, thenDragTo: list.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)))
        }
        XCTAssertTrue(row.waitForExistence(timeout: 8), app.debugDescription)
        XCTAssertTrue(row.label.contains("07:00"))
        XCTAssertTrue(row.label.contains("名古屋"))
        XCTAssertTrue(row.label.contains("未確認"))
        XCTAssertEqual(app.buttons.matching(identifier: row.identifier).count, 0,
                       "Unverified route facts must remain read-only.")
        let details = app.buttons.matching(NSPredicate(
            format: "identifier BEGINSWITH %@", "timetableDetails-jr-central.shinano.1.")).firstMatch
        XCTAssertTrue(details.waitForExistence(timeout: 8))
        // The floating search bar can cover a row while XCTest still reports it hittable.
        for _ in 0..<8 {
            if details.isHittable && details.frame.maxY < app.frame.maxY - 120 { break }
            app.collectionViews.firstMatch.swipeUp()
        }
        XCTAssertTrue(details.isHittable, app.debugDescription)
        details.tap()
        let originTime = app.descendants(matching: .any)
            .matching(identifier: "timetableStop-1").firstMatch
        XCTAssertTrue(originTime.waitForExistence(timeout: 8), app.debugDescription)
        XCTAssertTrue(originTime.label.contains("名古屋"))
        XCTAssertTrue(originTime.label.contains("07:00"))
        XCTAssertTrue(originTime.label.contains("掲載なし"),
                      "Missing source arrival time must not become a made-up 00:00.")
    }

    func testSelectedPatternRechecksChangedDateWithoutReplacingStops() {
        let app = XCUIApplication()
        app.launchArguments = ["-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        // Stops are seeded, but the date notice reads the in-memory selected pattern.
        // Named stops open the replace confirmation before that pattern can be chosen.
        EditorLaunchSupport.launchEditing(app, journey: hachiojiJourney(date: nil))
        XCTAssertTrue(app.descendants(matching: .any)["rideEditorForm"].firstMatch.waitForExistence(timeout: 30))

        let picker = app.buttons["rideEditorServicePattern"]
        XCTAssertTrue(EditorUITestSupport.reveal(picker, in: app), app.debugDescription)
        XCTAssertTrue(picker.waitForExistence(timeout: 8))
        picker.tap()
        let replaceStops = app.buttons["rideEditorReplaceStops"].firstMatch
        XCTAssertTrue(replaceStops.waitForExistence(timeout: 8), app.debugDescription)
        replaceStops.tap()
        let search = app.searchFields.firstMatch
        XCTAssertTrue(search.waitForExistence(timeout: 8))
        search.tap()
        search.typeText("はちおうじ")
        let pattern = app.buttons.matching(NSPredicate(
            format: "label CONTAINS %@", "東京〜八王子")).firstMatch
        XCTAssertTrue(pattern.waitForExistence(timeout: 8))
        // The search keyboard covers the row. Dismiss it before the tap, and
        // confirm the out-of-date dialog if the picker stays up.
        let searchKey = app.keyboards.buttons["Search"]
        let searchKeyJA = app.keyboards.buttons["検索"]
        if searchKey.exists {
            searchKey.tap()
        } else if searchKeyJA.exists {
            searchKeyJA.tap()
        }
        pattern.tap()
        let patternList = app.descendants(matching: .any)["servicePatternList"].firstMatch
        let confirmPattern = app.buttons["確認して適用"]
        if patternList.exists, confirmPattern.waitForExistence(timeout: 2) {
            confirmPattern.tap()
        }
        XCTAssertTrue(patternList.waitForNonExistence(timeout: 8),
                      "Choosing a pattern must close the picker.")

        // The pattern control sits below the stop list, so the replaced origin
        // is an unmounted row above the current scroll position.
        let origin = app.descendants(matching: .any)["rideEditorStop-0"].firstMatch
        XCTAssertTrue(EditorUITestSupport.reveal(origin, in: app, maxDrags: 12, unmountedRowIsAbove: true),
                      app.debugDescription)
        XCTAssertTrue(origin.waitForExistence(timeout: 8))
        XCTAssertTrue(origin.label.contains("東京"))
        openPatternStop(origin, in: app)

        let departure = app.textFields["rideEditorStopDeparture"]
        revealStopEditorControl(departure, in: app)
        XCTAssertTrue(departure.waitForExistence(timeout: 8), app.debugDescription)
        departure.tap()
        departure.typeText("07:15")
        dismissStopEditorKeyboard(in: app)
        revealStopEditorControl(app.switches["rideEditorStopRidden"], in: app)
        let ridden = stopRiddenSwitch(in: app)
        XCTAssertTrue(ridden.waitForExistence(timeout: 8), app.debugDescription)
        XCTAssertTrue(ridden.isHittable, app.debugDescription)
        ridden.tap()
        XCTAssertEqual(stopRiddenSwitch(in: app).value as? String, "0",
                       "Clear the ridden switch before changing the journey date.")
        let stopBar = app.navigationBars["東京"]
        if stopBar.waitForExistence(timeout: 2) {
            stopBar.buttons.firstMatch.tap()
        } else {
            app.navigationBars.buttons.element(boundBy: 0).tap()
        }

        let date = app.textFields["rideEditorDateInput"]
        // Returning from the origin stop leaves the form on the stop list.
        // The date row is an unmounted Basics cell above that position.
        XCTAssertTrue(EditorUITestSupport.reveal(
            date, in: app, maxDrags: 14, unmountedRowIsAbove: true), app.debugDescription)
        XCTAssertTrue(date.waitForExistence(timeout: 8))
        XCTAssertTrue(placeControlBelowNavigationBar(date, in: app), app.debugDescription)
        let oldValue = date.value as? String ?? ""
        date.tap()
        date.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue,
                             count: oldValue.count) + "2026-10-12")
        XCTAssertEqual(date.value as? String, "2026-10-12")
        let notice = app.descendants(matching: .any)["rideEditorPatternDateNotice"]
        // The keyboard covers a screen-wide swipe's start point; scroll
        // the editor form so its date notice is actually materialized.
        let dateForm = app.collectionViews["rideEditorForm"]
        for _ in 0..<10 where !notice.exists {
            dateForm.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.4))
                .press(forDuration: 0.1, thenDragTo: dateForm.coordinate(
                    withNormalizedOffset: CGVector(dx: 0.5, dy: 0.15)))
        }
        XCTAssertTrue(notice.waitForExistence(timeout: 8), app.debugDescription)
        // A nav-bar tap leaves rideEditorDateInput focused. The following
        // full-height gutter drag then starts on the keyboard (y≈691) and
        // the form stays at the top, so rideEditorStop-0 never mounts.
        let originAfter = app.buttons["rideEditorStop-0"]
        revealPatternOrigin(originAfter, in: app)
        XCTAssertTrue(originAfter.waitForExistence(timeout: 8))
        XCTAssertTrue(originAfter.label.contains("東京"),
                      "Changing the ride date must not rewrite selected stops.")
        openPatternStop(originAfter, in: app)
        let departureAfter = app.textFields["rideEditorStopDeparture"]
        revealStopEditorControl(departureAfter, in: app)
        XCTAssertTrue(departureAfter.waitForExistence(timeout: 8), app.debugDescription)
        XCTAssertEqual((departureAfter.value as? String)?.split(separator: ":")
            .compactMap { Int($0) }, [7, 15],
            "Changing the date must preserve the edited departure time.")
        let riddenAfter = stopRiddenSwitch(in: app)
        revealStopEditorControl(riddenAfter, in: app)
        XCTAssertTrue(riddenAfter.waitForExistence(timeout: 8))
        XCTAssertNotEqual(riddenAfter.value as? String, "1",
                          "A reader-cleared ride segment must survive the date change.")
    }

    /// `EditorUITestSupport.reveal` treats the area under the Edit bar as
    /// visible. A row whose center is there never pushes StopEditorView.
    private func openPatternStop(_ stop: XCUIElement, in app: XCUIApplication) {
        XCTAssertTrue(placeControlBelowNavigationBar(stop, in: app), app.debugDescription)
        stop.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        XCTAssertTrue(app.otherElements["rideEditorStopName"].waitForExistence(timeout: 8),
                      "Tapping the stop row must push the stop editor. \(app.debugDescription)")
    }

    private func placeControlBelowNavigationBar(_ stop: XCUIElement, in app: XCUIApplication) -> Bool {
        let form = app.collectionViews["rideEditorForm"]
        guard form.waitForExistence(timeout: 5) else { return false }
        let bar = app.navigationBars["Edit"]
        for _ in 0..<8 {
            let floor = (bar.exists ? bar.frame.maxY : 132) + 12
            if stop.exists, stop.isHittable, stop.frame.height > 20,
               stop.frame.minY >= floor, stop.frame.maxY <= app.frame.maxY - 8 {
                return true
            }
            // A row tucked under the bar has to move downward with the content.
            if !stop.exists || stop.frame.midY < floor {
                form.swipeDown()
            } else {
                form.swipeUp()
            }
        }
        let floor = (bar.exists ? bar.frame.maxY : 132) + 8
        return stop.exists && stop.isHittable && stop.frame.minY >= floor
    }

    /// The ridden identifier wraps the real switch. The inner control is the
    /// one that reports a hittable value.
    private func stopRiddenSwitch(in app: XCUIApplication) -> XCUIElement {
        let outer = app.switches["rideEditorStopRidden"]
        let inner = outer.switches.firstMatch
        return inner.exists ? inner : outer
    }

    private func dismissStopEditorKeyboard(in app: XCUIApplication) {
        let keyboard = app.keyboards.firstMatch
        guard keyboard.exists else { return }
        let bar = app.navigationBars.firstMatch
        if bar.exists {
            bar.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        }
    }

    /// After the date edit the form is still at the top and the keyboard
    /// covers the lower half. Resign the date field, then take short gutter
    /// steps so a lazy stop row can mount between checks.
    private func revealPatternOrigin(_ stop: XCUIElement, in app: XCUIApplication) {
        let form = app.collectionViews["rideEditorForm"]
        XCTAssertTrue(form.waitForExistence(timeout: 5))
        resignDateField(in: app)
        func nudge(revealBelow: Bool) {
            let start = form.coordinate(withNormalizedOffset: CGVector(dx: 0.08, dy: revealBelow ? 0.58 : 0.36))
            let end = form.coordinate(withNormalizedOffset: CGVector(dx: 0.08, dy: revealBelow ? 0.42 : 0.52))
            start.press(forDuration: 0.05, thenDragTo: end)
        }
        func mounted() -> String {
            (0..<6).compactMap { index -> String? in
                let row = app.buttons["rideEditorStop-\(index)"]
                guard row.exists else { return nil }
                return "\(index)=\(row.label.replacingOccurrences(of: "\n", with: " "))"
            }.joined(separator: " | ")
        }
        for _ in 0..<32 {
            if stop.exists { return }
            nudge(revealBelow: true)
        }
        for _ in 0..<8 {
            if stop.exists { return }
            nudge(revealBelow: false)
        }
        XCTFail("Pattern stops must stay reachable after the date change. seen=\(mounted().isEmpty ? "none" : mounted()) keyboard=\(app.keyboards.firstMatch.exists)")
    }

    private func resignDateField(in app: XCUIApplication) {
        let keyboard = app.keyboards.firstMatch
        guard keyboard.exists else { return }
        let returnKey = keyboard.buttons["Return"]
        XCTAssertTrue(returnKey.waitForExistence(timeout: 2), app.debugDescription)
        returnKey.tap()
        XCTAssertTrue(keyboard.waitForNonExistence(timeout: 5),
                      "Submitting the date must dismiss the keyboard before revealing stops.")
    }

    /// Stop times sit below the station block on the pushed editor, not on
    /// `rideEditorForm`. Drag that form's gutter so a DatePicker does not
    /// consume the scroll, and stop once the control is clear of the bar
    /// and the keyboard.
    private func revealStopEditorControl(_ element: XCUIElement, in app: XCUIApplication) {
        let lists = app.collectionViews.allElementsBoundByIndex.filter {
            $0.identifier != "rideEditorForm" && $0.exists && $0.frame.height > 200
        }
        let list = lists.last
        for _ in 0..<12 {
            let floor = (app.navigationBars.firstMatch.exists
                ? app.navigationBars.firstMatch.frame.maxY : 132) + 8
            let keyboard = app.keyboards.firstMatch
            let ceiling = keyboard.exists ? keyboard.frame.minY - 8 : app.frame.maxY - 8
            if element.exists, element.isHittable, element.frame.minY >= floor,
               element.frame.maxY <= ceiling {
                return
            }
            guard let list else {
                app.swipeUp()
                continue
            }
            let start = list.coordinate(withNormalizedOffset: CGVector(dx: 0.06, dy: 0.62))
            let end = list.coordinate(withNormalizedOffset: CGVector(dx: 0.06, dy: 0.42))
            start.press(forDuration: 0.05, thenDragTo: end)
        }
    }

    private func hachiojiJourney(date: String?) -> [String: Any] {
        var journey: [String: Any] = [
            "id": "ui-hachioji",
            "number": "",
            "origin": "東京",
            "destination": "八王子",
            "region": "jp",
            "visible": true,
            "stops": [
                EditorLaunchSupport.stop("東京", code: "003766", type: "origin"),
                EditorLaunchSupport.stop("新宿", code: "003700", type: "passenger_stop"),
                EditorLaunchSupport.stop("立川", code: "003634", type: "passenger_stop"),
                EditorLaunchSupport.stop("八王子", code: "003947", type: "destination"),
            ],
        ]
        if let date { journey["date"] = date }
        return journey
    }
}
