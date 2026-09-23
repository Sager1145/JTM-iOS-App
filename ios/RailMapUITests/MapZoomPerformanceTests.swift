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

    func testDenseHobokenNewportParallelBranchesRemainVisibleAcrossZoom() throws {
        try assertRepeatedZoom(camera: .hoboken, attachmentName: "hoboken-parallel-zoom")
    }

    func testDenseHudsonPennStationBundleRemainsVisibleAcrossZoom() throws {
        try assertRepeatedZoom(camera: .hudson, attachmentName: "hudson-parallel-zoom")
    }

    func testOrangeHighlandAvenueBendRemainsVisibleAcrossZoom() throws {
        try assertRepeatedZoom(camera: .orange, attachmentName: "orange-bend-zoom")
    }

    func testOrangeHighlandAvenueBendAtWiderZoomRemainsVisible() throws {
        try assertRepeatedZoom(camera: .orangeWide, attachmentName: "orange-wide-bend-zoom")
    }

    func testDenseBundleRemainsVisibleAfterRotation() throws {
        try assertRepeatedZoom(camera: .hudson, attachmentName: "rotated-hudson-zoom", rotateBeforeZoom: true)
    }

    func testOrangeBendRemainsVisibleInLandscape() throws {
        try assertRepeatedZoom(camera: .orangeWide, attachmentName: "landscape-orange-zoom", orientation: .landscapeLeft)
    }

    func testTwoFingerMapRotationThenZoomDefersGeometryBuilds() throws {
        try assertRepeatedZoom(camera: .hudson, attachmentName: "map-rotation-zoom", rotateMapBeforeZoom: true)
    }

    private func assertRepeatedZoom(
        camera: Camera, attachmentName: String,
        orientation: UIDeviceOrientation = .portrait, rotateBeforeZoom: Bool = false,
        rotateMapBeforeZoom: Bool = false
    ) throws {
        XCUIDevice.shared.orientation = orientation
        defer { XCUIDevice.shared.orientation = .portrait }
        let app = launch(camera: camera)
        let status = app.staticTexts["railMapRenderStatus"]
        XCTAssertTrue(
            status.waitForExistence(timeout: 12),
            "The DEBUG render-status probe never mounted.")

        var initial = try waitForRenderedNetwork(status, near: camera.center,
                                                minimumCamera: camera == .japan ? nil : 11, timeout: 30)
        if rotateBeforeZoom {
            let width = try initial.double("viewportWidth")
            XCUIDevice.shared.orientation = .landscapeLeft
            // A compact/docked composition swap owns a new coordinator, so its
            // rebuild counter starts over. Require the resized viewport and
            // preserved city camera rather than comparing unrelated counters.
            initial = try waitForRenderedNetwork(status, afterViewportWidth: width,
                                                near: camera.center, minimumCamera: 11, timeout: 20)
            XCTAssertGreaterThan(try initial.double("viewportWidth"), try initial.double("viewportHeight"))
        }
        attach(initial.raw, named: "\(attachmentName)-00-initial")
        let initialMap = camera.isDenseBundle || camera.isOrange
            ? try waitForVisibleRailways(app, requireAllColours: camera.isDenseBundle) : XCUIScreen.main.screenshot()
        attach(initialMap, named: "\(attachmentName)-00-initial-map")
        if camera.isDenseBundle {
            XCTAssertEqual(try initial.integer("budgetDrops"), 0)
        }
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
            if camera.isDenseBundle {
                XCTAssertEqual(
                    try settled.integer("budgetDrops"), 0,
                    "The vertex budget removed a line from the dense parallel bundle.")
                attach(try waitForVisibleRailways(app), named: "\(attachmentName)-0\(index + 1)-map")
            } else if camera.isOrange {
                XCTAssertEqual(try settled.integer("budgetDrops"), 0)
                attach(try waitForVisibleRailways(app, requireAllColours: false), named: "\(attachmentName)-0\(index + 1)-map")
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
    }

    private func launch(camera: Camera) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-AppleLanguages", "(en)", "-AppleLocale", "en_US",
                               "-AppleInterfaceStyle", "Light", "-appearance", "light",
                               // The Hoboken/Hudson/Orange cases are us stations; North America is off by default.
                               "-feature-north-america-enabled", "YES"]
        app.launchEnvironment["RAILMAP_UI_TEST_TAB"] = "all"
        app.launchEnvironment["RAILMAP_UI_TEST_STAGE"] = "compact"
        app.launchEnvironment["RAILMAP_UI_TEST_LAYERS"] = "network"
        app.launchEnvironment["RAILMAP_UI_TEST_GESTURE_TARGET"] = "1"
        switch camera {
        case .japan:
            // An explicit camera also loads Japan on a fresh simulator whose
            // default MapKit region is North America. Waiting for already
            // loaded Japanese lines before framing them deadlocks that launch.
            app.launchEnvironment["RAILMAP_UI_TEST_CAMERA"] = "37,138,24"
        case .tokyo:
            app.launchEnvironment["RAILMAP_UI_TEST_CAMERA"] = "35.68,139.75,0.12"
        case .hoboken:
            app.launchEnvironment["RAILMAP_UI_TEST_CAMERA"] = "40.731,-74.031,0.026"
        case .hudson:
            app.launchEnvironment["RAILMAP_UI_TEST_CAMERA"] = "40.749,-74.012,0.065"
        case .orange:
            app.launchEnvironment["RAILMAP_UI_TEST_CAMERA"] = "40.762,-74.234,0.04"
        case .orangeWide:
            app.launchEnvironment["RAILMAP_UI_TEST_CAMERA"] = "40.762,-74.234,0.075"
        }
        app.launch()
        return app
    }

    /// Overlay submission precedes MapKit's asynchronous rasterization. A
    /// nonzero overlay count alone passed even with an empty railway screenshot.
    /// The dense cameras contain green, blue and orange parallel tracks;
    /// Orange's bend requires green ink before taking its geometry screenshot.
    /// Exclude the controls and sheet, then require enough saturated pixels of
    /// EACH colour to distinguish the strokes from a few detached station dots.
    private func waitForVisibleRailways(_ app: XCUIApplication, requireAllColours: Bool = true) throws -> XCUIScreenshot {
        let deadline = Date().addingTimeInterval(10)
        var counts = [0, 0, 0]
        // App snapshots can crop a landscape window using stale portrait
        // bounds, producing a large black band. Capture the physical screen.
        var screenshot = XCUIScreen.main.screenshot()
        repeat {
            screenshot = XCUIScreen.main.screenshot()
            // UIKit can return a landscape screenshot with a rotated backing
            // CGImage. Draw through UIImage so the exclusion rectangle below
            // is applied in the visible screen's orientation on every device.
            let captured = screenshot.image
            let format = UIGraphicsImageRendererFormat()
            format.scale = 1
            let size = CGSize(width: captured.size.width * captured.scale,
                              height: captured.size.height * captured.scale)
            let upright = UIGraphicsImageRenderer(size: size, format: format).image { _ in
                captured.draw(in: CGRect(origin: .zero, size: size))
            }
            let source = try XCTUnwrap(upright.cgImage)
            let width = source.width, height = source.height
            var pixels = [UInt8](repeating: 0, count: width * height * 4)
            try pixels.withUnsafeMutableBytes { bytes in
                let context = try XCTUnwrap(CGContext(
                    data: bytes.baseAddress, width: width, height: height,
                    bitsPerComponent: 8, bytesPerRow: width * 4,
                    space: CGColorSpaceCreateDeviceRGB(),
                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
                        | CGBitmapInfo.byteOrder32Big.rawValue))
                context.draw(source, in: CGRect(x: 0, y: 0, width: width, height: height))
            }
            counts = [0, 0, 0]
            for y in (height / 10)..<(height * 78 / 100) {
                for x in (width / 10)..<(width * 90 / 100) {
                    let index = (y * width + x) * 4
                    let r = Int(pixels[index]), g = Int(pixels[index + 1]), b = Int(pixels[index + 2])
                    // NJ Transit uses a bluer green than PATH. Test green
                    // dominance, rather than a blue-channel cutoff which
                    // falsely rejected the visible Hudson trunk after zoom.
                    if g > 100, g * 4 > r * 5, g * 4 > b * 5 { counts[0] += 1 }
                    if b > 140, b * 4 > g * 5, r < 80 { counts[1] += 1 }
                    if r > 170, g > 65, g < 180, b < 70 { counts[2] += 1 }
                }
            }
            if (requireAllColours ? counts : [counts[0]]).allSatisfy({ $0 >= 300 }) { return screenshot }
            Thread.sleep(forTimeInterval: 0.25)
        } while Date() < deadline
        attach(screenshot, named: "missing-railway-ink")
        XCTFail("Railways did not become visible: green/blue/orange pixel counts \(counts)")
        return screenshot
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
        case hoboken
        case hudson
        case orange
        case orangeWide

        var isOrange: Bool { self == .orange || self == .orangeWide }

        var isDenseBundle: Bool { self == .hoboken || self == .hudson }

        var center: (latitude: Double, longitude: Double) {
            switch self {
            case .japan: (37, 138)
            case .tokyo: (35.68, 139.75)
            case .hoboken: (40.731, -74.031)
            case .hudson: (40.749, -74.012)
            case .orange, .orangeWide: (40.762, -74.234)
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
