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
    override func setUp() async throws {
        try await super.setUp()
        continueAfterFailure = false
        await MainActor.run {
            XCUIDevice.shared.orientation = .portrait
        }
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
        let stops = revealSwitch("layerStops", in: app)
        XCTAssertTrue(stops.exists, "the ridden-layer switches were not reachable in the layers sheet")
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
        let restoredStops = revealSwitch("layerStops", in: app)
        XCTAssertTrue(waitFor(timeout: 8) { restoredStops.isEnabled })
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
        let master = revealSwitch("layerRoutes", in: app)
        XCTAssertTrue(master.exists, "the ridden-layer switches were not reachable in the layers sheet")
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
        let drawn = launchOverTokyo(selectingMetro: true)
        XCTAssertTrue(
            tapSelectsARide(drawn, requiringTarget: true),
            "the tap no longer lands on a ridden line — the camera or the sample moved, "
                + "and the other half of this test proves nothing until it does again")
        attach(drawn, named: "08-tap-selects-a-drawn-ride")
        drawn.terminate()

        let hidden = launchOverTokyo(hiding: "routes", selectingMetro: true)
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
        let app = launchOverTokyo(hiding: "metro", selectingMetro: true)
        // Until the region's network has been read, every segment is
        // UNDETERMINED and therefore still drawn (and still tappable) — see
        // the renderer's `draws(segment:…)`. So this waits for the
        // classification rather than for the map, and an insufficient wait
        // fails the test rather than passing it for the wrong reason.
        let status = app.staticTexts["railMapRenderStatus"]
        XCTAssertTrue(waitFor(timeout: 45) { status.label.contains("targetCategoryReady:1") }, status.label)
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

    /// Enabling the complete network must leave the app responsive while its
    /// prebuilt viewport tiles are prepared and atomically installed.
    func testAllRailwaysToggleDoesNotStallTheMap() throws {
        XCUIDevice.shared.orientation = .portrait
        // A fixed railway-dense camera makes an empty render unambiguous. The
        // network still starts off and the store still starts without display
        // geometry, so this exercises the cold request that regressed.
        let app = launchOverTokyo()
        let renderStatus = app.staticTexts["railMapRenderStatus"]
        XCTAssertTrue(
            renderStatus.waitForExistence(timeout: 12),
            "the map's debug render status never mounted")
        let network = app.buttons["mapNetworkToggle"]
        XCTAssertTrue(network.waitForExistence(timeout: 12))
        XCTAssertFalse(network.isSelected)

        network.tap()
        XCTAssertTrue(network.isSelected, "全部線路 did not finish enabling")
        let rendered = NSPredicate(format: "label BEGINSWITH %@", "network:rendered;")
        expectation(for: rendered, evaluatedWith: renderStatus)
        waitForExpectations(timeout: 20)
        let status = renderStatus.label
        XCTAssertTrue(
            !status.contains("overlays:0"),
            "全部線路 was enabled but the map installed no railway overlays")
        // The time to query thousands of MapKit accessibility descendants is
        // XCTest overhead, not time to draw. Keep the 3-second gate on the
        // app's interval from enabling the network through its first render.
        let timing = try XCTUnwrap(status.split(separator: ";").first {
            $0.hasPrefix("firstNetworkMs:")
        })
        let milliseconds = try XCTUnwrap(Double(timing.dropFirst("firstNetworkMs:".count)))
        XCTAssertGreaterThanOrEqual(milliseconds, 0)
        XCTAssertLessThan(milliseconds, 3_000, "First network render took \(milliseconds) ms")
        let measurement = XCTAttachment(string: status)
        measurement.name = "first-network-render-timing"
        measurement.lifetime = .keepAlways
        add(measurement)
        let layers = app.buttons["mapLayersButton"]
        layers.tap()
        XCTAssertTrue(
            app.switches["layerNetworkStations"].waitForExistence(timeout: 6),
            "the layers sheet did not respond after enabling all railways")
        attach(app, named: "11-all-railways-responsive")
    }

    /// Turning 全部線路 off and on again must draw the network every time,
    /// including when the reader flips it faster than a rebuild finishes.
    func testAllRailwaysRepeatedToggleRendersEveryTime() throws {
        try assertRepeatedToggleRenders(camera: nil)
    }

    /// The same at a regional span, where preparing the network's geometry
    /// takes long enough for a flip to land inside it.
    func testAllRailwaysRepeatedToggleRendersAtRegionalZoom() throws {
        try assertRepeatedToggleRenders(camera: "35.9,139.75,4.0")
    }

    /// All of Japan, where most of the network is drawn from overview chunks.
    func testAllRailwaysRepeatedToggleRendersAtNationalZoom() throws {
        try assertRepeatedToggleRenders(camera: "36.5,139.75,18.0")
    }

    private func assertRepeatedToggleRenders(camera: String?) throws {
        XCUIDevice.shared.orientation = .portrait
        // The ready ride is a Tokyo metro line, too small to count as drawn
        // at a national span.
        let app = launchOverTokyo(camera: camera, waitsForReadyRide: camera == nil)
        let renderStatus = app.staticTexts["railMapRenderStatus"]
        XCTAssertTrue(renderStatus.waitForExistence(timeout: 12))
        let network = app.buttons["mapNetworkToggle"]
        XCTAssertTrue(network.waitForExistence(timeout: 12))
        XCTAssertFalse(network.isSelected)
        func rendered() -> Bool {
            let label = renderStatus.label
            return label.hasPrefix("network:rendered;") && !label.contains(";overlays:0;")
        }
        func off() -> Bool { renderStatus.label.hasPrefix("network:off;") }
        var log: [String] = []
        // Settled cycles, then flips that land inside a rebuild.
        for cycle in 0..<3 {
            network.tap()
            XCTAssertTrue(
                waitFor(timeout: cycle == 0 ? 60 : 20, rendered),
                "cycle \(cycle): network did not render on: " + renderStatus.label)
            log.append("on \(cycle): " + renderStatus.label)
            network.tap()
            XCTAssertTrue(
                waitFor(timeout: 20, off), "cycle \(cycle): network did not turn off: " + renderStatus.label)
            log.append("off \(cycle): " + renderStatus.label)
        }
        for pause in [0.0, 0.3, 0.8, 1.5] {
            network.tap()
            Thread.sleep(forTimeInterval: pause)
            network.tap()
            Thread.sleep(forTimeInterval: pause)
        }
        network.tap()
        XCTAssertTrue(network.isSelected)
        XCTAssertTrue(
            waitFor(timeout: 20, rendered), "network did not render after rapid toggles: " + renderStatus.label)
        log.append("rapid: " + renderStatus.label)
        // Moved while hidden, and moving while it comes back.
        let east = app.coordinate(withNormalizedOffset: CGVector(dx: 0.85, dy: 0.25))
        let west = app.coordinate(withNormalizedOffset: CGVector(dx: 0.15, dy: 0.25))
        for cycle in 0..<2 {
            network.tap()
            XCTAssertTrue(waitFor(timeout: 20, off))
            east.press(forDuration: 0.05, thenDragTo: west)
            Thread.sleep(forTimeInterval: 1.5)
            network.tap()
            west.press(forDuration: 0.05, thenDragTo: east, withVelocity: .fast, thenHoldForDuration: 0)
            XCTAssertTrue(
                waitFor(timeout: 20, rendered), "pan \(cycle): network did not render: " + renderStatus.label)
            Thread.sleep(forTimeInterval: 2)
            XCTAssertTrue(rendered(), "pan \(cycle): " + renderStatus.label)
            log.append("pan \(cycle): " + renderStatus.label)
        }
        let attachment = XCTAttachment(string: log.joined(separator: "\n"))
        attachment.name = "repeated-network-toggle"
        attachment.lifetime = .keepAlways
        add(attachment)
        attach(app, named: "network-after-repeated-toggles")
    }

    /// Checks the actual renderer independently of XCTest's tap timing.
    func testNetworkVisibilityUsesWindowDensity() throws {
        XCUIDevice.shared.orientation = .portrait
        try assertNetworkWindowDensity()
    }

    private func assertNetworkWindowDensity() throws {
        let app = launchOverTokyo(hiding: "network")
        let renderStatus = app.staticTexts["railMapRenderStatus"]
        XCTAssertTrue(renderStatus.waitForExistence(timeout: 12))
        expectation(
            for: NSPredicate(format: "label BEGINSWITH %@", "network:rendered;"),
            evaluatedWith: renderStatus)
        waitForExpectations(timeout: 20)
        // Read the real renderer's scales, rather than only testing the pure
        // policy. This catches a detail delay that never reaches MapKit.
        let status = renderStatus.label
        let fields = status.split(separator: ";")
        let cameraText = try XCTUnwrap(fields.first { $0.hasPrefix("camera:") })
        let lodText = try XCTUnwrap(fields.first { $0.hasPrefix("lod:") })
        let camera = try XCTUnwrap(Double(cameraText.dropFirst("camera:".count)))
        let lod = try XCTUnwrap(Double(lodText.dropFirst("lod:".count)))
        let widthText = try XCTUnwrap(fields.first { $0.hasPrefix("viewportWidth:") })
        let heightText = try XCTUnwrap(fields.first { $0.hasPrefix("viewportHeight:") })
        let width = try XCTUnwrap(Double(widthText.dropFirst("viewportWidth:".count)))
        let height = try XCTUnwrap(Double(heightText.dropFirst("viewportHeight:".count)))
        // NetworkVisibilityPolicy continuously normalises the renderer to its
        // 390-point reference short edge. The old 600/900-point test buckets
        // predated that policy and treated the real 402-point adjustment as
        // rounding noise.
        let adjustment = log2(390 / min(width, height))
        let expectedDelay = -min(max(adjustment, -1.5), 0.5)
        XCTAssertEqual(
            camera - lod, expectedDelay, accuracy: 0.02,
            "The rendered network must defer detail for this window's workload.")
        let density = XCTAttachment(string: status)
        density.name = "rendered-network-density"
        density.lifetime = .keepAlways
        add(density)
        attach(app, named: "network-window-density")
    }

    func testLandscapeNetworkUsesWindowDensity() throws {
        XCUIDevice.shared.orientation = .landscapeLeft
        defer { XCUIDevice.shared.orientation = .portrait }
        try assertNetworkWindowDensity()
    }

    /// Cross the padded viewport in both directions with the network mounted.
    /// First-render timing cannot detect repeated rebuilds inside a gesture.
    func testAllRailwaysContinuousPanReusesGeometryAndAnnotations() throws {
        XCUIDevice.shared.orientation = .portrait
        let app = launchOverTokyo(hiding: "network")
        let status = app.staticTexts["railMapRenderStatus"]
        XCTAssertTrue(status.waitForExistence(timeout: 12))
        XCTAssertTrue(waitFor(timeout: 20) { status.label.hasPrefix("network:rendered;") })
        func value(_ field: String, in text: String) throws -> Int {
            let part = try XCTUnwrap(text.split(separator: ";").first { $0.hasPrefix(field + ":") })
            return try XCTUnwrap(Int(part.dropFirst(field.count + 1)))
        }
        let before = status.label
        let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.90, dy: 0.12))
        let end = app.coordinate(withNormalizedOffset: CGVector(dx: 0.10, dy: 0.12))
        start.press(forDuration: 0.05, thenDragTo: end, withVelocity: .slow, thenHoldForDuration: 0.1)
        // Let inertia and the settle task finish before requesting a large
        // MapKit accessibility snapshot, which can itself stall a simulator.
        Thread.sleep(forTimeInterval: 2)
        let outward = status.label
        end.press(forDuration: 0.05, thenDragTo: start, withVelocity: .slow, thenHoldForDuration: 0.1)
        Thread.sleep(forTimeInterval: 2)
        let returned = status.label
        let measurements = XCTAttachment(string: [before, outward, returned].joined(separator: "\n"))
        measurements.name = "continuous-network-pan"
        measurements.lifetime = .keepAlways
        add(measurements)
        XCTAssertGreaterThan(try value("panCallbacks", in: returned), 10)
        XCTAssertEqual(try value("gestureBuilds", in: returned), 0)
        XCTAssertGreaterThan(try value("rebuilds", in: outward), try value("rebuilds", in: before))
        XCTAssertGreaterThan(try value("rebuilds", in: returned), try value("rebuilds", in: outward))
        XCTAssertGreaterThan(try value("cacheHits", in: returned), try value("cacheHits", in: before))
        XCTAssertGreaterThan(try value("annotationReuses", in: returned), try value("annotationReuses", in: before))
        for snapshot in [outward, returned] {
            XCTAssertEqual(try value("covered", in: snapshot), 1)
            XCTAssertGreaterThan(try value("lines", in: snapshot), 0)
        }
        attach(app, named: "network-after-return-pan")
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

    /// SwiftUI's List only publishes rows in its current lazy viewport. The
    /// ridden controls follow the basemap and complete-network sections, so
    /// reach them the same way a reader does rather than interpreting an
    /// offscreen row as a sheet that failed to open.
    private func revealSwitch(_ identifier: String, in app: XCUIApplication) -> XCUIElement {
        let toggle = app.switches[identifier]
        for _ in 0..<4 where !toggle.exists {
            app.swipeUp()
            Thread.sleep(forTimeInterval: 0.4)
        }
        return toggle
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
        app.launchEnvironment["RAILMAP_UI_TEST_STORAGE_ID"] = UUID().uuidString
        app.launchEnvironment["RAILMAP_UI_TEST_TAB"] = "all"
        app.launchEnvironment["RAILMAP_UI_TEST_STATS_REGION"] = "all"
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

    // A point on the fixture's isolated 地下鐵 stretch between 茗荷谷 and
    // 新大塚 (part-008.json), where one journey is selected without a chooser.
    // Centering it keeps the tap outside the iPad's leading dock. The closer
    // span keeps nearby stations' 44-point annotation targets off the track aim.
    private static let metroSelectionCamera = "35.72124,139.73418,0.04"
    private static let riddenMetroLine = CGVector(dx: 0.5, dy: 0.5)

    /// Launch over ``tokyoCamera``, with `layers` switched off.
    private func launchOverTokyo(
        hiding layers: String? = nil, selectingMetro: Bool = false, camera: String? = nil,
        waitsForReadyRide: Bool = true
    ) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchEnvironment["RAILMAP_UI_TEST_STORAGE_ID"] = UUID().uuidString
        // The renderer fixture must not depend on a previous simulator session.
        app.launchEnvironment["RAILMAP_UI_TEST_SAMPLE"] = "train-store"
        app.launchEnvironment["RAILMAP_UI_TEST_TAB"] = "all"
        // The shared region scope persists across suites and also filters
        // All Journeys' map. Keep the Japanese fixture in that scope.
        app.launchEnvironment["RAILMAP_UI_TEST_STATS_REGION"] = "all"
        // Start open, then collapse through the actual header gesture before
        // tapping the map and reopen it to inspect the selected card.
        app.launchEnvironment["RAILMAP_UI_TEST_STAGE"] = "medium"
        app.launchEnvironment["RAILMAP_UI_TEST_CAMERA"] = camera ?? (selectingMetro
            ? Self.metroSelectionCamera : Self.tokyoCamera)
        app.launchEnvironment["RAILMAP_UI_TEST_READY_RIDE"] = "20260704_06_marunouchi_line"
        if let layers { app.launchEnvironment["RAILMAP_UI_TEST_LAYERS"] = layers }
        app.launch()
        let status = app.staticTexts["railMapRenderStatus"]
        XCTAssertTrue(status.waitForExistence(timeout: 15))
        XCTAssertTrue(waitFor(timeout: 45) {
            (!waitsForReadyRide || status.label.contains("targetRideReady:1"))
                && abs((Double(status.label.split(separator: ";").first {
                    $0.hasPrefix("centerLon:")
                }?.dropFirst("centerLon:".count) ?? "") ?? 0) - (selectingMetro ? 139.73418 : 139.75)) < 0.01
        }, status.label)
        return app
    }

    /// Whether a tap on ``riddenMetroLine`` selected a journey.
    ///
    /// The selected card is identified by the fixture record rather than by
    /// whichever primary action its current presentation policy happens to
    /// offer. That keeps this assertion about map picking.
    private func tapSelectsARide(_ app: XCUIApplication, requiringTarget: Bool = false) -> Bool {
        let header = app.descendants(matching: .any)["panelHeader"].firstMatch
        XCTAssertTrue(header.waitForExistence(timeout: 8))
        var tapCoordinate = app.coordinate(withNormalizedOffset: Self.riddenMetroLine)
        let dockToggle = app.buttons["dockPanelToggle"]
        if dockToggle.exists {
            let appBounds = app.frame
            let headerBounds = header.frame
            let toggleBounds = dockToggle.frame
            let originalAim = CGPoint(x: appBounds.minX + appBounds.width * Self.riddenMetroLine.dx,
                                      y: appBounds.minY + appBounds.height * Self.riddenMetroLine.dy)
            // Source layout: dock inset 16 minus adjacent HStack spacing 8.
            // The actual toggle origin supplies the card width and safe-area offset.
            let leadingObstruction = toggleBounds.minX - appBounds.minX + 8
            let aim = CGPoint(x: (appBounds.minX + appBounds.maxX + leadingObstruction) / 2,
                              y: originalAim.y)
            func finiteNonempty(_ frame: CGRect) -> Bool {
                !frame.isEmpty && !frame.isNull && !frame.isInfinite
                    && frame.minX.isFinite && frame.minY.isFinite
                    && frame.width.isFinite && frame.height.isFinite
            }
            let measurement = XCTAttachment(string:
                "App=\(appBounds); header=\(headerBounds); toggle=\(toggleBounds); oldAim=\(originalAim); leadingObstruction=\(leadingObstruction); newAim=\(aim); "
                + "headerLabel=\(header.label); toggleLabel=\(dockToggle.label); "
                + "headerNativeIsHittable=\(header.isHittable); toggleNativeIsHittable=\(dockToggle.isHittable)\n"
                + app.debugDescription)
            measurement.name = "metro-aim-leading-dock-native-geometry"
            measurement.lifetime = .keepAlways
            add(measurement)
            // The toggle follows the entire DockedCard in the leading HStack.
            // Its right edge conservatively bounds that covered strip at every height.
            // panelHeader is only title text; it is not a full-card measurement.
            guard header.exists, finiteNonempty(appBounds), finiteNonempty(headerBounds),
                  finiteNonempty(toggleBounds), leadingObstruction.isFinite,
                  leadingObstruction >= 0, leadingObstruction < appBounds.width,
                  appBounds.contains(headerBounds),
                  appBounds.contains(toggleBounds), appBounds.contains(aim),
                  aim.x > max(headerBounds.maxX, toggleBounds.maxX) + 60 else {
                XCTFail("The measured leading dock and its adjacent toggle must leave the centered metro aim beyond the covered strip plus 60 points.")
                return false
            }
            tapCoordinate = app.coordinate(withNormalizedOffset: .zero).withOffset(
                CGVector(dx: aim.x - appBounds.minX, dy: aim.y - appBounds.minY))
        } else {
            let collapseStart = header.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
            let collapseDistance = min(320, app.frame.maxY - header.frame.midY - 30)
            collapseStart.press(forDuration: 0.1, thenDragTo: collapseStart.withOffset(
                CGVector(dx: 0, dy: collapseDistance)))
            let tapY = app.frame.minY + app.frame.height * Self.riddenMetroLine.dy
            XCTAssertTrue(waitFor(timeout: 8) { header.frame.minY > tapY + 60 },
                          "The resident panel must leave the metro tap on uncovered map.")
        }
        tapCoordinate.tap()
        // Long enough for the card to arrive, and asserted on afterwards
        // rather than waited for: a `waitForExistence` here would answer the
        // negative case only by timing out, which is the case both callers
        // care about most.
        Thread.sleep(forTimeInterval: 4)
        // A visible route presents a separate menu immediately. A hidden
        // route must not become selectable through the base map.
        if requiringTarget {
            return app.descendants(matching: .any)["selectedJourney-20260704_06_marunouchi_line"].firstMatch
                .waitForExistence(timeout: 8)
        }
        return app.descendants(matching: .any).matching(NSPredicate(
            format: "identifier BEGINSWITH %@", "selectedJourney-")).firstMatch.exists

    }
}
