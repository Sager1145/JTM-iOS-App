import XCTest
import UIKit

/// Physical-screen checks keep the basemap free of dark blocks during camera changes.
@MainActor
final class BasemapRenderingTests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    func testBasemapRemainsClearAcrossZoomPanAndRotation() throws {
        XCUIDevice.shared.orientation = .portrait
        defer { XCUIDevice.shared.orientation = .portrait }
        let app = XCUIApplication()
        app.launchArguments = ["-AppleLanguages", "(en)", "-AppleLocale", "en_US",
                               "-AppleInterfaceStyle", "Light", "-appearance", "light",
                               "-interface-language", "en",
                               "-auto-focus-zoom", "NO"]
        app.launchEnvironment["RAILMAP_UI_TEST_TAB"] = "all"
        app.launchEnvironment["RAILMAP_UI_TEST_STATS_REGION"] = "all"
        app.launchEnvironment["RAILMAP_UI_TEST_STAGE"] = "compact"
        app.launchEnvironment["RAILMAP_UI_TEST_LAYERS"] = "network,routes"
        app.launchEnvironment["RAILMAP_UI_TEST_GESTURE_TARGET"] = "1"
        app.launchEnvironment["RAILMAP_UI_TEST_CAMERA"] = "35.68,139.75,0.12"
        app.launch()

        let status = app.staticTexts["railMapRenderStatus"]
        let target = app.otherElements["railMapGestureTarget"]
        XCTAssertTrue(status.waitForExistence(timeout: 15))
        XCTAssertTrue(target.waitForExistence(timeout: 10))
        try waitForStatus(status) {
            $0["network"] == "rendered" && self.number("covered", $0) == 1
                && abs(self.number("centerLat", $0) - 35.68) < 0.02
                && abs(self.number("centerLon", $0) - 139.75) < 0.02
        }
        _ = try waitForImage(app, target: target, name: "basemap-portrait") {
            $0.hasTexture && !$0.hasBlackBlock
        }

        let beforeZoom = fields(status.label)
        target.pinch(withScale: 2, velocity: 1)
        try waitForStatus(status) {
            $0["network"] == "rendered" && self.number("covered", $0) == 1
                && abs(self.number("camera", $0) - self.number("camera", beforeZoom)) > 0.3
        }
        let beforePan = fields(status.label)
        let start = target.coordinate(withNormalizedOffset: CGVector(dx: 0.85, dy: 0.5))
        let end = target.coordinate(withNormalizedOffset: CGVector(dx: 0.15, dy: 0.5))
        start.press(forDuration: 0.05, thenDragTo: end, withVelocity: .slow, thenHoldForDuration: 0.1)
        try waitForStatus(status) {
            self.number("covered", $0) == 1
                && abs(self.number("centerLon", $0) - self.number("centerLon", beforePan)) > 0.001
        }
        _ = try waitForImage(app, target: target, name: "basemap-portrait-after-zoom-pan") {
            $0.hasTexture && !$0.hasBlackBlock
        }

        XCUIDevice.shared.orientation = .landscapeLeft
        try waitForStatus(status) {
            self.number("viewportWidth", $0) > self.number("viewportHeight", $0)
                && self.number("covered", $0) == 1
        }
        _ = try waitForImage(app, target: target, name: "basemap-landscape") {
            $0.hasTexture && !$0.hasBlackBlock
        }
        XCUIDevice.shared.orientation = .portrait
        try waitForStatus(status) {
            self.number("viewportHeight", $0) > self.number("viewportWidth", $0)
                && self.number("covered", $0) == 1
        }
        _ = try waitForImage(app, target: target, name: "basemap-portrait-restored") {
            $0.hasTexture && !$0.hasBlackBlock
        }
    }

    private func fields(_ text: String) -> [String: String] {
        Dictionary(text.split(separator: ";").compactMap { field in
            let pair = field.split(separator: ":", maxSplits: 1)
            return pair.count == 2 ? (String(pair[0]), String(pair[1])) : nil
        }, uniquingKeysWith: { _, last in last })
    }

    private func number(_ key: String, _ fields: [String: String]) -> Double {
        fields[key].flatMap(Double.init) ?? -Double.infinity
    }

    private func waitForStatus(_ status: XCUIElement, condition: @escaping ([String: String]) -> Bool) throws {
        let ready = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            condition(self.fields(status.label))
        }, object: status)
        XCTAssertEqual(XCTWaiter.wait(for: [ready], timeout: 30), .completed, status.label)
    }

    private struct Pixels {
        let medians: [Double]
        let blackCells: [Bool]
        let columns: Int
        let rows: Int

        var hasTexture: Bool {
            guard let low = medians.min(), let high = medians.max() else { return false }
            return high - low > 6 && high > 80
        }

        // Each cell is eight screen points. A solid 32 x 32 point dark
        // rectangle is large enough to be a tile defect and cannot be a label.
        var hasBlackBlock: Bool {
            guard columns >= 4, rows >= 4 else { return true }
            for y in 0...(rows - 4) {
                for x in 0...(columns - 4) {
                    if (y..<(y + 4)).allSatisfy({ row in
                        (x..<(x + 4)).allSatisfy { blackCells[row * columns + $0] }
                    }) { return true }
                }
            }
            return false
        }
    }

    private func waitForImage(
        _ app: XCUIApplication, target: XCUIElement, name: String,
        condition: (Pixels) -> Bool
    ) throws -> Pixels {
        let deadline = Date().addingTimeInterval(10)
        var last: Pixels?
        repeat {
            // App screenshots can use stale portrait bounds after rotation.
            // Physical-screen screenshots preserve the actual map surface.
            let screenshot = XCUIScreen.main.screenshot()
            let sampled = try sample(screenshot, in: sampleRegion(app, target: target), appFrame: app.frame)
            last = sampled
            if condition(sampled) {
                attach(screenshot, name: name)
                return sampled
            }
            if Date() >= deadline {
                attach(screenshot, name: "\(name)-failed")
                let detail = XCTAttachment(string: "Map cell medians: \(sampled.medians); black block: \(sampled.hasBlackBlock)")
                detail.name = "\(name)-pixels"
                detail.lifetime = .keepAlways
                add(detail)
                XCTFail("The physical map surface did not reach the expected uniform opacity: \(name)")
                break
            }
            Thread.sleep(forTimeInterval: 0.5)
        } while true
        return try XCTUnwrap(last)
    }

    private func sampleRegion(_ app: XCUIApplication, target: XCUIElement) -> CGRect {
        var region = target.frame.insetBy(dx: 12, dy: 12)
        // The landscape dock can overlap the left edge of the gesture probe.
        // Exclude its full column; portrait panels occupy the bottom instead.
        let header = app.descendants(matching: .any)["panelHeader"].firstMatch
        if header.exists {
            if header.frame.maxX < app.frame.minX + app.frame.width * 0.75 {
                let left = max(region.minX, header.frame.maxX + 12)
                region = CGRect(x: left, y: region.minY,
                                width: max(0, region.maxX - left), height: region.height)
            } else {
                region.size.height = max(0, min(region.maxY, header.frame.minY - 12) - region.minY)
            }
        }
        return region
    }

    private func sample(_ screenshot: XCUIScreenshot, in region: CGRect, appFrame: CGRect) throws -> Pixels {
        let captured = screenshot.image
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let size = CGSize(width: captured.size.width * captured.scale, height: captured.size.height * captured.scale)
        let upright = UIGraphicsImageRenderer(size: size, format: format).image { _ in
            captured.draw(in: CGRect(origin: .zero, size: size))
        }
        let source = try XCTUnwrap(upright.cgImage)
        let width = source.width, height = source.height
        var rgba = [UInt8](repeating: 0, count: width * height * 4)
        try rgba.withUnsafeMutableBytes { bytes in
            let context = try XCTUnwrap(CGContext(data: bytes.baseAddress, width: width, height: height,
                bitsPerComponent: 8, bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue))
            context.draw(source, in: CGRect(x: 0, y: 0, width: width, height: height))
        }
        let sx = CGFloat(width) / appFrame.width, sy = CGFloat(height) / appFrame.height
        let columns = Int(region.width / 8), rows = Int(region.height / 8)
        XCTAssertGreaterThanOrEqual(columns, 4, "The unobscured map sample became too narrow")
        XCTAssertGreaterThanOrEqual(rows, 4, "The unobscured map sample became too short")
        var medians: [Double] = [], blackCells: [Bool] = []
        for row in 0..<max(0, rows) {
            for column in 0..<max(0, columns) {
                var luminances: [Double] = []
                var dark = 0
                for y in 0..<8 {
                    for x in 0..<8 {
                        let px = min(width - 1, max(0, Int((region.minX - appFrame.minX + CGFloat(column * 8 + x) + 0.5) * sx)))
                        let py = min(height - 1, max(0, Int((region.minY - appFrame.minY + CGFloat(row * 8 + y) + 0.5) * sy)))
                        let i = (py * width + px) * 4
                        let r = Double(rgba[i]), g = Double(rgba[i + 1]), b = Double(rgba[i + 2])
                        luminances.append(0.2126 * r + 0.7152 * g + 0.0722 * b)
                        if max(r, g, b) < 12 { dark += 1 }
                    }
                }
                medians.append(luminances.sorted()[32])
                blackCells.append(dark >= 60)
            }
        }
        return Pixels(medians: medians, blackCells: blackCells, columns: columns, rows: rows)
    }

    private func attach(_ screenshot: XCUIScreenshot, name: String) {
        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
