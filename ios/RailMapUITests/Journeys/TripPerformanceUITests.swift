import RailPresentation
import XCTest

/// Performance of every trip operation against the full example-trip store
/// (about 290 rides: all bundled `RideLibrary.Sample` resources).
///
/// Every test uses its own `RAILMAP_UI_TEST_STORAGE_ID`, so the real store is
/// never touched. Each result is also printed as `PERF <name> <ms>` so a run
/// can be summarised with `grep PERF` on the xcodebuild log.
///
/// `measure` may run the block once more than `iterationCount` (a warm-up
/// that is discarded). Every block is therefore repeatable: it either starts
/// from a fresh relaunch of a persisted store or leaves the UI as it found it.
/// Time spent in setup is excluded with `startMeasuring()`/`stopMeasuring()`.
/// Polling adds up to roughly 0.1 to 0.3 s of resolution to manual timings.
@MainActor
final class TripPerformanceUITests: XCTestCase {

    // MARK: Fixture

    /// Every bundled sample, merged into the store: about 290 rides.
    private static let allSamples = [
        "train-store", "new-year-grand-loop", "tokyo-limited-express-loop",
        "train-store-tw", "train-store-hk", "train-store-mo", "train-store-kr",
    ].joined(separator: ",")

    /// Fewer than this registered rides means the samples did not all merge.
    private static let minimumRides = 250

    private static let subsystem = "com.jtm.railmap"

    override func setUp() async throws {
        try await super.setUp()
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
    }

    // MARK: 1. Cold load

    /// Fresh store, empty route cache: launch, merge every sample, solve and
    /// draw all trips (until the load-complete inventory reads `loaded`).
    func testPerf01ColdLoad() {
        let app = XCUIApplication()
        let options = XCTMeasureOptions()
        options.iterationCount = 1
        options.invocationOptions = [.manuallyStart, .manuallyStop]
        measure(metrics: metrics(app, [
            ("data", "route.cacheRead"), ("map", "map.rebuild"),
            ("data", "data.edgeIndex.build"), ("data", "data.displayNetwork.build"),
        ]), options: options) {
            configure(app, storage: UUID().uuidString, sample: Self.allSamples)
            let watch = Stopwatch()
            startMeasuring()
            UITestLaunchSupport.launch(app)
            let state = waitForLoad(app)
            stopMeasuring()
            watch.report("coldLoad")
            note("coldLoad registered=\(state.registered) drawable=\(state.drawable)")
            app.terminate()
        }
    }

    // MARK: 2. Warm relaunch

    /// The same store with its route cache warm: relaunch until all trips are drawn.
    func testPerf02WarmRelaunch() {
        let storage = seedStore()
        let app = XCUIApplication()
        let options = XCTMeasureOptions()
        options.iterationCount = 3
        options.invocationOptions = [.manuallyStart, .manuallyStop]
        measure(metrics: metrics(app, [
            ("data", "route.cacheRead"), ("map", "map.rebuild"),
            ("data", "data.edgeIndex.build"), ("data", "data.displayNetwork.build"),
        ]), options: options) {
            configure(app, storage: storage, sample: "")
            let watch = Stopwatch()
            startMeasuring()
            UITestLaunchSupport.launch(app)
            let state = waitForLoad(app)
            stopMeasuring()
            watch.report("warmRelaunch")
            note("warmRelaunch registered=\(state.registered) drawable=\(state.drawable)")
            app.terminate()
        }
    }

    // MARK: 3. Repair routes

    /// The data manager, Repair routes, confirm, until the row is enabled
    /// again. A repair reads cached routes back and can finish before its
    /// progress row shows, so progress is not asserted. XCTMemoryMetric reports
    /// the peak.
    func testPerf03ReloadAll() {
        let app = seededApp()
        defer { app.terminate() }
        openReloadRow(in: app)
        let options = XCTMeasureOptions()
        options.iterationCount = 1
        options.invocationOptions = [.manuallyStart, .manuallyStop]
        measure(metrics: metrics(app, [
            ("data", "route.cacheRead"), ("map", "map.rebuild"),
            ("data", "data.edgeIndex.build"),
        ]), options: options) {
            let button = app.buttons["reloadAllButton"]
            let enabled = expectation(for: NSPredicate(format: "isEnabled == true"), evaluatedWith: button)
            wait(for: [enabled], timeout: 60)
            let watch = Stopwatch()
            startMeasuring()
            button.tap()
            let confirm = app.buttons["reloadAllConfirm"].firstMatch
            XCTAssertTrue(confirm.waitForExistence(timeout: 8))
            confirm.tap()
            XCTAssertTrue(button.waitForExistence(timeout: 900), "Repair did not finish.")
            let finished = expectation(for: NSPredicate(format: "exists == true AND isEnabled == true"), evaluatedWith: button)
            wait(for: [finished], timeout: 900)
            stopMeasuring()
            watch.report("reloadAll")
        }
    }

    // MARK: 4. Tap a trip

    /// Tap a trip row in the list until the selected-trip card is shown (the
    /// select latency), then return to the list.
    func testPerf04SelectTrip() {
        let app = seededApp()
        defer { app.terminate() }
        let options = XCTMeasureOptions()
        options.iterationCount = 3
        options.invocationOptions = [.manuallyStart, .manuallyStop]
        measure(metrics: metrics(app, [
            ("map", "map.tap"), ("map", "map.selection"),
            ("map", "map.selection.overlays"), ("map", "map.selection.markers"),
        ]), options: options) {
            returnToList(app)
            let row = tripRow(0, in: app)
            XCTAssertTrue(row.waitForExistence(timeout: 30))
            let watch = Stopwatch()
            startMeasuring()
            row.tap()
            XCTAssertTrue(selectedCard(in: app).waitForExistence(timeout: 30), "Selected-trip card never appeared.")
            stopMeasuring()
            watch.report("selectTrip")
        }
    }

    // MARK: 5. Focus a trip

    /// Locate route on a selected trip until the camera has settled; then the
    /// same on another trip; then again on the same trip after the camera was
    /// moved away. Auto-focus on selection is off so Locate is the only fit.
    func testPerf05FocusTrip() {
        let app = seededApp(autoFocus: false)
        defer { app.terminate() }
        let options = XCTMeasureOptions()
        options.iterationCount = 3
        options.invocationOptions = [.manuallyStart, .manuallyStop]
        measure(metrics: metrics(app, [("map", "map.selection"), ("map", "map.rebuild")]), options: options) {
            returnToList(app)
            XCTAssertTrue(tripRow(0, in: app).waitForExistence(timeout: 30))
            tripRow(0, in: app).tap()
            XCTAssertTrue(selectedCard(in: app).waitForExistence(timeout: 30))
            focusAndSettle(app, name: "focusFirst")

            returnToList(app)
            XCTAssertTrue(tripRow(1, in: app).waitForExistence(timeout: 30))
            tripRow(1, in: app).tap()
            XCTAssertTrue(selectedCard(in: app).waitForExistence(timeout: 30))
            focusAndSettle(app, name: "refocusOther")

            nudgeCamera(app)
            focusAndSettle(app, name: "refocusSame")
        }
    }

    // MARK: 6. Open a saved trip in the editor

    /// Selected trip, Edit: until the editor shows its saved route.
    func testPerf06OpenEditor() {
        let app = seededApp()
        defer { app.terminate() }
        let options = XCTMeasureOptions()
        options.iterationCount = 3
        options.invocationOptions = [.manuallyStart, .manuallyStop]
        measure(metrics: metrics(app, [("map", "map.rebuild")]), options: options) {
            selectFirstTrip(app)
            let watch = Stopwatch()
            startMeasuring()
            tapEdit(app)
            XCTAssertTrue(editorReady(app), "Editor never showed the saved route.")
            stopMeasuring()
            watch.report("openEditor")
            cancelEditor(app)
        }
    }

    // MARK: 7. Edit and save

    /// Edit a saved trip by swapping its two ends (the one edit that needs no
    /// station knowledge): time until the route is planned again, then Save
    /// until the editor closes and the map has rebuilt with the edited trip.
    /// Changing a line choice or adding a via stop needs per-trip station
    /// data, so those variants are not driven here.
    func testPerf07EditAndSave() {
        let app = seededApp()
        defer { app.terminate() }
        let options = XCTMeasureOptions()
        options.iterationCount = 3
        options.invocationOptions = [.manuallyStart, .manuallyStop]
        measure(metrics: metrics(app, [
            ("map", "map.rebuild"), ("data", "route.cacheRead"), ("map", "map.selection"),
        ]), options: options) {
            selectFirstTrip(app)
            tapEdit(app)
            XCTAssertTrue(editorReady(app), "Editor never showed the saved route.")
            let swap = app.buttons["newTripSwap"]
            XCTAssertTrue(EditorUITestSupport.reveal(swap, in: app, unmountedRowIsAbove: true),
                          "newTripSwap not reachable. \(app.debugDescription)")
            let rebuildsBefore = renderField("rebuilds", app)
            let total = Stopwatch()
            let replan = Stopwatch()
            startMeasuring()
            swap.tap()
            XCTAssertTrue(waitUntilSavable(app), "Swapped route never became savable.")
            replan.report("editReplan")
            let save = Stopwatch()
            app.buttons["newTripSave"].tap()
            XCTAssertTrue(app.buttons["newTripSave"].waitForNonExistence(timeout: 60), "Editor did not close.")
            wait(timeout: 60) { renderField("rebuilds", app) > rebuildsBefore }
            stopMeasuring()
            save.report("editSaveToMap")
            total.report("editTotal")
            returnToList(app)
        }
    }

    // MARK: 8. Add a new trip

    /// New trip, pick two stations by search on the Tokyu Toyoko / Minatomirai
    /// through-service pair: until the route shows live and its pass-through
    /// stations are auto-filled. Each iteration relaunches the persisted store
    /// with the new-trip sheet open, then saves and waits for the trip to draw.
    func testPerf08aAddTripPassThroughAutoFill() {
        let storage = seedStore()
        let app = XCUIApplication()
        let options = XCTMeasureOptions()
        options.iterationCount = 3
        options.invocationOptions = [.manuallyStart, .manuallyStop]
        measure(metrics: metrics(app, [
            ("map", "map.rebuild"), ("data", "route.cacheRead"),
        ]), options: options) {
            let baseline = launchNewTrip(app, storage: storage)
            pickStation(field: "newTripOrigin", query: "東横", code: "003922", lineID: nil, in: app)
            let route = Stopwatch()
            startMeasuring()
            pickStation(field: "newTripDestination", query: "みなとみらい", code: "004704", lineID: nil, in: app)
            let live = waitUntilSavable(app) || app.buttons["newTripCorridor-0"].waitForExistence(timeout: 60)
            XCTAssertTrue(live, "Route never showed live.")
            route.report("addTripRouteLive")
            let passes = app.buttons["newTripPassStations"]
            if !passes.exists, app.buttons["newTripCorridor-0"].exists { app.buttons["newTripCorridor-0"].tap() }
            let filled = EditorUITestSupport.reveal(passes, in: app, unmountedRowIsAbove: false)
            route.report("addTripPassThroughFilled")
            XCTAssertTrue(filled, "Pass-through stations were not auto-filled.")
            XCTAssertTrue(waitUntilSavable(app))
            let save = Stopwatch()
            app.buttons["newTripSave"].tap()
            XCTAssertTrue(app.buttons["newTripSave"].waitForNonExistence(timeout: 60))
            waitForTripDrawn(app, baseline: baseline)
            stopMeasuring()
            save.report("addTripSaveToDrawn")
            app.terminate()
        }
    }

    /// New trip on the Osaka Loop pair (two directions, so two routes): until
    /// both routes show, choose the second route to enable Save, then Save
    /// until the new trip is drawn. Same relaunch-per-iteration scheme as 8a.
    func testPerf08bAddTripResolveMultiRoute() {
        let storage = seedStore()
        let app = XCUIApplication()
        let loop = "jp-西日本旅客鉄道-大阪環状線"
        let options = XCTMeasureOptions()
        options.iterationCount = 3
        options.invocationOptions = [.manuallyStart, .manuallyStop]
        measure(metrics: metrics(app, [
            ("map", "map.rebuild"), ("data", "route.cacheRead"),
        ]), options: options) {
            let baseline = launchNewTrip(app, storage: storage)
            pickStation(field: "newTripOrigin", query: "大阪", code: "007068", lineID: loop, in: app)
            let route = Stopwatch()
            startMeasuring()
            pickStation(field: "newTripDestination", query: "天王寺", code: "007439", lineID: loop, in: app)
            let second = app.buttons["newTripCorridor-1"]
            XCTAssertTrue(EditorUITestSupport.reveal(second, in: app, unmountedRowIsAbove: false),
                          "The pair did not produce two routes. \(app.debugDescription)")
            route.report("addTripMultiRouteLive")
            let resolve = Stopwatch()
            second.tap()
            let save = app.buttons["newTripSave"]
            let enabled = expectation(for: NSPredicate(format: "isEnabled == true"), evaluatedWith: save)
            wait(for: [enabled], timeout: 30)
            resolve.report("addTripResolveRoute")
            let saving = Stopwatch()
            save.tap()
            XCTAssertTrue(save.waitForNonExistence(timeout: 60))
            waitForTripDrawn(app, baseline: baseline)
            stopMeasuring()
            saving.report("addTripMultiRouteSaveToDrawn")
            app.terminate()
        }
    }

    // MARK: 9. Delete a trip

    /// Swipe the first trip row, Delete, confirm: until it leaves the list and
    /// the registered count drops (the map is rebuilt without it).
    func testPerf09DeleteTrip() {
        let app = seededApp()
        defer { app.terminate() }
        let options = XCTMeasureOptions()
        options.iterationCount = 3
        options.invocationOptions = [.manuallyStart, .manuallyStop]
        measure(metrics: metrics(app, [("map", "map.rebuild"), ("ui", "itinerary.group")]), options: options) {
            returnToList(app)
            let row = tripRow(0, in: app)
            XCTAssertTrue(row.waitForExistence(timeout: 30))
            let id = row.identifier
            let before = inventory(app)
            row.swipeLeft()
            let swipeDelete = app.buttons.matching(NSPredicate(format: "label == 'Delete'")).firstMatch
            XCTAssertTrue(swipeDelete.waitForExistence(timeout: 8), "Swipe action Delete not shown.")
            swipeDelete.tap()
            let confirm = app.buttons.matching(NSPredicate(format: "label == 'Delete'")).firstMatch
            XCTAssertTrue(confirm.waitForExistence(timeout: 8), "Delete confirmation not shown.")
            let watch = Stopwatch()
            startMeasuring()
            confirm.tap()
            XCTAssertTrue(any(id, in: app).waitForNonExistence(timeout: 60), "Deleted trip is still listed.")
            if let before {
                wait(timeout: 60) { (inventory(app)?.registered ?? before.registered) < before.registered }
            }
            stopMeasuring()
            watch.report("deleteTrip")
        }
    }

    // MARK: 10. Statistics

    /// Open the Stats tab for the first time after a launch (relaunch of the
    /// persisted store each iteration), then leave and open it a second time.
    /// The metrics cover the first open; the second is timed by hand.
    func testPerf10Statistics() {
        let storage = seedStore()
        let app = XCUIApplication()
        let options = XCTMeasureOptions()
        options.iterationCount = 3
        options.invocationOptions = [.manuallyStart, .manuallyStop]
        measure(metrics: metrics(app, [
            ("jobs", "stats.load"), ("jobs", "stats.readNetwork"), ("jobs", "stats.matchRides"),
            ("jobs", "stats.aggregate"), ("jobs", "stats.group"), ("data", "data.displayNetwork.build"),
        ]), options: options) {
            configure(app, storage: storage, sample: "")
            UITestLaunchSupport.launch(app)
            _ = waitForLoad(app)
            let tabs = app.tabBars.firstMatch
            XCTAssertTrue(tabs.waitForExistence(timeout: 20))
            let first = Stopwatch()
            startMeasuring()
            tabs.buttons.element(boundBy: 2).tap() // Stats
            waitForStatistics(app)
            stopMeasuring()
            first.report("statsFirstOpen")
            tabs.buttons.element(boundBy: 1).tap() // History
            XCTAssertTrue(tripRow(0, in: app).waitForExistence(timeout: 30))
            let second = Stopwatch()
            tabs.buttons.element(boundBy: 2).tap()
            waitForStatistics(app)
            second.report("statsSecondOpen")
            app.terminate()
        }
    }

    // MARK: 11. Hide and unhide trips

    /// Hide trips by country (region) and by year through the filter's Hide
    /// trips sheet, then unhide: until the drawable trip count on the map
    /// changes. Notes whether the 500-trip cap notice is shown (it is not at
    /// about 290 rides).
    func testPerf11HideAndUnhideTrips() {
        let app = seededApp()
        defer { app.terminate() }
        for prefix in ["tripHideRegion-", "tripHideYear-"] {
            let label = prefix == "tripHideRegion-" ? "Country" : "Year"
            let options = XCTMeasureOptions()
            options.iterationCount = 3
            options.invocationOptions = [.manuallyStart, .manuallyStop]
            guard openHideSheet(app), hideToggle(prefix, in: app).waitForExistence(timeout: 10) else {
                note("hide\(label) skipped: no \(prefix)* toggle")
                dismissHideSheet(app)
                continue
            }
            dismissHideSheet(app)
            measure(metrics: metrics(app, [("map", "map.rebuild"), ("ui", "itinerary.group")]), options: options) {
                XCTAssertTrue(openHideSheet(app))
                let before = inventory(app)?.drawable ?? -1
                let toggle = hideToggle(prefix, in: app)
                XCTAssertTrue(toggle.waitForExistence(timeout: 10))
                let hide = Stopwatch()
                startMeasuring()
                toggle.tap()
                let changed = wait(timeout: 60) { (inventory(app)?.drawable ?? before) != before }
                stopMeasuring()
                hide.report("hide\(label)")
                if !changed { note("hide\(label) drawable count did not change (before=\(before))") }
                // Unhide, untimed by the metrics; timed by hand.
                let unhide = Stopwatch()
                toggle.tap()
                wait(timeout: 60) { (inventory(app)?.drawable ?? -2) == before }
                unhide.report("unhide\(label)")
                dismissHideSheet(app)
            }
        }
        let cap = any("mapTripCapNotice", in: app)
        note("mapTripCapNotice exists=\(cap.waitForExistence(timeout: 2)) registered=\(inventory(app)?.registered ?? -1)")
    }

    // MARK: - Launch helpers

    private func configure(_ app: XCUIApplication, storage: String, sample: String,
                           tab: String = "all", autoFocus: Bool = true) {
        app.launchArguments = ["-AppleLanguages", "(en)", "-AppleLocale", "en_US",
                               "-interface-language", "en",
                               "-auto-focus-zoom", autoFocus ? "YES" : "NO"]
        app.uiTestLaunch[.storageId] = storage
        app.uiTestLaunch[.sample] = sample
        app.uiTestLaunch[.tab] = tab
        app.uiTestLaunch[.stage] = "expanded"
        app.uiTestLaunch[.journeyInventory] = "1"
        app.uiTestLaunch[.gestureTarget] = "1"
        app.uiTestLaunch[.sheet] = ""
    }

    /// Launch with every sample on a fresh store and wait until all are drawn.
    private func seededApp(autoFocus: Bool = true) -> XCUIApplication {
        let app = XCUIApplication()
        configure(app, storage: UUID().uuidString, sample: Self.allSamples, autoFocus: autoFocus)
        UITestLaunchSupport.launch(app)
        _ = waitForLoad(app)
        return app
    }

    /// Fill a fresh persisted store (route cache included), then quit.
    private func seedStore() -> String {
        let storage = UUID().uuidString
        let app = XCUIApplication()
        configure(app, storage: storage, sample: Self.allSamples)
        UITestLaunchSupport.launch(app)
        _ = waitForLoad(app)
        // The store write is asynchronous.
        Thread.sleep(forTimeInterval: 2)
        app.terminate()
        return storage
    }

    /// Relaunch the persisted store with the new-trip sheet open. Returns the
    /// inventory before the trip is added, when the map reports one.
    private func launchNewTrip(_ app: XCUIApplication, storage: String) -> Inventory? {
        app.launchArguments = ["-AppleLanguages", "(en)", "-AppleLocale", "en_US", "-interface-language", "en"]
        let key = UITestLaunchConfiguration.Key.self
        EditorLaunchSupport.launchNewTrip(app, environment: [
            key.storageId.rawValue: storage,
            key.sample.rawValue: "",
            key.journeyInventory.rawValue: "1",
        ])
        XCTAssertTrue(app.buttons["newTripSave"].waitForExistence(timeout: 60))
        // The inventory lives on the map behind the sheet: use it when it is exposed.
        if app.staticTexts["journeyLoadInventory"].waitForExistence(timeout: 30) {
            return waitForLoad(app, timeout: 300)
        }
        note("journeyLoadInventory not exposed behind the new-trip sheet; save completion uses sheet dismissal only")
        return nil
    }

    // MARK: - Inventory and waits

    private struct Inventory {
        var registered: Int
        var phase: String
        var drawable: Int
    }

    private func inventory(_ app: XCUIApplication) -> Inventory? {
        let element = app.staticTexts["journeyLoadInventory"]
        guard element.exists else { return nil }
        let fields = Self.fields(element.label)
        guard let phase = fields["phase"] else { return nil }
        return Inventory(registered: Int(fields["registered"] ?? "") ?? 0,
                         phase: phase, drawable: Int(fields["drawable"] ?? "") ?? 0)
    }

    /// All samples registered, routes loaded, and the figures steady for ~4 s (16 polls; a warm load takes ~40 s).
    @discardableResult
    private func waitForLoad(_ app: XCUIApplication, timeout: TimeInterval = 900) -> Inventory {
        XCTAssertTrue(app.staticTexts["journeyLoadInventory"].waitForExistence(timeout: 120),
                      "journeyLoadInventory never appeared (RAILMAP_UI_TEST_JOURNEY_INVENTORY).")
        var last: Inventory?
        var steady = 0
        let done = wait(timeout: timeout, poll: 0.25) {
            guard let now = inventory(app), now.phase == "loaded",
                  now.registered >= Self.minimumRides, now.drawable > 0 else { steady = 0; return false }
            if let last, last.registered == now.registered, last.drawable == now.drawable { steady += 1 }
            else { steady = 0 }
            last = now
            return steady >= 16   // ~4 s unchanged: a warm load takes ~40 s and the figures pause between batches
        }
        XCTAssertTrue(done, "Trips did not finish loading: \(app.staticTexts["journeyLoadInventory"].label)")
        return last ?? Inventory(registered: 0, phase: "", drawable: 0)
    }

    /// After a save: one more registered trip, loaded, and one more drawn.
    private func waitForTripDrawn(_ app: XCUIApplication, baseline: Inventory?) {
        guard let baseline else { return }
        let drawn = wait(timeout: 120, poll: 0.1) {
            guard let now = inventory(app) else { return false }
            return now.registered > baseline.registered && now.phase == "loaded"
                && now.drawable > baseline.drawable
        }
        if !drawn { note("saved trip not reported drawn: \(app.staticTexts["journeyLoadInventory"].label)") }
    }

    private func renderField(_ key: String, _ app: XCUIApplication) -> Double {
        let status = app.staticTexts["railMapRenderStatus"]
        guard status.exists, let value = Self.fields(status.label)[key], let number = Double(value) else { return -1 }
        return number
    }

    @discardableResult
    private func wait(timeout: TimeInterval, poll: TimeInterval = 0.1, _ condition: () -> Bool) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if condition() { return true }
            RunLoop.current.run(until: Date().addingTimeInterval(poll))
        }
        return condition()
    }

    private static func fields(_ text: String) -> [String: String] {
        Dictionary(text.split(separator: ";").compactMap { field in
            let pair = field.split(separator: ":", maxSplits: 1)
            return pair.count == 2 ? (String(pair[0]), String(pair[1])) : nil
        }, uniquingKeysWith: { _, last in last })
    }

    // MARK: - Element helpers

    private func any(_ id: String, in app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any)[id].firstMatch
    }

    private func tripRow(_ index: Int, in app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier BEGINSWITH %@", "journeyRow-"))
            .element(boundBy: index)
    }

    private func selectedCard(in app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier BEGINSWITH %@", "selectedJourney-")).firstMatch
    }

    private func returnToList(_ app: XCUIApplication) {
        let back = app.buttons["journeyBackToList"].firstMatch
        if back.exists, back.isHittable { back.tap() }
        XCTAssertTrue(tripRow(0, in: app).waitForExistence(timeout: 30), "Trip list not shown.")
    }

    private func selectFirstTrip(_ app: XCUIApplication) {
        returnToList(app)
        tripRow(0, in: app).tap()
        XCTAssertTrue(selectedCard(in: app).waitForExistence(timeout: 30))
    }

    private func tapEdit(_ app: XCUIApplication) {
        let edit = app.buttons["journeyMenuEdit"]
        if !edit.waitForExistence(timeout: 5) {
            let information = app.buttons["Journey information"]
            if information.waitForExistence(timeout: 5) { information.tap() }
        }
        XCTAssertTrue(edit.waitForExistence(timeout: 15), "journeyMenuEdit not shown.")
        edit.tap()
    }

    /// Editor open, its saved route shown, and the map reporting its routes loaded.
    private func editorReady(_ app: XCUIApplication) -> Bool {
        guard app.buttons["newTripCancel"].waitForExistence(timeout: 60) else { return false }
        let saved = any("newTripSavedRoute", in: app)
        let stop = any("rideEditorStop-0", in: app)
        return wait(timeout: 60) { saved.exists || stop.exists }
    }

    private func cancelEditor(_ app: XCUIApplication) {
        let cancel = app.buttons["newTripCancel"]
        if cancel.exists { cancel.tap() }
        _ = cancel.waitForNonExistence(timeout: 15)
        returnToList(app)
    }

    /// Save becomes enabled; a single corridor choice is taken when it blocks Save.
    private func waitUntilSavable(_ app: XCUIApplication, timeout: TimeInterval = 90) -> Bool {
        let save = app.buttons["newTripSave"]
        return wait(timeout: timeout, poll: 0.2) {
            if save.exists, save.isEnabled { return true }
            let first = app.buttons["newTripCorridor-0"]
            if first.exists, first.isHittable, !app.buttons["newTripCorridor-1"].exists { first.tap() }
            return save.exists && save.isEnabled
        }
    }

    // MARK: - Focus

    private func focusAndSettle(_ app: XCUIApplication, name: String) {
        let action = app.buttons["journeyPrimaryAction"].firstMatch
        XCTAssertTrue(action.waitForExistence(timeout: 15), "journeyPrimaryAction (Locate route) not shown.")
        let before = renderField("focusRevision", app)
        let watch = Stopwatch()
        startMeasuring()
        action.tap()
        _ = wait(timeout: 20) { renderField("focusRevision", app) > before }
        waitCameraSettled(app)
        stopMeasuring()
        watch.report(name)
    }

    /// The camera has not moved between two reads 0.4 s apart.
    private func waitCameraSettled(_ app: XCUIApplication) {
        func camera() -> [Double] {
            ["centerLat", "centerLon", "distance"].map { renderField($0, app) }
        }
        var previous = camera()
        _ = wait(timeout: 30, poll: 0.4) {
            let now = camera()
            defer { previous = now }
            return zip(now, previous).allSatisfy { abs($0 - $1) < max(1e-5, abs($1) * 1e-4) }
        }
    }

    /// Move the camera off the trip so a second Locate has work to do.
    private func nudgeCamera(_ app: XCUIApplication) {
        let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.8, dy: 0.2))
        let end = app.coordinate(withNormalizedOffset: CGVector(dx: 0.2, dy: 0.2))
        start.press(forDuration: 0.05, thenDragTo: end)
        waitCameraSettled(app)
    }

    // MARK: - Reload all and hide sheet

    private func openReloadRow(in app: XCUIApplication) {
        let menu = any("utilityMenuButton", in: app)
        XCTAssertTrue(menu.waitForExistence(timeout: 30))
        menu.tap()
        let data = app.buttons["utilityDataButton"]
        XCTAssertTrue(data.waitForExistence(timeout: 8))
        data.tap()
        let button = app.buttons["reloadAllButton"]
        for _ in 0..<6 where !(button.exists && button.isHittable) { app.swipeUp() }
        XCTAssertTrue(button.waitForExistence(timeout: 8))
    }

    private func openHideSheet(_ app: XCUIApplication) -> Bool {
        returnToList(app)
        let filter = app.buttons["journeyFilterButton"].firstMatch
        guard filter.waitForExistence(timeout: 15) else { return false }
        filter.tap()
        let item = app.buttons["tripHideMenuItem"]
        guard item.waitForExistence(timeout: 8) else { return false }
        item.tap()
        return any("tripHideSheet", in: app).waitForExistence(timeout: 10)
    }

    private func hideToggle(_ prefix: String, in app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier BEGINSWITH %@", prefix)).firstMatch
    }

    private func dismissHideSheet(_ app: XCUIApplication) {
        let done = app.buttons["tripHideDone"]
        if done.exists { done.tap() }
        _ = done.waitForNonExistence(timeout: 10)
    }

    private func waitForStatistics(_ app: XCUIApplication) {
        let widget = app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier BEGINSWITH %@", "statisticsWidget-")).firstMatch
        if !widget.waitForExistence(timeout: 120) {
            note("no statisticsWidget-* element; falling back to statisticsFilterButton")
            XCTAssertTrue(app.buttons["statisticsFilterButton"].waitForExistence(timeout: 60),
                          "Statistics never appeared.")
        }
    }

    // MARK: - Station picking

    /// Search sheet pick, as `NewTripUITests.pickStation` does it: the `lineID`
    /// narrows shared codes; without it the row is the first ending in `-<code>`.
    private func pickStation(field: String, query: String, code: String, lineID: String?, in app: XCUIApplication) {
        let button = app.buttons[field]
        XCTAssertTrue(EditorUITestSupport.reveal(button, in: app, unmountedRowIsAbove: field != "newTripDestination"),
                      "\(field) not reachable.")
        let enabled = expectation(for: NSPredicate(format: "isEnabled == true"), evaluatedWith: button)
        wait(for: [enabled], timeout: 30)
        button.tap()
        let search = app.searchFields.firstMatch
        XCTAssertTrue(search.waitForExistence(timeout: 20))
        search.tap()
        search.typeText(query)
        let rows = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'newTripStation-'"))
        XCTAssertTrue(rows.firstMatch.waitForExistence(timeout: 30), "\(query) listed no stations.")
        let row = rows.matching(NSPredicate(
            format: lineID == nil ? "identifier ENDSWITH %@" : "identifier == %@",
            lineID.map { "newTripStation-\($0)-\(code)" } ?? "-\(code)")).firstMatch
        var swipes = 0
        while !row.waitForExistence(timeout: swipes == 0 ? 3 : 0.5), swipes < 40 {
            app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.55))
                .press(forDuration: 0.05, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.2)))
            swipes += 1
        }
        XCTAssertTrue(row.exists, "No newTripStation row ending in \(code) for \(query).")
        // A tap while the search keyboard is up only resigns the field.
        if app.keyboards.firstMatch.exists {
            search.typeText("\n")
            _ = app.keyboards.firstMatch.waitForNonExistence(timeout: 2)
        }
        row.tap()
        if search.exists, row.waitForExistence(timeout: 2) { row.tap() }
        XCTAssertTrue(search.waitForNonExistence(timeout: 10), "Choosing \(query) must close station search.")
    }

    // MARK: - Metrics and reporting

    private func metrics(_ app: XCUIApplication, _ signposts: [(category: String, name: String)]) -> [XCTMetric] {
        var result: [XCTMetric] = [XCTClockMetric(), XCTMemoryMetric(application: app), XCTCPUMetric(application: app)]
        for signpost in signposts {
            result.append(XCTOSSignpostMetric(subsystem: Self.subsystem, category: signpost.category, name: signpost.name))
        }
        return result
    }

    private func note(_ text: String) {
        print("PERF-NOTE \(text)")
    }

    private struct Stopwatch {
        let start = Date()
        func report(_ name: String) {
            print("PERF \(name) \(Int(Date().timeIntervalSince(start) * 1000))")
        }
    }
}
