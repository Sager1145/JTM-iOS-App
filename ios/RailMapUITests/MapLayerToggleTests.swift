import XCTest

/// The two switches the map is toggled with most, and the master/subordinate
/// relationship between them.
///
/// These assert on the CONTROLS rather than on pixels — a UI test cannot see
/// whether a station dot is drawn — so each one also attaches a screenshot.
/// The assertion catches a control that stopped working; the attachment is
/// what a person looks at to see that the map actually changed.
@MainActor
final class MapLayerToggleTests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    /// 列車経路 is reachable from the rail, and reports its own state.
    func testTrainRoutesToggleLivesOnTheRail() {
        let app = launch()
        let routes = app.buttons["mapRoutesToggle"]
        XCTAssertTrue(
            routes.waitForExistence(timeout: 12),
            "列車経路 must be a control on the map rail, not only inside the layers sheet.")
        XCTAssertTrue(routes.isSelected, "It starts on, with every ride drawn.")
        attach(app, named: "01-routes-on")

        routes.tap()
        // The selected trait is the accessibility half of §10.5's rule that a
        // state may not be carried by colour alone; if it does not clear, the
        // switch moved the map without telling anyone who cannot see the tint.
        XCTAssertTrue(
            waitFor(timeout: 6) { !routes.isSelected },
            "Turning 列車経路 off must clear the control's selected trait.")
        attach(app, named: "02-routes-off")

        routes.tap()
        XCTAssertTrue(waitFor(timeout: 6) { routes.isSelected })
    }

    /// With 列車経路 off, the three ride-marker switches are disabled rather
    /// than silently ignored — `MapLayers.routes` is their master.
    func testRideMarkerSwitchesFollowTheirMaster() {
        let app = launch()
        let routes = app.buttons["mapRoutesToggle"]
        XCTAssertTrue(routes.waitForExistence(timeout: 12))
        routes.tap()

        app.buttons["mapLayersButton"].tap()
        let stops = app.switches["layerStops"]
        XCTAssertTrue(stops.waitForExistence(timeout: 8), "the layers sheet never opened")
        XCTAssertFalse(
            stops.isEnabled,
            "With 列車経路 off there are no routes for a stop marker to sit on, so its "
                + "switch must not look operable.")
        attach(app, named: "03-markers-disabled")

        // And back: the master returns, the subordinates come back with the
        // values the reader left them at rather than being reset.
        dismissLayers(app)
        routes.tap()
        app.buttons["mapLayersButton"].tap()
        XCTAssertTrue(waitFor(timeout: 8) { app.switches["layerStops"].isEnabled })
        attach(app, named: "04-markers-enabled")
    }

    /// The master switch stays operable while it is OFF.
    ///
    /// It did not. The three subordinate switches sat in one `Group` carrying a
    /// single `.disabled(!routes)`, and inside a `Section` that modifier did not
    /// stay on the group — it reached the master beside them. So 列車経路 could
    /// be switched off from this sheet and never on again: the switch took the
    /// tap and moved nothing, and only the map rail's own button could undo it.
    ///
    /// Asserted on the SHEET's switch rather than on the state, because the
    /// state was never the broken half — the rail went on working throughout,
    /// which is why a one-way switch sat here unnoticed.
    func testTheMasterSwitchCanBeTurnedBackOnFromTheSheet() {
        let app = launch()
        let routes = app.buttons["mapRoutesToggle"]
        XCTAssertTrue(routes.waitForExistence(timeout: 12))
        routes.tap()
        XCTAssertTrue(waitFor(timeout: 6) { !routes.isSelected })

        app.buttons["mapLayersButton"].tap()
        let master = app.switches["layerRoutes"]
        XCTAssertTrue(master.waitForExistence(timeout: 8), "the layers sheet never opened")
        XCTAssertTrue(
            master.isEnabled,
            "列車経路 is the only switch in this section that can put the ridden lines back, "
                + "so it must stay operable while it is the one that is off.")
        flip(master)
        settleAfterLayerChange()
        XCTAssertEqual(
            master.value as? String, "1",
            "The master switch took the tap and did not move.")
        XCTAssertTrue(
            app.switches["layerStops"].isEnabled,
            "Turning 列車経路 back on from the sheet must return its subordinates with it.")
        attach(app, named: "07-master-back-on")

        dismissLayers(app)
        XCTAssertTrue(
            waitFor(timeout: 6) { routes.isSelected },
            "and the rail's own button must report the state the sheet just set.")
    }

    /// A ride that is not drawn is not a target either.
    ///
    /// `RailMap.setVisible` moves the pick layers with the drawn ones, so a
    /// click over a hidden route hits nothing in the browser. The native tap
    /// index was built from the rides themselves, which do not know whether
    /// they were drawn: with 列車経路 off, a tap on empty basemap opened a
    /// journey card — or the ambiguity chooser, listing journeys none of which
    /// was on screen.
    ///
    /// The first half is the control: without it, "nothing was selected" would
    /// also be the answer when the tap simply stopped landing on a line.
    func testAHiddenRideIsNotSelectable() {
        let drawn = launchOverTokyo()
        XCTAssertTrue(
            tapSelectsARide(drawn),
            "the tap no longer lands on a ridden line — the camera or the sample moved, "
                + "and the other half of this test proves nothing until it does again")
        attach(drawn, named: "08-tap-selects-a-drawn-ride")
        drawn.terminate()

        let hidden = launchOverTokyo(hiding: "routes")
        XCTAssertFalse(
            tapSelectsARide(hidden),
            "With 列車経路 off there is nothing of the reader's on the map, so a tap on "
                + "one of its lines must read as a tap on empty ground.")
        attach(hidden, named: "09-tap-on-hidden-ride-selects-nothing")
    }

    /// And a ride 已乘路線顯示 has filtered out is not a target either.
    ///
    /// The same rule one switch further down: the web app filters hidden
    /// categories out of the source the pick layer reads, so a 地下鐵 stretch
    /// the reader has switched off is not clickable there. Per SEGMENT, which
    /// is why the aim is a metro line rather than a metro journey.
    ///
    /// No control half here — ``testAHiddenRideIsNotSelectable`` is it, and it
    /// fails first if this aim ever stops finding a line.
    func testACategoryHiddenRideIsNotSelectable() {
        let app = launchOverTokyo(hiding: "metro")
        // Until the region's network has been read, every segment is
        // UNDETERMINED and therefore still drawn (and still tappable) — see
        // the renderer's `draws(segment:…)`. So this waits for the
        // classification rather than for the map, and an insufficient wait
        // fails the test rather than passing it for the wrong reason.
        Thread.sleep(forTimeInterval: 18)
        attach(app, named: "10-metro-filtered-off")
        XCTAssertFalse(
            tapSelectsARide(app),
            "A ridden stretch whose category is switched off is not on the map, so it "
                + "must not answer a tap on where it used to be.")
    }

    /// The network group exists and both of its switches operate.
    func testNetworkStationSwitchesExist() {
        let app = launch()
        XCTAssertTrue(app.buttons["mapLayersButton"].waitForExistence(timeout: 12))
        app.buttons["mapLayersButton"].tap()

        for label in ["layerNetworkStations", "layerNetworkStationNames"] {
            let toggle = app.switches[label]
            XCTAssertTrue(
                toggle.waitForExistence(timeout: 8),
                "the 全部線路 group must offer the “\(label)” switch")
            XCTAssertTrue(toggle.isEnabled)
            toggle.tap()
        }
        attach(app, named: "05-network-stations-off")

        dismissLayers(app)
        // Give the map a moment to rebuild without the network's dots.
        Thread.sleep(forTimeInterval: 3)
        attach(app, named: "06-map-without-network-stations")
    }

    // MARK: - helpers

    /// Press a row's switch, rather than its row.
    ///
    /// A SwiftUI `Toggle` in a `List` publishes the WHOLE ROW as one switch
    /// element, so `XCUIElement.tap()` aims at the middle of the row — the
    /// label — where nothing happens. A test written that way reports on where
    /// XCTest aimed instead of on whether the control works, which is the one
    /// thing this suite is for.
    private func flip(_ toggle: XCUIElement) {
        toggle.coordinate(withNormalizedOffset: CGVector(dx: 0.92, dy: 0.5)).tap()
    }

    /// Let the map finish redrawing before the tree is asked anything.
    ///
    /// A switch in this sheet remounts every ride on the map, and an
    /// accessibility snapshot taken across that rebuild is how this suite loses
    /// its runner: XCTest waits on an app that is busy walking a few hundred
    /// annotations and eventually kills it ("Test crashed with signal kill"),
    /// which reads as a product crash and is not one. Polling made it worse
    /// rather than better — every retry is another snapshot request.
    private func settleAfterLayerChange() {
        Thread.sleep(forTimeInterval: 3)
    }

    /// The layers sheet's dismissal.
    ///
    /// By position, not by the word: 完了 / Done / 完成 all live on the same
    /// toolbar and the label depends on the reader's language, which is what
    /// made the first version of this suite fail on a Japanese simulator.
    private func dismissLayers(_ app: XCUIApplication) {
        let done = app.navigationBars.buttons.element(boundBy: 0)
        if done.waitForExistence(timeout: 6) { done.tap() }
    }

    private func waitFor(timeout: TimeInterval, _ condition: () -> Bool) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if condition() { return true }
            Thread.sleep(forTimeInterval: 0.25)
        }
        return condition()
    }

    private func attach(_ app: XCUIApplication, named: String) {
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = named
        shot.lifetime = .keepAlways
        add(shot)
    }

    private func launch() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchEnvironment["RAILMAP_UI_TEST_TAB"] = "all"
        app.launchEnvironment["RAILMAP_UI_TEST_STAGE"] = "medium"
        app.launch()
        return app
    }

    // MARK: - the tap tests' shared aim

    /// Tokyo, at the zoom the sample's metro lines are legible from.
    ///
    /// A camera the test SETS rather than one it pans to: `setRegion` fits
    /// this span to the window, so the fraction below lands on the same
    /// geography whatever the launch camera would have chosen.
    private static let tokyoCamera = "35.68,139.75,0.12"

    /// Where on the window the 丸ノ内線 runs between 新大塚 and 茗荷谷 under
    /// ``tokyoCamera``.
    ///
    /// Chosen because it is one line on its own — the tap resolves to a single
    /// journey rather than to the ambiguity chooser — and because it is 地下鐵,
    /// which is what makes it usable by both tests below.
    private static let riddenMetroLine = CGVector(dx: 148.0 / 402.0, dy: 277.0 / 874.0)

    /// Launch over ``tokyoCamera``, with `layers` switched off.
    private func launchOverTokyo(hiding layers: String? = nil) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchEnvironment["RAILMAP_UI_TEST_TAB"] = "all"
        app.launchEnvironment["RAILMAP_UI_TEST_STAGE"] = "medium"
        app.launchEnvironment["RAILMAP_UI_TEST_CAMERA"] = Self.tokyoCamera
        if let layers { app.launchEnvironment["RAILMAP_UI_TEST_LAYERS"] = layers }
        app.launch()
        // The camera hook waits for the map to exist and then for its own
        // beat, and the rides land as their packages decode. There is nothing
        // in the tree to wait ON — a map is one element whatever is drawn in
        // it — so this is one of the two places in this suite that sleeps.
        Thread.sleep(forTimeInterval: 12)
        return app
    }

    /// Whether a tap on ``riddenMetroLine`` selected a journey.
    ///
    /// `journeyPrimaryAction` is the selected journey's own button, so it
    /// exists exactly while the panel is showing one — which is the question
    /// here, asked without depending on the reader's language.
    private func tapSelectsARide(_ app: XCUIApplication) -> Bool {
        app.coordinate(withNormalizedOffset: Self.riddenMetroLine).tap()
        // Long enough for the card to arrive, and asserted on afterwards
        // rather than waited for: a `waitForExistence` here would answer the
        // negative case only by timing out, which is the case both callers
        // care about most.
        Thread.sleep(forTimeInterval: 4)
        return app.buttons["journeyPrimaryAction"].exists
    }
}
