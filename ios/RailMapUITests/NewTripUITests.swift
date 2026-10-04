import XCTest

@MainActor
final class NewTripUITests: XCTestCase {
    override func setUp() async throws {
        try await super.setUp()
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
    }

    func testNewTripStartsEmptyAndSaveRequiresRoute() {
        let app = XCUIApplication()
        EditorLaunchSupport.launchNewTrip(app)
        let save = app.buttons["newTripSave"]
        XCTAssertTrue(save.waitForExistence(timeout: 20))
        XCTAssertFalse(save.isEnabled, "Save starts disabled before either station is chosen.")

        // 003768 is not in the package. 品川 on 山手線 is 004095 and sorts to the top of a name search.
        pickStation(field: "newTripOrigin", query: "品川", code: "004095",
                    lineID: "jp-東日本旅客鉄道-山手線", in: app)
        XCTAssertFalse(save.isEnabled, "One station is not a route, so Save stays disabled.")
        XCTAssertFalse(app.descendants(matching: .any)["newTripCorridor-0"].exists)
    }

    func testStationSearchByStationLineAndCompany() {
        let app = XCUIApplication()
        EditorLaunchSupport.launchNewTrip(app)
        let origin = app.buttons["newTripOrigin"]
        XCTAssertTrue(waitForEnabled(origin, timeout: 20))
        origin.tap()

        let search = app.searchFields.firstMatch
        XCTAssertTrue(search.waitForExistence(timeout: 20))
        replaceSearch(search, with: "渋谷", in: app)
        let shibuya = stationRows(in: app).matching(NSPredicate(
            format: "identifier ENDSWITH %@", "-003922")).firstMatch
        XCTAssertTrue(shibuya.waitForExistence(timeout: 20),
                      "A station query must list that station's rows.")

        replaceSearch(search, with: "Ginza", in: app)
        XCTAssertTrue(stationRows(in: app).firstMatch.waitForExistence(timeout: 20))
        XCTAssertGreaterThan(stationRows(in: app).count, 1)
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(
            format: "label CONTAINS %@", "銀座")).firstMatch.waitForExistence(timeout: 8),
                      "A line query must list that line's stations.")

        replaceSearch(search, with: "東京メトロ", in: app)
        XCTAssertTrue(stationRows(in: app).firstMatch.waitForExistence(timeout: 20),
                      "A company query must list that company's stations.")
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(
            format: "label CONTAINS %@", "東京メトロ")).firstMatch.waitForExistence(timeout: 8))

        replaceSearch(search, with: "Ginza", in: app)
        let ginzaShibuya = stationRows(in: app).matching(NSPredicate(
            format: "identifier ENDSWITH %@", "-003922")).firstMatch
        XCTAssertTrue(ginzaShibuya.waitForExistence(timeout: 20))
        ginzaShibuya.tap()

        let shown = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "label CONTAINS ' · ' AND label CONTAINS '銀座'"),
            object: origin)
        XCTAssertEqual(XCTWaiter.wait(for: [shown], timeout: 8), .completed,
                       "Picking a row must show \"<line> · <operator>\" on the origin.")
    }

    func testDisconnectedLinesShowError() {
        let app = XCUIApplication()
        EditorLaunchSupport.launchNewTrip(app)
        pickStation(field: "newTripOrigin", query: "銀座", code: "003922", in: app)
        pickStation(field: "newTripDestination", query: "丸ノ内", code: "003390", in: app)

        let error = app.descendants(matching: .any)["newTripRouteError"]
        XCTAssertTrue(reveal(error, in: app, timeout: 20))
        XCTAssertTrue(error.label.contains("赤坂見附"), error.label)
        XCTAssertFalse(app.buttons["newTripSave"].isEnabled,
                       "A disconnected pair must not be savable.")
    }

    func testThroughServiceCorridorSavesWithPassStations() {
        let number = "Through \(UUID().uuidString.prefix(8))"
        let app = XCUIApplication()
        EditorLaunchSupport.launchNewTrip(app)
        pickStation(field: "newTripOrigin", query: "東横", code: "003922", in: app)
        pickStation(field: "newTripDestination", query: "みなとみらい", code: "004704", in: app)

        let corridor = app.buttons["newTripCorridor-0"]
        XCTAssertTrue(reveal(corridor, in: app, timeout: 20))
        let passes = app.buttons["newTripPassStations"]
        if !passes.exists { corridor.tap() }
        XCTAssertTrue(reveal(passes, in: app, timeout: 8))
        passes.tap()
        let yokohama = app.staticTexts.matching(NSPredicate(
            format: "label CONTAINS %@", "横浜")).firstMatch
        XCTAssertTrue(reveal(yokohama, in: app, timeout: 8),
                      "The through-service corridor must list 横浜.")
        // Collapse the long pass list so the number field, above the route, can be reached.
        passes.tap()

        typeNumber(number, in: app)
        let save = app.buttons["newTripSave"]
        XCTAssertTrue(waitForEnabled(save, timeout: 20))
        save.tap()
        XCTAssertTrue(save.waitForNonExistence(timeout: 20))

        let row = app.descendants(matching: .any).matching(NSPredicate(
            format: "identifier BEGINSWITH %@ AND label CONTAINS %@",
            "journeyRow-", number)).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 20),
                      "Saving a through-service corridor must insert a journey row.")
    }

    func testMultipleCorridorsRequireChoice() {
        let app = XCUIApplication()
        EditorLaunchSupport.launchNewTrip(app)
        // "東北" line-matches 東北新幹線 first. The two-corridor pair is conventional 東北線.
        pickStation(field: "newTripOrigin", query: "大宮", code: "002914",
                    lineID: "jp-東日本旅客鉄道-東北線", in: app)
        pickStation(field: "newTripDestination", query: "新木場", code: "003997",
                    lineID: "jp-東日本旅客鉄道-京葉線", in: app)

        XCTAssertTrue(reveal(app.buttons["newTripCorridor-1"], in: app, timeout: 40))
        let waiting = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            let save = app.buttons["newTripSave"]
            return app.buttons["newTripCorridor-1"].exists && save.exists && !save.isEnabled
        }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [waiting], timeout: 20), .completed,
                       "Several corridors must leave Save disabled until one is chosen.")

        XCTAssertTrue(reveal(app.buttons["newTripCorridor-1"], in: app))
        app.buttons["newTripCorridor-1"].tap()
        XCTAssertTrue(waitForEnabled(app.buttons["newTripSave"], timeout: 8),
                      "Choosing a corridor must enable Save.")
    }

    func testSwapExchangesStationsAndReplans() {
        let app = XCUIApplication()
        EditorLaunchSupport.launchNewTrip(app)
        pickStation(field: "newTripOrigin", query: "品川", code: "004095",
                    lineID: "jp-東日本旅客鉄道-山手線", in: app)
        pickStation(field: "newTripDestination", query: "大崎", code: "004135",
                    lineID: "jp-東日本旅客鉄道-山手線", in: app)
        XCTAssertTrue(waitUntilSavable(app), "The first route must become savable. \(routeState(app))")
        XCTAssertTrue(reveal(app.buttons["newTripCorridor-0"], in: app, timeout: 15))

        let origin = app.buttons["newTripOrigin"]
        let destination = app.buttons["newTripDestination"]
        XCTAssertTrue(reveal(origin, in: app, upward: true))
        let originBefore = origin.label
        let destinationBefore = destination.label
        XCTAssertTrue(originBefore.contains("品川"), originBefore)
        XCTAssertTrue(destinationBefore.contains("大崎"), destinationBefore)

        XCTAssertTrue(reveal(app.buttons["newTripSwap"], in: app, upward: true))
        app.buttons["newTripSwap"].tap()
        // Labels carry their row role ("From, …" / "To, …"); compare the station part.
        func station(_ label: String) -> Substring {
            label.split(separator: ",", maxSplits: 1).last ?? Substring(label)
        }
        XCTAssertEqual(station(origin.label), station(destinationBefore))
        XCTAssertEqual(station(destination.label), station(originBefore))

        XCTAssertTrue(waitUntilSavable(app), "Swapping the endpoints must plan the reversed route. \(routeState(app))")
        XCTAssertTrue(reveal(app.buttons["newTripCorridor-0"], in: app, timeout: 15))
    }

    func testArrivalBeforeDepartureBlocksSave() {
        let app = XCUIApplication()
        EditorLaunchSupport.launchNewTrip(app)
        pickStation(field: "newTripOrigin", query: "品川", code: "004095",
                    lineID: "jp-東日本旅客鉄道-山手線", in: app)
        pickStation(field: "newTripDestination", query: "大崎", code: "004135",
                    lineID: "jp-東日本旅客鉄道-山手線", in: app)
        let save = app.buttons["newTripSave"]
        XCTAssertTrue(waitUntilSavable(app), "Save must enable once the route is planned. \(routeState(app))")

        moveArrivalToPreviousDay(in: app)
        let error = app.staticTexts["Arrival is before departure."]
        XCTAssertTrue(reveal(error, in: app, timeout: 8))
        XCTAssertFalse(save.isEnabled, "An arrival before departure must block Save.")
    }

    func testSaveWithoutNumberUsesLineName() {
        let app = XCUIApplication()
        EditorLaunchSupport.launchNewTrip(app)
        pickStation(field: "newTripOrigin", query: "品川", code: "004095",
                    lineID: "jp-東日本旅客鉄道-山手線", in: app)
        pickStation(field: "newTripDestination", query: "大崎", code: "004135",
                    lineID: "jp-東日本旅客鉄道-山手線", in: app)
        let number = app.textFields["newTripNumber"]
        XCTAssertTrue(reveal(number, in: app, timeout: 8))
        let typed = number.value as? String ?? ""
        XCTAssertTrue(typed.isEmpty || typed == number.placeholderValue,
                      "The train number starts empty.")

        let save = app.buttons["newTripSave"]
        XCTAssertTrue(waitUntilSavable(app), "Save must enable once the route is planned. \(routeState(app))")
        save.tap()
        XCTAssertTrue(save.waitForNonExistence(timeout: 20))

        let row = app.descendants(matching: .any).matching(NSPredicate(
            format: "identifier BEGINSWITH %@ AND label CONTAINS %@",
            "journeyRow-", "山手")).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 20),
                      "An empty number must be saved as the corridor's line name.")
    }

    func testDraftSurvivesPhoneRotation() throws {
        try XCTSkipUnless(UIDevice.current.userInterfaceIdiom == .phone)
        XCUIDevice.shared.orientation = .portrait
        defer { XCUIDevice.shared.orientation = .portrait }

        let app = XCUIApplication()
        EditorLaunchSupport.launchNewTrip(app)
        pickStation(field: "newTripOrigin", query: "品川", code: "004095",
                    lineID: "jp-東日本旅客鉄道-山手線", in: app)
        pickStation(field: "newTripDestination", query: "大崎", code: "004135",
                    lineID: "jp-東日本旅客鉄道-山手線", in: app)
        typeNumber("Rotate 42", in: app)

        XCUIDevice.shared.orientation = .landscapeLeft
        let portraitLock = XCTNSPredicateExpectation(
            predicate: NSPredicate { object, _ in
                guard let window = object as? XCUIElement else { return false }
                return window.frame.height > window.frame.width
            },
            object: app.windows.firstMatch)
        XCTAssertEqual(XCTWaiter().wait(for: [portraitLock], timeout: 8), .completed,
                       "The iPhone new-trip screen must stay in portrait after a rotation request.")

        let origin = app.buttons["newTripOrigin"]
        let destination = app.buttons["newTripDestination"]
        XCTAssertTrue(reveal(origin, in: app, timeout: 8, upward: true))
        XCTAssertTrue(origin.label.contains("品川"), origin.label)
        XCTAssertTrue(destination.label.contains("大崎"), destination.label)
        let number = app.textFields["newTripNumber"]
        XCTAssertTrue(reveal(number, in: app, timeout: 8))
        XCTAssertEqual(number.value as? String, "Rotate 42",
                       "Rotation must retain the draft number.")
    }

    func testChineseAccessibilityXXXLHeaderButtonsStayTappable() {
        let app = XCUIApplication()
        app.launchArguments = [
            "-AppleLanguages", "(zh-Hans)",
            "-AppleLocale", "zh_CN",
            "-interface-language", "zh-Hans",
            "-UIPreferredContentSizeCategoryName",
            "UICTContentSizeCategoryAccessibilityXXXL",
        ]
        EditorLaunchSupport.launchNewTrip(app)
        pickStation(field: "newTripOrigin", query: "品川", code: "004095",
                    lineID: "jp-東日本旅客鉄道-山手線", in: app)
        pickStation(field: "newTripDestination", query: "大崎", code: "004135",
                    lineID: "jp-東日本旅客鉄道-山手線", in: app)

        let cancel = app.buttons["newTripCancel"]
        let save = app.buttons["newTripSave"]
        XCTAssertTrue(cancel.waitForExistence(timeout: 20))
        XCTAssertTrue(waitForEnabled(save, timeout: 20))
        XCTAssertEqual(cancel.label, "取消")
        XCTAssertEqual(save.label, "保存")
        XCTAssertLessThanOrEqual(cancel.frame.height, 100)
        XCTAssertLessThanOrEqual(save.frame.height, 100)
        XCTAssertTrue(app.frame.contains(cancel.frame))
        XCTAssertTrue(app.frame.contains(save.frame))
        XCTAssertTrue(cancel.isHittable)
        XCTAssertTrue(save.isHittable)
        cancel.tap()
        XCTAssertTrue(cancel.waitForNonExistence(timeout: 8),
                      "The header Cancel button must stay tappable at accessibility XXXL.")
    }

    func testCancelDoesNotSaveJourney() {
        let number = "Cancel \(UUID().uuidString.prefix(8))"
        let app = XCUIApplication()
        EditorLaunchSupport.launchNewTrip(app)
        pickStation(field: "newTripOrigin", query: "品川", code: "004095",
                    lineID: "jp-東日本旅客鉄道-山手線", in: app)
        pickStation(field: "newTripDestination", query: "大崎", code: "004135",
                    lineID: "jp-東日本旅客鉄道-山手線", in: app)
        typeNumber(number, in: app)
        XCTAssertTrue(waitUntilSavable(app),
                      "The draft must be saveable before Cancel is meaningful. \(routeState(app))")

        let cancel = app.buttons["newTripCancel"]
        cancel.tap()
        XCTAssertTrue(cancel.waitForNonExistence(timeout: 8))

        app.terminate()
        app.launchEnvironment["RAILMAP_UI_TEST_SHEET"] = ""
        app.launchEnvironment["RAILMAP_UI_TEST_TAB"] = "search"
        app.launchEnvironment["RAILMAP_UI_TEST_QUERY"] = number
        app.launch()
        let search = app.textFields["journeySearchField"]
        XCTAssertTrue(search.waitForExistence(timeout: 30))
        let row = app.descendants(matching: .any).matching(NSPredicate(
            format: "identifier BEGINSWITH %@ AND label CONTAINS %@",
            "journeyRow-", number)).firstMatch
        XCTAssertFalse(row.waitForExistence(timeout: 8),
                       "Cancel must close the new trip without writing a journey.")
    }

    private func stationRows(in app: XCUIApplication) -> XCUIElementQuery {
        app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'newTripStation-'"))
    }

    private func pickStation(
        field: String, query: String, code: String, lineID: String? = nil, in app: XCUIApplication
    ) {
        let button = app.buttons[field]
        XCTAssertTrue(button.waitForExistence(timeout: 20))
        XCTAssertTrue(waitForEnabled(button, timeout: 20), "\(field) stays disabled until the catalog loads.")
        button.tap()
        let search = app.searchFields.firstMatch
        XCTAssertTrue(search.waitForExistence(timeout: 20))
        replaceSearch(search, with: query, in: app)
        // A name query keeps that station's rows near the top. The line id
        // distinguishes shared station codes (山手線 vs 神戸市-山手線, 東北線 vs 東北新幹線).
        let row = stationRows(in: app).matching(NSPredicate(
            format: lineID == nil ? "identifier ENDSWITH %@" : "identifier == %@",
            lineID.map { "newTripStation-\($0)-\(code)" } ?? "-\(code)")).firstMatch
        XCTAssertTrue(stationRows(in: app).firstMatch.waitForExistence(timeout: 20),
                      "\(query) must list station rows.")
        // Results are a lazy list in line order: a station deep in a long line
        // only gets an accessibility element once it is scrolled on screen.
        var swipes = 0
        while !row.waitForExistence(timeout: swipes == 0 ? 3 : 0.5), swipes < 40 {
            let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.55))
            start.press(forDuration: 0.05,
                        thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.2)))
            swipes += 1
        }
        XCTAssertTrue(row.exists, "No newTripStation row ending in \(code) for \(query).")
        let previousLabel = button.label
        // A tap while the search keyboard is up resigns the field and leaves the
        // sheet open, so the station is never chosen. Resign first, then tap.
        dismissSearchKeyboard(in: app)
        if row.exists, !row.isHittable {
            app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.55))
                .press(forDuration: 0.05,
                       thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.35)))
        }
        row.tap()
        if app.searchFields.firstMatch.exists {
            dismissSearchKeyboard(in: app)
            if row.waitForExistence(timeout: 2) { row.tap() }
        }
        XCTAssertTrue(
            app.searchFields.firstMatch.waitForNonExistence(timeout: 5),
            "Choosing \(query) must close station search.")
        let chosen = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "label != %@", previousLabel),
            object: button)
        XCTAssertEqual(XCTWaiter.wait(for: [chosen], timeout: 8), .completed, button.label)
    }

    private func replaceSearch(_ search: XCUIElement, with text: String, in app: XCUIApplication) {
        search.tap()
        if let value = search.value as? String, !value.isEmpty, value != search.placeholderValue {
            search.press(forDuration: 1.1)
            let selectAll = app.menuItems["Select All"].firstMatch
            let selectAllButton = app.buttons["Select All"].firstMatch
            if selectAllButton.waitForExistence(timeout: 2) {
                selectAllButton.tap()
            } else if selectAll.waitForExistence(timeout: 2) {
                selectAll.tap()
            }
            search.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: value.count))
        }
        search.typeText(text)
    }

    private func typeNumber(_ value: String, in app: XCUIApplication) {
        let field = app.textFields["newTripNumber"]
        // Service fields sit above the route. After a long pass-station list
        // the number is off the top, so look down first and then back up.
        let visible = reveal(field, in: app, timeout: 8)
            || reveal(field, in: app, timeout: 16, upward: true)
        XCTAssertTrue(visible, "Train number must scroll into the form.")
        XCTAssertTrue(
            focusField(field, in: app),
            "The train number field must take keyboard focus. "
                + "frame=\(field.frame) hittable=\(field.isHittable) "
                + "keyboard=\(app.keyboards.firstMatch.exists)")
        field.typeText(value + "\n")
    }

    /// A leftover search keyboard covers this field, so `isHittable` stays false
    /// and a coordinate tap does not move focus. Dismiss that keyboard, then
    /// `tap()` once the field sits in the open part of the form.
    private func focusField(_ field: XCUIElement, in app: XCUIApplication) -> Bool {
        closeStationSearch(in: app)
        for step in 0..<10 {
            if field.exists, field.isHittable, clearOfKeyboard(field, in: app) {
                field.tap()
                let focused = XCTNSPredicateExpectation(
                    predicate: NSPredicate(format: "hasKeyboardFocus == true"), object: field)
                if XCTWaiter.wait(for: [focused], timeout: 2) == .completed { return true }
            } else if field.exists {
                // At its resting y≈560 the field has a frame but is not hittable.
                // The same field accepts a tap near y≈330. Move it up into that band.
                let keyboard = app.keyboards.firstMatch
                let ceiling: CGFloat = keyboard.exists ? keyboard.frame.minY - 40 : 430
                if field.frame.midY > ceiling {
                    nudgeForm(in: app, up: false, span: 0.28)
                } else if field.frame.midY < 200 {
                    nudgeForm(in: app, up: true, span: 0.18)
                } else {
                    nudgeForm(in: app, up: false, span: 0.12)
                }
            } else {
                nudgeForm(in: app, up: step < 5)
            }
        }
        return false
    }

    /// Resign the station-search keyboard without leaving the sheet up.
    /// Tapping its Search key keeps the result rows and lets the next row tap select.
    private func dismissSearchKeyboard(in app: XCUIApplication) {
        let keyboard = app.keyboards.firstMatch
        guard keyboard.exists else { return }
        for label in ["Search", "検索"] {
            let key = keyboard.buttons[label]
            if key.exists {
                key.tap()
                break
            }
        }
        _ = keyboard.waitForNonExistence(timeout: 2)
    }

    /// The station sheet is already closed. A leftover keyboard still covers the form.
    private func closeStationSearch(in app: XCUIApplication) {
        guard !app.searchFields.firstMatch.exists else { return }
        let keyboard = app.keyboards.firstMatch
        guard keyboard.exists else { return }
        for label in ["Return", "Done", "Search", "検索"] {
            let key = keyboard.buttons[label]
            if key.exists {
                key.tap()
                break
            }
        }
        _ = keyboard.waitForNonExistence(timeout: 2)
    }

    private func clearOfKeyboard(_ element: XCUIElement, in app: XCUIApplication) -> Bool {
        let frame = element.frame
        guard frame.width > 1, frame.height > 1 else { return false }
        var band = app.frame.insetBy(dx: 8, dy: 0)
        band.origin.y = 140
        let keyboard = app.keyboards.firstMatch
        let limit = keyboard.exists ? keyboard.frame.minY - 12 : app.frame.maxY - 40
        band.size.height = limit - band.origin.y
        guard band.height > 40 else { return false }
        return band.contains(frame)
    }

    private func moveArrivalToPreviousDay(in app: XCUIApplication) {
        let arrival = app.datePickers["newTripArrival"]
        XCTAssertTrue(reveal(arrival, in: app, timeout: 8))
        let dateButton = arrival.buttons.firstMatch
        if dateButton.exists { dateButton.tap() } else { arrival.tap() }

        let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: Date())!
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US")
        formatter.dateFormat = "EEEE, MMMM d"
        let named = app.buttons[formatter.string(from: yesterday)]
        if named.waitForExistence(timeout: 5) {
            named.tap()
        } else {
            let day = String(Calendar.current.component(.day, from: yesterday))
            let byNumber = app.buttons[day].firstMatch
            XCTAssertTrue(byNumber.waitForExistence(timeout: 5),
                          "The arrival calendar must offer yesterday.")
            byNumber.tap()
        }
        if app.buttons["PopoverDismissRegion"].exists {
            app.buttons["PopoverDismissRegion"].tap()
        }
    }

    /// A loop such as 山手線 keeps both directions, so Save stays disabled until
    /// one corridor is tapped. Those rows are lazy and sit under the service
    /// fields. A single corridor is selected by the form itself.
    private func waitUntilSavable(_ app: XCUIApplication, timeout: TimeInterval = 50) -> Bool {
        let save = app.buttons["newTripSave"]
        if waitForEnabled(save, timeout: 5) { return true }
        let first = app.buttons["newTripCorridor-0"]
        let deadline = Date().addingTimeInterval(min(35, timeout))
        while Date() < deadline {
            if save.isEnabled { return true }
            if app.descendants(matching: .any)["newTripRouteError"].exists { return false }
            if first.exists, first.isHittable {
                // Two corridors leave Save disabled. One that is already
                // selected enables it before this tap.
                if !save.isEnabled { first.tap() }
                if waitForEnabled(save, timeout: 6) { return true }
            }
            nudgeForm(in: app, up: false)
        }
        return save.isEnabled
    }

    private func routeState(_ app: XCUIApplication) -> String {
        let error = app.descendants(matching: .any)["newTripRouteError"]
        return "saveEnabled=\(app.buttons["newTripSave"].isEnabled) "
            + "corridor0=\(app.buttons["newTripCorridor-0"].exists) "
            + "corridor1=\(app.buttons["newTripCorridor-1"].exists) "
            + "error=\(error.exists ? error.label : "-") "
            + "searching=\(app.staticTexts["Searching routes"].exists)"
    }

    private func formList(in app: XCUIApplication) -> XCUIElement {
        // newTripSave is in the header, outside the form. A station-search sheet
        // is a taller collection view; scrolling that never reaches the route.
        let lists = app.collectionViews.allElementsBoundByIndex.filter {
            $0.frame.height > 160 && !$0.searchFields.firstMatch.exists
        }
        return lists.max(by: { $0.frame.height < $1.frame.height }) ?? app.collectionViews.firstMatch
    }

    /// A downward swipe from the sheet edge collapses New Trip to a bottom detent.
    private func expandSheetIfNeeded(in app: XCUIApplication) {
        let save = app.buttons["newTripSave"]
        guard save.exists, save.frame.minY > 180 else { return }
        let handle = app.coordinate(withNormalizedOffset: CGVector(
            dx: 0.5, dy: max(0.1, (save.frame.midY - 8) / app.frame.height)))
        handle.press(forDuration: 0.05,
                     thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.12)))
    }

    private func nudgeForm(in app: XCUIApplication, up: Bool, span: CGFloat = 0.40) {
        expandSheetIfNeeded(in: app)
        let form = formList(in: app)
        guard form.exists, form.frame.height > 80 else { return }
        let travel = min(0.40, max(0.12, span))
        let startY: CGFloat = up ? 0.42 : 0.78
        let endY: CGFloat = up ? 0.42 + travel : 0.78 - travel
        let start = form.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: startY))
        let end = form.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: endY))
        start.press(forDuration: 0.05, thenDragTo: end)
    }

    private func frameInBand(_ element: XCUIElement, in app: XCUIApplication) -> Bool {
        let frame = element.frame
        guard frame.width > 1, frame.height > 1 else { return false }
        return app.frame.insetBy(dx: 0, dy: 120).contains(frame)
    }

    @discardableResult
    private func reveal(
        _ element: XCUIElement, in app: XCUIApplication,
        timeout: TimeInterval = 20, upward: Bool = false
    ) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        var searchUp = upward
        var streak = 0
        if element.waitForExistence(timeout: min(2, max(0, timeout))), revealed(element, in: app) {
            return true
        }
        while Date() < deadline {
            if element.exists {
                if revealed(element, in: app) { return true }
                searchUp = element.frame.midY < app.frame.midY
                streak = 0
            } else if streak >= 8 {
                // Keep one direction long enough to cross the form.
                // Toggling every swipe walks back to the start.
                searchUp.toggle()
                streak = 0
            }
            nudgeForm(in: app, up: searchUp)
            streak += 1
            let visible = XCTNSPredicateExpectation(
                predicate: NSPredicate { _, _ in self.revealed(element, in: app) }, object: nil)
            if XCTWaiter.wait(for: [visible], timeout: min(0.5, max(0, deadline.timeIntervalSinceNow))) == .completed {
                return true
            }
        }
        return revealed(element, in: app)
    }

    /// Form text fields report a frame but `isHittable` stays false.
    private func revealed(_ element: XCUIElement, in app: XCUIApplication) -> Bool {
        guard element.exists else { return false }
        if element.elementType == .textField { return frameInBand(element, in: app) }
        return element.isHittable
    }

    @discardableResult
    private func waitForEnabled(_ element: XCUIElement, timeout: TimeInterval) -> Bool {
        let enabled = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "enabled == true"), object: element)
        return XCTWaiter.wait(for: [enabled], timeout: timeout) == .completed
    }
}
