import XCTest
import UIKit

/// Regressions for the complete-network zoom path.
///
/// The renderer publishes these measurements from inside the app. Measuring
/// `XCUIElement.pinch` with `XCTClockMetric` would mostly time XCTest's
/// synthetic gesture duration, while treating sparse MapKit camera callbacks
/// as frames would overstate what they prove. A DEBUG-only display-link probe
/// measures main-run-loop gaps while the gesture sensors are active; the other
/// useful signal is whether an expensive rebuild entered while a finger was down.
@MainActor
final class MapZoomPerformanceTests: XCTestCase {
    private static let maximumDisplayLinkGapMilliseconds = 150

    override func setUp() {
        continueAfterFailure = false
    }

    func testAllRailwaysRepeatedZoomAcrossJapanDefersRebuildsUntilSettle() throws {
        try assertRepeatedZoom(camera: .japan, attachmentName: "japan-network-zoom")
    }

    func testAllRailwaysRepeatedZoomOverDenseTokyoKeepsCallbacksResponsive() throws {
        try assertRepeatedZoom(camera: .tokyo, attachmentName: "tokyo-network-zoom")
    }

    func testAll287JourneysRepeatedZoomAcrossJapan() throws {
        try assertRepeatedZoom(camera: .japan, attachmentName: "all287-japan-zoom", requiredRecords: 287)
    }

    func testAll287JourneysRepeatedZoomOverDenseTokyo() throws {
        try assertRepeatedZoom(camera: .tokyo, attachmentName: "all287-tokyo-zoom", requiredRecords: 287)
    }

    func testTokyoNetworkRemainsVisibleAfterDeviceRotation() throws {
        try assertRepeatedZoom(camera: .tokyo, attachmentName: "rotated-tokyo-zoom", rotateBeforeZoom: true)
    }

    func testTwoFingerMapRotationThenZoomDefersGeometryBuilds() throws {
        try assertRepeatedZoom(camera: .tokyo, attachmentName: "map-rotation-zoom", rotateMapBeforeZoom: true)
    }

    private func assertRepeatedZoom(
        camera: Camera, attachmentName: String,
        rotateBeforeZoom: Bool = false,
        rotateMapBeforeZoom: Bool = false, requiredRecords: Int? = nil
    ) throws {
#if !targetEnvironment(macCatalyst)
        XCUIDevice.shared.orientation = .portrait
        defer { XCUIDevice.shared.orientation = .portrait }
        let app = launch(camera: camera)
        if requiredRecords != nil {
            MapSampleUITestSupport.importAllSamples(in: app)
            // Warm the route cache in this session so the relaunch measures zoom, not a cold solve.
            let warmupInventory = app.staticTexts["journeyLoadInventory"]
            XCTAssertTrue(warmupInventory.waitForExistence(timeout: 10))
            let warmed = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
                let loaded = RenderSnapshot(warmupInventory.label)
                return loaded.integerIfPresent("registered") == requiredRecords
                    && loaded.fields["phase"] == "loaded"
            }, object: nil)
            XCTAssertEqual(XCTWaiter.wait(for: [warmed], timeout: 900), .completed,
                           "The route cache must be warm before relaunch: \(warmupInventory.label)")
            app.terminate()
            app.launch()
        }
        let status = app.staticTexts["railMapRenderStatus"]
        XCTAssertTrue(
            status.waitForExistence(timeout: 12),
            "The DEBUG render-status probe never mounted.")

        var initial = try waitForRenderedNetwork(status, near: camera.center,
                                                minimumCamera: camera == .japan ? nil : 11, timeout: 30)
        if let requiredRecords {
            let inventory = app.staticTexts["journeyLoadInventory"]
            XCTAssertTrue(inventory.waitForExistence(timeout: 10))
            let complete = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
                let loaded = RenderSnapshot(inventory.label)
                return loaded.integerIfPresent("registered") == requiredRecords
                    && loaded.fields["phase"] == "loaded"
                    && loaded.fields["drawable"] == RenderSnapshot(status.label).fields["rides"]
            }, object: nil)
            XCTAssertEqual(XCTWaiter.wait(for: [complete], timeout: 180), .completed,
                           "Every record must finish processing: \(inventory.label); \(status.label)")
            initial = try waitForRenderedNetwork(status, near: camera.center,
                                                minimumCamera: camera == .japan ? nil : 11, timeout: 30)
            let loaded = RenderSnapshot(inventory.label)
            XCTAssertEqual(try loaded.integer("registered"), requiredRecords)
            XCTAssertEqual(try initial.integer("rides"), try loaded.integer("drawable"))
            XCTAssertGreaterThan(try initial.integer("rides"), 0)
        }
        if rotateBeforeZoom {
            let width = try initial.double("viewportWidth")
            XCUIDevice.shared.orientation = .landscapeLeft
            if UIDevice.current.userInterfaceIdiom == .phone {
                initial = try waitForRenderedNetwork(status, near: camera.center,
                                                    minimumCamera: 11, timeout: 20)
                XCTAssertGreaterThan(try initial.double("viewportHeight"), try initial.double("viewportWidth"))
                XCTAssertEqual(try initial.double("viewportWidth"), width, accuracy: 1,
                               "iPhone rotation requests must keep the portrait map viewport.")
            } else {
                // An iPad composition swap owns a new coordinator; require
                // the resized viewport and preserved city camera.
                initial = try waitForRenderedNetwork(status, afterViewportWidth: width,
                                                    near: camera.center, minimumCamera: 11, timeout: 20)
                XCTAssertGreaterThan(try initial.double("viewportWidth"), try initial.double("viewportHeight"))
            }
        }
        attach(initial.raw, named: "\(attachmentName)-00-initial")
        attach(XCUIScreen.main.screenshot(), named: "\(attachmentName)-00-initial-map")
        let gestureTarget = app.otherElements["railMapGestureTarget"]
        XCTAssertTrue(
            gestureTarget.waitForExistence(timeout: 8),
            "The unobscured DEBUG map gesture target was not reachable.")
        var previous = initial
        if rotateMapBeforeZoom {
            gestureTarget.rotate(.pi / 3, withVelocity: 0.6)
            previous = try waitForRenderedNetwork(status, afterRebuild: initial.integer("rebuilds"),
                                                 afterHeading: initial.double("heading"), timeout: 15)
        }
        let zoomStartCamera = try previous.double("camera")
        // Alternate in and out across the same LOD boundaries. Targeting the
        // central map area keeps both synthetic touches clear of the resident
        // bottom panel, including the contracting pinch's wider start points.
        for (index, scale) in [2.0, 0.5, 2.0, 0.5, 2.0].enumerated() {
            gestureTarget.pinch(withScale: scale, velocity: scale > 1 ? 1 : -1)
            let previousRebuilds = try previous.integer("rebuilds")
            let previousCamera = try previous.double("camera")
            let settled = try waitForRenderedNetwork(
                status, afterRebuild: previousRebuilds,
                afterCamera: previousCamera, timeout: 15)
            XCTAssertGreaterThan(
                try settled.integer("rebuilds"), previousRebuilds,
                "The pinch finished without publishing its settled network rebuild.")
            XCTAssertGreaterThan(
                abs(try settled.double("camera") - previousCamera), 0.3,
                "The synthetic pinch did not change the map camera enough to exercise zoom.")
            attach(settled.raw, named: "\(attachmentName)-0\(index + 1)-settled")
            if rotateMapBeforeZoom, index == 0 {
                XCTAssertGreaterThan(abs(sin(try settled.double("heading") * .pi / 180)), 0.2,
                                     "The two-finger gesture did not rotate the map.")
            }
            previous = settled
        }

        let settled = previous
        XCTAssertGreaterThan(
            abs(try settled.double("camera") - zoomStartCamera), 0.3,
            "The final assertion read an earlier published build instead of the last pinch.")

        let callbackDelta = try settled.integer("panCallbacks")
            - initial.integer("panCallbacks")
        XCTAssertGreaterThan(
            callbackDelta, 5,
            "Five pinches produced no meaningful MapKit camera callback activity.")
        let gestureFrameDelta = try settled.integer("gestureFrames")
            - initial.integer("gestureFrames")
        XCTAssertGreaterThan(
            gestureFrameDelta, 20,
            "The display-link probe observed too few gesture frames to make its gap meaningful.")
        XCTAssertLessThanOrEqual(
            try settled.integer("gestureMaxFrameGapMs"), Self.maximumDisplayLinkGapMilliseconds,
            "The main display link paused for at least 150 ms during repeated zoom.")
        XCTAssertEqual(
            try settled.integer("gestureBuilds"),
            try initial.integer("gestureBuilds"),
            "Network geometry rebuilt while a pinch was still active.")
        XCTAssertEqual(
            try settled.integer("gestureBuilds"), 0,
            "No complete-network rebuild may enter during a map gesture.")

        XCTAssertEqual(settled.fields["network"], "rendered")
        XCTAssertGreaterThan(
            try settled.integer("lines"), 0,
            "The complete network became empty after zoom settled.")
        XCTAssertGreaterThan(
            try settled.integer("overlays"), 0,
            "No railway overlay remained after zoom settled.")
        XCTAssertEqual(
            try settled.integer("covered"), 1,
            "The installed network geometry did not cover the settled viewport.")
        attach(XCUIScreen.main.screenshot(), named: "\(attachmentName)-final")
#else
        throw XCTSkip("Pinch/rotate gestures are unavailable on Mac Catalyst")
#endif
    }

    private func launch(camera: Camera) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchEnvironment["RAILMAP_UI_TEST_STORAGE_ID"] = UUID().uuidString
        app.launchArguments = ["-AppleLanguages", "(en)", "-AppleLocale", "en_US",
                               "-AppleInterfaceStyle", "Light", "-appearance", "light"]
        app.launchEnvironment["RAILMAP_UI_TEST_TAB"] = "all"
        app.launchEnvironment["RAILMAP_UI_TEST_STATS_REGION"] = "all"
        app.launchEnvironment["RAILMAP_UI_TEST_STAGE"] = "compact"
        app.launchEnvironment["RAILMAP_UI_TEST_LAYERS"] = "network"
        app.launchEnvironment["RAILMAP_UI_TEST_GESTURE_TARGET"] = "1"
        app.launchEnvironment["RAILMAP_UI_TEST_JOURNEY_INVENTORY"] = "1"
        switch camera {
        case .japan:
            // Explicit framing starts Japanese resource loading on a fresh
            // simulator instead of waiting for those resources first.
            app.launchEnvironment["RAILMAP_UI_TEST_CAMERA"] = "37,138,24"
        case .tokyo:
            app.launchEnvironment["RAILMAP_UI_TEST_CAMERA"] = "35.68,139.75,0.12"
        }
        app.launch()
        return app
    }

    /// Wait for a renderer publication rather than sleeping for a guessed
    /// rebuild time. Polling happens only before or after the gestures, so the
    /// accessibility snapshots cannot inflate the measured callback gap.
    private func waitForRenderedNetwork(
        _ element: XCUIElement,
        afterRebuild: Int? = nil,
        afterCamera: Double? = nil,
        afterViewportWidth: Double? = nil,
        afterHeading: Double? = nil,
        near center: (latitude: Double, longitude: Double)? = nil,
        minimumCamera: Double? = nil,
        timeout: TimeInterval
    ) throws -> RenderSnapshot {
        let deadline = Date().addingTimeInterval(timeout)
        var last = RenderSnapshot(element.label)
        while Date() < deadline {
            let candidate = RenderSnapshot(element.label)
            last = candidate
            let rebuilt = afterRebuild.map {
                (candidate.integerIfPresent("rebuilds") ?? Int.min) > $0
            } ?? true
            let cameraMoved = afterCamera.map {
                abs((candidate.doubleIfPresent("camera") ?? $0) - $0) > 0.3
            } ?? true
            let resized = afterViewportWidth.map {
                abs((candidate.doubleIfPresent("viewportWidth") ?? $0) - $0) > 1
            } ?? true
            let cameraReady = minimumCamera.map {
                (candidate.doubleIfPresent("camera") ?? 0) >= $0
            } ?? true
            let centerReady = center.map {
                abs((candidate.doubleIfPresent("centerLat") ?? 0) - $0.latitude) < 0.1
                    && abs((candidate.doubleIfPresent("centerLon") ?? 0) - $0.longitude) < 0.1
            } ?? true
            let rotated = afterHeading.map {
                let delta = abs((candidate.doubleIfPresent("heading") ?? $0) - $0)
                    .truncatingRemainder(dividingBy: 360)
                return min(delta, 360 - delta) > 15
            } ?? true
            if rebuilt, cameraMoved, resized, cameraReady, centerReady, rotated,
               candidate.fields["network"] == "rendered",
               (candidate.integerIfPresent("lines") ?? 0) > 0,
               (candidate.integerIfPresent("overlays") ?? 0) > 0,
               candidate.integerIfPresent("covered") == 1 {
                return candidate
            }
            Thread.sleep(forTimeInterval: 0.75)
        }

        XCTFail("The network did not publish a covered rendered state: \(last.raw)")
        return last
    }

    private func attach(_ text: String, named name: String) {
        print("[\(name)] \(text)")
        let attachment = XCTAttachment(string: text)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func attach(_ screenshot: XCUIScreenshot, named name: String) {
        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}

private extension MapZoomPerformanceTests {
    enum Camera {
        case japan
        case tokyo

        var center: (latitude: Double, longitude: Double) {
            switch self {
            case .japan: (37, 138)
            case .tokyo: (35.68, 139.75)
            }
        }
    }

    struct RenderSnapshot {
        let raw: String
        let fields: [String: String]

        init(_ raw: String) {
            self.raw = raw
            fields = Dictionary(
                raw.split(separator: ";").compactMap { part in
                    guard let separator = part.firstIndex(of: ":") else { return nil }
                    return (
                        String(part[..<separator]),
                        String(part[part.index(after: separator)...])
                    )
                },
                uniquingKeysWith: { _, latest in latest })
        }

        func integerIfPresent(_ name: String) -> Int? {
            fields[name].flatMap(Int.init)
        }

        func doubleIfPresent(_ name: String) -> Double? {
            fields[name].flatMap(Double.init)
        }

        func integer(_ name: String) throws -> Int {
            try XCTUnwrap(
                integerIfPresent(name),
                "Missing integer field \(name) in renderer status: \(raw)")
        }

        func double(_ name: String) throws -> Double {
            try XCTUnwrap(
                doubleIfPresent(name),
                "Missing numeric field \(name) in renderer status: \(raw)")
        }
    }
}
