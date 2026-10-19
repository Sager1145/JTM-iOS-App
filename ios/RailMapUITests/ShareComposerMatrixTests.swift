import RailPresentation
import UIKit
import Vision
import XCTest

@MainActor
final class ShareComposerMatrixTests: XCTestCase {
    private struct Case {
        let name: String
        var preset = "japanIslands"
        var ratio = "portrait"
        var base = "all"
        var cards: String?
        var size = "medium"
        var allowsOverflow = false
        var expectsEmptyScope = false
        var expectsJourneys = false
        var expectedScopeName: String?
        var expectedLongEdge: Int?
        var expectedOverflow: Int?
    }

    override func setUp() {
        super.setUp()
        continueAfterFailure = false
    }

    func testPresetRatioMatrix() {
        continueAfterFailure = true
        let presets = ["japanIslands", "taiwan", "hongKong", "macau"]
        let ratios = ["square", "landscape", "portrait", "wide", "tall"]
        for preset in presets {
            for ratio in ratios {
                run(Case(name: "preset-\(preset)-\(ratio)", preset: preset, ratio: ratio))
            }
        }
    }

    func testBaseRegionMatrix() {
        continueAfterFailure = true
        let bases = [
            "all", "jp", "jp:hokkaido", "jp:honshu",
            "jp:shikoku", "jp:kyushu", "jp:okinawa",
        ]
        for base in bases {
            run(Case(
                name: "base-\(base.replacingOccurrences(of: ":", with: "-"))",
                base: base,
                expectsJourneys: base == "jp:honshu",
                expectedScopeName: expectedScopeName(for: base)))
        }
        run(Case(name: "base-tw-japan-islands-empty", base: "tw", expectsEmptyScope: true))
        let regionalCases = [
            Case(name: "base-tw-own", preset: "taiwan", base: "tw", expectsJourneys: true,
                 expectedScopeName: "Taiwan"),
            Case(name: "base-hk-own", preset: "hongKong", base: "hk", expectsJourneys: true,
                 expectedScopeName: "Hong Kong"),
            Case(name: "base-mo-own", preset: "macau", base: "mo", expectsJourneys: true,
                 expectedScopeName: "Macao"),
            Case(name: "base-kr-own", base: "kr", cards: "ticket:2,map:kr:small:1",
                 expectsJourneys: true, expectedScopeName: "South Korea"),
        ]
        for item in regionalCases { run(item) }
    }

    func testCustomCardMatrix() {
        continueAfterFailure = true
        let combinations = [
            Case(name: "custom-japan-pair", cards: "ticket:2,map:jp:honshu:medium:1,map:jp:kyushu:medium:1",
                 expectedScopeName: "Honshu・Kyushu"),
            Case(name: "custom-shikoku-kyushu", cards: "ticket:2,map:jp:shikoku:medium:1,map:jp:kyushu:medium:1",
                 expectedScopeName: "Shikoku・Kyushu"),
            Case(name: "custom-honshu-hokkaido", cards: "ticket:2,map:jp:honshu:medium:1,map:jp:hokkaido:medium:1",
                 expectedScopeName: "Honshu・Hokkaido"),
            Case(name: "custom-japan-taiwan", cards: "map:jp:medium:2,map:tw:tall:1,ticket:1",
                 expectedScopeName: "Japan・Taiwan"),
            Case(name: "custom-hong-kong-macau", cards: "ticket:2,map:hk:large:1,map:mo:large:1"),
            Case(name: "custom-stat-map", cards: "ticket:2,stat:coverage:medium:1,stat:distance:small:1,map:kr:small:1"),
            Case(name: "custom-japan-zoom", cards: "ticket:2,map:jp:honshu:large:1:2.0,map:jp:hokkaido:small:1:0.75"),
            Case(name: "custom-overflow", cards: "stat:rhythm:medium:2,stat:operators:large:1,ticket:2", allowsOverflow: true),
        ]
        for item in combinations { run(item) }

        let statisticKinds = [
            "recordTicket", "dailyTicket", "rhythm", "distance", "time", "coverage",
            "service", "stations", "operators", "routes", "topSegments", "regions", "lineDetail",
        ]
        for kind in statisticKinds {
            run(Case(name: "stat-\(kind)", cards: "ticket:2,stat:\(kind):large:1"))
        }
    }

    func testOverflowingMapDoesNotFilterPlacedTaiwanMapStatistics() {
        run(Case(
            name: "overflowing-japan-map", cards: "map:tw:small:1,ticket:2,map:jp:large:3",
            allowsOverflow: true, expectsJourneys: true, expectedScopeName: "Taiwan", expectedOverflow: 1))
    }

    func testMapAndDataCardShapeSpecs() {
        continueAfterFailure = true
        for shape in ["small", "medium", "tall", "large"] {
            run(Case(
                name: "shape-\(shape)",
                cards: "ticket:1,map:jp:honshu:\(shape):1,stat:distance:\(shape):1"))
        }
    }

    func testTicketMatchesStatisticsPage() {
        continueAfterFailure = true
        let scopes = [
            "jp", "tw", "hk", "mo", "kr",
            "jp:hokkaido", "jp:honshu", "jp:shikoku",
            "jp:kyushu", "jp:okinawa",
        ]
        for scope in scopes {
            let app = XCUIApplication()
            configureBaseLaunch(app)
            let parts = scope.split(separator: ":")
            app.uiTestLaunch[.statsRegion] = String(parts[0])
            if parts.count == 2 {
                app.uiTestLaunch[.statsArea] = String(parts[1])
            }
            app.uiTestLaunch[.shareBase] = "all"
            app.uiTestLaunch[.shareCards] = "ticket:2,map:\(scope):small:1"
            app.uiTestLaunch[.shareName] = "ticket-match-\(scope)"
            UITestLaunchSupport.launch(app)
            defer { app.terminate() }

            let statisticsDebug = element("statisticsDebug", in: app)
            let share = element("statisticsShareButton", in: app)
            XCTAssertTrue(share.waitForExistence(timeout: 120), "\(scope): share button missing")
            waitUntilEnabled(share, timeout: 120)
            let statisticsValue = waitForStatistics(statisticsDebug, timeout: 120)
            share.tap()
            let composerValue = waitForReady(element("shareComposerDebug", in: app), scheme: "light", timeout: 120)

            XCTAssertEqual(field("journeys", in: composerValue), field("journeys", in: statisticsValue),
                           "\(scope): stats=\(statisticsValue); share=\(composerValue)")
            let expectedKm = Double(field("km", in: statisticsValue) ?? "")
            let actualKm = Double(field("km", in: composerValue) ?? "")
            XCTAssertNotNil(expectedKm, "\(scope): invalid statistics km: \(statisticsValue)")
            XCTAssertNotNil(actualKm, "\(scope): invalid composer km: \(composerValue)")
            if let expectedKm, let actualKm {
                XCTAssertEqual(actualKm, expectedKm, accuracy: 0.1,
                               "\(scope): stats=\(statisticsValue); share=\(composerValue)")
            }
        }
    }

    func testLargePresetExportsUse2160PixelLongEdge() {
        continueAfterFailure = true
        for preset in ["japanIslands", "taiwan", "hongKong", "macau"] {
            run(Case(name: "large-\(preset)", preset: preset, size: "large",
                     expectedLongEdge: 2160))
        }
    }

    func testEditModeDragReorders() {
        let app = XCUIApplication()
        configureMotionLaunch(app)
        app.uiTestLaunch[.shareName] = "edit-drag-reorders"
        UITestLaunchSupport.launch(app)
        defer { app.terminate() }

        openComposer(in: app)
        let debug = element("shareComposerDebug", in: app)
        let initial = waitForReady(debug, scheme: "light", timeout: 120)
        let initialOrder = field("order", in: initial)
        let first = element("shareComposerCard-0", in: app)
        let third = element("shareComposerCard-2", in: app)
        XCTAssertTrue(first.waitForExistence(timeout: 8))
        XCTAssertTrue(third.waitForExistence(timeout: 8))
        XCTAssertTrue(element("shareComposerEditButton", in: app).exists)

        first.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
            .press(forDuration: 0.6,
                   thenDragTo: third.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)))

        let reordered = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            guard let value = debug.value as? String else { return false }
            return value.contains("ready=1") && self.field("order", in: value) != initialOrder
        }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [reordered], timeout: 120), .completed,
                       debug.debugDescription)
        XCTAssertTrue(element("shareComposerEditButton", in: app).exists)
    }

    func testRemoveBadge() {
        let app = XCUIApplication()
        configureMotionLaunch(app)
        app.uiTestLaunch[.shareName] = "remove-badge"
        UITestLaunchSupport.launch(app)
        defer { app.terminate() }

        openComposer(in: app)
        let debug = element("shareComposerDebug", in: app)
        let initial = waitForReady(debug, scheme: "light", timeout: 120)
        let initialCount = Int(field("cards", in: initial) ?? "")
        let edit = element("shareComposerEditButton", in: app)
        XCTAssertTrue(edit.waitForExistence(timeout: 8))
        edit.tap()
        let remove = element("shareComposerRemove-1", in: app)
        XCTAssertTrue(remove.waitForExistence(timeout: 8))
        remove.tap()

        let removed = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            guard let value = debug.value as? String,
                  let count = Int(self.field("cards", in: value) ?? "") else { return false }
            return count == (initialCount ?? 0) - 1
        }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [removed], timeout: 20), .completed,
                       debug.debugDescription)
    }

    func testDragOutsideCanvasReturnsAndAllowsNextDrag() {
        let app = XCUIApplication()
        configureMotionLaunch(app)
        app.uiTestLaunch[.shareName] = "drag-cancel-and-retry"
        UITestLaunchSupport.launch(app)
        defer { app.terminate() }

        openComposer(in: app)
        let debug = element("shareComposerDebug", in: app)
        let initialOrder = field("order", in: waitForReady(debug, scheme: "light", timeout: 120))
        let first = element("shareComposerCard-0", in: app)
        let edit = element("shareComposerEditButton", in: app)
        first.coordinate(withNormalizedOffset: CGVector(dx: 0.8, dy: 0.5))
            .press(forDuration: 0.6,
                   thenDragTo: edit.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)))

        let returned = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            guard let value = debug.value as? String else { return false }
            return value.contains("interaction=idle") && value.contains("editing=1")
                && self.field("order", in: value) == initialOrder
        }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [returned], timeout: 8), .completed,
                       debug.value as? String ?? debug.debugDescription)

        attach(app: app, debugValue: debug.value as? String ?? "", name: "drag-returned")

        // The next gesture starts away from the card center: the grab point
        // must remain stable, and cancellation must release the gesture owner.
        let third = element("shareComposerCard-2", in: app)
        let destination = third.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
            .withOffset(CGVector(dx: first.frame.width * 0.3, dy: 0))
        first.coordinate(withNormalizedOffset: CGVector(dx: 0.8, dy: 0.5))
            .press(forDuration: 0.1,
                   thenDragTo: destination)
        let reordered = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            guard let value = debug.value as? String else { return false }
            return value.contains("interaction=idle") && self.field("order", in: value) != initialOrder
        }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [reordered], timeout: 8), .completed,
                       debug.value as? String ?? debug.debugDescription)
        attach(app: app, debugValue: debug.value as? String ?? "", name: "drag-reordered-after-cancel")
    }

    func testComposerUsesFullWindow() {
        let app = XCUIApplication()
        configureMotionLaunch(app)
        UITestLaunchSupport.launch(app)
        defer { app.terminate() }

        openComposer(in: app)
        let composer = element("shareComposer", in: app)
        let window = app.windows.firstMatch.frame
        let frame = composer.frame
        XCTAssertEqual(frame.minX, window.minX, accuracy: 2)
        XCTAssertEqual(frame.maxX, window.maxX, accuracy: 2)
        XCTAssertEqual(frame.minY, window.minY, accuracy: 2)
        XCTAssertEqual(frame.maxY, window.maxY, accuracy: 2)
        attach(app: app, debugValue: "window=\(window); composer=\(frame)", name: "full-window-composer")

        app.buttons["Cancel"].tap()
        XCTAssertTrue(element("statisticsShareButton", in: app).waitForExistence(timeout: 8))
        XCTAssertFalse(composer.exists)
    }

    // Device Hub changes the real Duo posture while this test waits at each
    // marker. Keep the same app and composer alive throughout both changes.
    func testDuoComposerPreservesLayoutAcrossPostures() throws {
        let environment = ProcessInfo.processInfo.environment
        try XCTSkipUnless(environment["DUO_SHARE_POSTURE_TEST"] == "1"
                          || environment["TEST_RUNNER_DUO_SHARE_POSTURE_TEST"] == "1",
                          "Requires a coordinated Device Hub posture operator.")
        let app = XCUIApplication()
        configureMotionLaunch(app)
        app.uiTestLaunch[.shareName] = "duo-posture-sharing"
        // All drag endpoints must be on-screen in the shorter open display.
        app.uiTestLaunch[.shareRatio] = "square"
        UITestLaunchSupport.launch(app)
        defer { app.terminate() }
        openComposer(in: app)
        let debug = element("shareComposerDebug", in: app)
        _ = waitForReady(debug, scheme: "light", timeout: 120)
        assertComposerFillsWindow(app)
        let expandedWidth = app.windows.firstMatch.frame.width
        dragAndWaitForReorder(app, debug: debug, duration: 0.6)
        let expandedLayout = debug.value as? String ?? ""
        attach(app: app, debugValue: expandedLayout, name: "duo-expanded-drag")

        print("DUO_SHARE_WAIT_CLOSED")
        let folded = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            app.windows.firstMatch.frame.width < expandedWidth - 50
        }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [folded], timeout: 180), .completed)
        let foldedLayout = waitForReady(debug, scheme: "light", timeout: 120)
        assertComposerFillsWindow(app)
        for key in ["order", "layout", "cards", "overflow", "ratio", "editing"] {
            XCTAssertEqual(field(key, in: foldedLayout), field(key, in: expandedLayout), key)
        }
        dragAndWaitForReorder(app, debug: debug, duration: 0.1)
        let reorderedFoldedLayout = debug.value as? String ?? ""
        attach(app: app, debugValue: reorderedFoldedLayout, name: "duo-folded-drag")

        print("DUO_SHARE_WAIT_OPEN")
        let unfolded = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            abs(app.windows.firstMatch.frame.width - expandedWidth) < 2
        }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [unfolded], timeout: 180), .completed)
        let finalLayout = waitForReady(debug, scheme: "light", timeout: 120)
        assertComposerFillsWindow(app)
        for key in ["order", "layout", "cards", "overflow", "ratio", "editing"] {
            XCTAssertEqual(field(key, in: finalLayout), field(key, in: reorderedFoldedLayout), key)
        }
        dragAndWaitForReorder(app, debug: debug, duration: 0.1)
        attach(app: app, debugValue: debug.value as? String ?? "", name: "duo-reopened-drag")
    }

    private func assertComposerFillsWindow(_ app: XCUIApplication) {
        let window = app.windows.firstMatch.frame
        let composer = element("shareComposer", in: app).frame
        XCTAssertEqual(composer.minX, window.minX, accuracy: 2)
        XCTAssertEqual(composer.maxX, window.maxX, accuracy: 2)
        XCTAssertEqual(composer.minY, window.minY, accuracy: 2)
        XCTAssertEqual(composer.maxY, window.maxY, accuracy: 2)
    }

    private func dragAndWaitForReorder(_ app: XCUIApplication, debug: XCUIElement,
                                      duration: TimeInterval) {
        let order = field("order", in: debug.value as? String ?? "")
        let first = element("shareComposerCard-0", in: app)
        let third = element("shareComposerCard-2", in: app)
        let window = app.windows.firstMatch.frame
        XCTAssertTrue(window.contains(CGPoint(x: first.frame.midX, y: first.frame.midY)),
                      "Drag source must be visible: \(first.frame), window \(window)")
        XCTAssertTrue(window.contains(CGPoint(x: third.frame.midX, y: third.frame.midY)),
                      "Drag destination must be visible: \(third.frame), window \(window)")
        first.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
            .press(forDuration: duration,
                   thenDragTo: third.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)))
        let settled = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            guard let value = debug.value as? String else { return false }
            return value.contains("ready=1") && value.contains("interaction=idle")
                && self.field("order", in: value) != order
        }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [settled], timeout: 12), .completed,
                       debug.value as? String ?? debug.debugDescription)
    }

    func testCardMeaningsScopesAndMultipleTickets() throws {
        let app = XCUIApplication()
        configureMotionLaunch(app)
        app.uiTestLaunch[.shareRatio] = "square"
        app.uiTestLaunch[.shareCards] = "stat:distance:small:1,stat:time:small:1,stat:coverage:small:1,ticket:1,ticket:1"
        app.uiTestLaunch[.shareName] = "card-semantics"
        UITestLaunchSupport.launch(app)
        defer { app.terminate() }
        openComposer(in: app)
        let debug = element("shareComposerDebug", in: app)
        let ready = waitForReady(debug, scheme: "light", timeout: 120)
        XCTAssertEqual(field("cards", in: ready), "5")
        XCTAssertEqual(field("overflow", in: ready), "0")
        let distance = try recognizedCardText(0, app: app, debugValue: ready)
        let time = try recognizedCardText(1, app: app, debugValue: ready)
        let coverage = try recognizedCardText(2, app: app, debugValue: ready)
        XCTAssertTrue(distance.contains("Longest trip"), distance)
        XCTAssertTrue(time.contains("Longest time"), time)
        for text in [distance, time] {
            XCTAssertTrue(text.contains("2026"), text)
            XCTAssertNotNil(text.range(of: "[0-9]{1,2}:[0-9]{2}", options: .regularExpression), text)
        }
        XCTAssertTrue(coverage.contains("Taiwan"), coverage)
        attach(app: app, debugValue: [ready, distance, time, coverage].joined(separator: "\n"),
               name: "card-semantics-export")

        let add = element("shareComposerAddCard", in: app)
        for _ in 0..<5 where !add.isHittable { scrollComposer(app, up: true) }
        XCTAssertTrue(add.isHittable, app.debugDescription)
        add.tap()
        element("shareComposerAddTicket", in: app).tap()
        let added = waitForReady(debug, scheme: "light", timeout: 120)
        XCTAssertEqual(field("cards", in: added), "6")

        let coverageCard = element("shareComposerCard-2", in: app)
        for _ in 0..<5 where !coverageCard.isHittable { scrollComposer(app, up: false) }
        XCTAssertTrue(coverageCard.isHittable, app.debugDescription + "\n" + (debug.value as? String ?? ""))
        coverageCard.tap()
        let selected = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            guard let value = debug.value as? String else { return false }
            return self.field("selectedCard", in: value) == "2"
        }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [selected], timeout: 5), .completed,
                       debug.value as? String ?? "Missing card selection")
        let region = element("shareComposerCardRegion", in: app)
        for _ in 0..<5 where !region.isHittable { scrollComposer(app, up: true) }
        XCTAssertTrue(region.isHittable, app.debugDescription)
        region.tap()
        app.buttons["Japan"].firstMatch.tap()
        XCTAssertTrue(app.buttons["Honshu"].firstMatch.waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["Kanto"].exists)
        XCTAssertFalse(app.buttons["Tohoku"].exists)
        app.buttons["Honshu"].firstMatch.tap()
        let scoped = waitForReady(debug, scheme: "light", timeout: 120)
        XCTAssertEqual(field("scope", in: scoped), field("scope", in: ready))
        let cardScopes = (field("cardScopes", in: scoped) ?? "").components(separatedBy: "~")
        XCTAssertEqual(cardScopes.count, 6)
        XCTAssertTrue(cardScopes[2].hasPrefix("jp|"), scoped)
        XCTAssertEqual(cardScopes[0], "tw|*")
        attach(app: app, debugValue: scoped, name: "coverage-independent-honshu")

        // Selection and drag share recognizers: verify both drag modes after changing scope.
        let first = element("shareComposerCard-0", in: app)
        for _ in 0..<5 where !first.isHittable { scrollComposer(app, up: false) }
        XCTAssertTrue(first.isHittable)
        let third = element("shareComposerCard-2", in: app)
        XCTAssertTrue(third.isHittable)
        func waitForOrderChange(from order: String?) -> String {
            let changed = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
                guard let value = debug.value as? String else { return false }
                return self.field("order", in: value) != order
                    && self.field("interaction", in: value) == "idle" && value.contains("ready=1")
            }, object: nil)
            XCTAssertEqual(XCTWaiter.wait(for: [changed], timeout: 120), .completed,
                           debug.value as? String ?? "Missing drag result")
            return debug.value as? String ?? ""
        }
        let beforeLongPress = field("order", in: debug.value as? String ?? "")
        first.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
            .press(forDuration: 0.6,
                   thenDragTo: third.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)))
        let longPressed = waitForOrderChange(from: beforeLongPress)
        XCTAssertEqual(field("editing", in: longPressed), "1")
        first.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
            .press(forDuration: 0.1,
                   thenDragTo: third.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)))
        let editDragged = waitForOrderChange(from: field("order", in: longPressed))
        attach(app: app, debugValue: editDragged, name: "card-selection-and-both-drag-modes")
    }

    private func scrollComposer(_ app: XCUIApplication, up: Bool) {
        let scroll = app.windows.firstMatch
        // Use the visible window gutter; ScrollView bounds may include offscreen content.
        print("Composer scroll window=\(scroll.frame), canvas=\(element("shareComposerCard-2", in: app).frame)")
        let start = scroll.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: up ? 0.8 : 0.25))
        let end = scroll.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: up ? 0.25 : 0.8))
        start.press(forDuration: 0.01, thenDragTo: end)
    }

    private func recognizedCardText(_ index: Int, app: XCUIApplication, debugValue: String) throws -> String {
        let numbers = (field("canvas", in: debugValue) ?? "")
            .components(separatedBy: CharacterSet(charactersIn: "0123456789.-").inverted)
            .compactMap(Double.init)
        XCTAssertEqual(numbers.count, 4)
        guard numbers.count == 4 else { return "" }
        let canvas = CGRect(x: numbers[0], y: numbers[1], width: numbers[2], height: numbers[3])
        let url = URL(fileURLWithPath: matrixDirectory).appendingPathComponent("card-semantics.png")
        let image = try XCTUnwrap(UIImage(contentsOfFile: url.path)?.cgImage)
        let frame = element("shareComposerCard-\(index)", in: app).frame
        let crop = CGRect(x: (frame.minX - canvas.minX) / canvas.width * CGFloat(image.width),
                          y: (frame.minY - canvas.minY) / canvas.height * CGFloat(image.height),
                          width: frame.width / canvas.width * CGFloat(image.width),
                          height: frame.height / canvas.height * CGFloat(image.height))
        let cardImage = try XCTUnwrap(image.cropping(to: crop))
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.recognitionLanguages = ["en-US"]
        try VNImageRequestHandler(cgImage: cardImage).perform([request])
        return (request.results ?? []).compactMap { $0.topCandidates(1).first?.string }.joined(separator: "\n")
    }

    func testCompactCardsFillTicketGaps() {
        let app = XCUIApplication()
        configureMotionLaunch(app)
        app.uiTestLaunch[.shareRatio] = "square"
        app.uiTestLaunch[.shareCards] =
            "ticket:1,stat:distance:small:1,stat:time:mini:1,stat:rides:mini:1,stat:coverage:strip:1"
        app.uiTestLaunch[.shareName] = "compact-ticket-fillers"
        UITestLaunchSupport.launch(app)
        defer { app.terminate() }

        openComposer(in: app)
        let debug = element("shareComposerDebug", in: app)
        let light = waitForReady(debug, scheme: "light", timeout: 120)
        XCTAssertEqual(field("cards", in: light), "5", light)
        XCTAssertEqual(field("overflow", in: light), "0", light)
        for index in 0..<5 {
            XCTAssertTrue(element("shareComposerCard-\(index)", in: app).exists, light)
        }
        assertExport(debugValue: light, name: "compact-ticket-fillers", caseName: "compact-light",
                     expectedLongEdge: 1620, expectedRatio: "square")
        attachCompactExport(appearance: "light")
        attach(app: app, debugValue: light, name: "compact-ticket-fillers-light")

        element("shareComposerAppearance", in: app).tap()
        let dark = waitForReady(debug, scheme: "dark", timeout: 120)
        XCTAssertEqual(field("overflow", in: dark), "0", dark)
        assertExport(debugValue: dark, name: "compact-ticket-fillers", caseName: "compact-dark",
                     expectedLongEdge: 1620, expectedRatio: "square")
        attachCompactExport(appearance: "dark")
        attach(app: app, debugValue: dark, name: "compact-ticket-fillers-dark")
    }

    private func attachCompactExport(appearance: String) {
        let url = URL(fileURLWithPath: matrixDirectory, isDirectory: true)
            .appendingPathComponent("compact-ticket-fillers.png")
        let attachment = XCTAttachment(contentsOfFile: url)
        attachment.name = "compact-ticket-fillers-\(appearance)-export"
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func run(_ item: Case) {
        let app = XCUIApplication()
        configureBaseLaunch(app)
        app.uiTestLaunch[.sharePreset] = item.preset
        app.uiTestLaunch[.shareRatio] = item.ratio
        app.uiTestLaunch[.shareBase] = item.base
        app.uiTestLaunch[.shareSize] = item.size
        if let cards = item.cards { app.uiTestLaunch[.shareCards] = cards }
        app.uiTestLaunch[.shareName] = item.name
        UITestLaunchSupport.launch(app)
        defer { app.terminate() }

        let share = element("statisticsShareButton", in: app)
        XCTAssertTrue(share.waitForExistence(timeout: 120), "\(item.name): \(app.debugDescription)")
        waitUntilEnabled(share, timeout: 120)
        share.tap()
        XCTAssertTrue(element("shareComposer", in: app).waitForExistence(timeout: 8), item.name)

        let debug = element("shareComposerDebug", in: app)
        let lightValue = waitForReady(debug, scheme: "light", timeout: 120)
        if !item.allowsOverflow { XCTAssertTrue(lightValue.contains(";overflow=0;"), "\(item.name): \(lightValue)") }
        if let expected = item.expectedOverflow {
            XCTAssertEqual(Int(field("overflow", in: lightValue) ?? ""), expected, lightValue)
        }
        if item.expectsEmptyScope {
            XCTAssertTrue(lightValue.contains(";scope=|*;"), "\(item.name): \(lightValue)")
            XCTAssertTrue(element("shareComposerScopeWarning", in: app).exists, item.name)
        }
        if let expected = item.expectedScopeName {
            XCTAssertEqual(field("scopeName", in: lightValue), expected, "\(item.name): \(lightValue)")
        }
        if item.expectsJourneys {
            XCTAssertGreaterThan(Int(field("journeys", in: lightValue) ?? "") ?? 0, 0,
                                 "\(item.name): \(lightValue)")
        }
        XCTAssertTrue(lightValue.contains("scheme=light"), "\(item.name): \(lightValue)")
        assertExport(debugValue: lightValue, name: item.name, caseName: item.name,
                     expectedLongEdge: item.expectedLongEdge, expectedRatio: item.ratio)
        attach(app: app, debugValue: lightValue, name: "\(item.name)-light")

        let appearance = element("shareComposerAppearance", in: app)
        XCTAssertTrue(appearance.waitForExistence(timeout: 8), item.name)
        appearance.tap()
        let darkValue = waitForReady(debug, scheme: "dark", timeout: 120)
        if !item.allowsOverflow { XCTAssertTrue(darkValue.contains(";overflow=0;"), "\(item.name): \(darkValue)") }
        assertExport(debugValue: darkValue, name: item.name, caseName: item.name,
                     expectedLongEdge: item.expectedLongEdge, expectedRatio: item.ratio)
        attach(app: app, debugValue: darkValue, name: "\(item.name)-dark")
    }

    private func configureMotionLaunch(_ app: XCUIApplication) {
        configureBaseLaunch(app)
        // These cases exercise interaction, not multi-country statistics or
        // map snapshots. Keep the same ticket and three 1x1 grid footprints.
        app.uiTestLaunch[.sample] = "train-store-tw"
        app.uiTestLaunch[.region] = "tw"
        app.uiTestLaunch[.statsRegion] = "tw"
        app.uiTestLaunch[.shareBase] = "tw"
        app.uiTestLaunch[.shareCards] =
            "ticket:1,stat:coverage:small:1,stat:distance:small:1,stat:time:small:1"
    }

    private func configureBaseLaunch(_ app: XCUIApplication) {
        app.launchArguments = ["-AppleLanguages", "(en)", "-AppleLocale", "en_US", "-interface-language", "en"]
        app.uiTestLaunch[.storageId] = UUID().uuidString
        app.uiTestLaunch[.tab] = "stats"
        app.uiTestLaunch[.stage] = "expanded"
        app.uiTestLaunch[.sample] =
            "train-store,train-store-tw,train-store-hk,train-store-mo,train-store-kr"
        app.uiTestLaunch[.shareScheme] = "light"
        app.uiTestLaunch[.shareSize] = "medium"
        app.uiTestLaunch[.shareExportDir] = matrixDirectory
    }

    private var matrixDirectory: String {
        ProcessInfo.processInfo.environment["TEST_RUNNER_SHARE_MATRIX_DIR"] ?? "/tmp/share-matrix"
    }

    private func expectedScopeName(for base: String) -> String {
        let names = [
            "all": "Japan", "jp": "Japan", "jp:hokkaido": "Hokkaido", "jp:honshu": "Honshu",
            "jp:shikoku": "Shikoku", "jp:kyushu": "Kyushu",
            "jp:okinawa": "Okinawa", "tw": "Taiwan", "hk": "Hong Kong", "mo": "Macao", "kr": "South Korea",
        ]
        return names[base] ?? base
    }

    private func waitForReady(_ element: XCUIElement, scheme: String, timeout: TimeInterval) -> String {
        XCTAssertTrue(element.waitForExistence(timeout: timeout))
        let ready = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            guard let value = element.value as? String else { return false }
            return value.contains("ready=1") && value.contains("scheme=\(scheme)")
        }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [ready], timeout: timeout), .completed, element.debugDescription)
        return element.value as? String ?? ""
    }

    private func waitForStatistics(_ element: XCUIElement, timeout: TimeInterval) -> String {
        XCTAssertTrue(element.waitForExistence(timeout: timeout))
        let ready = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            guard let value = element.value as? String else { return false }
            return self.field("km", in: value) != "-1"
        }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [ready], timeout: timeout), .completed, element.debugDescription)
        return element.value as? String ?? ""
    }

    private func assertExport(
        debugValue: String, name: String, caseName: String, expectedLongEdge: Int? = nil,
        expectedRatio: String = "portrait"
    ) {
        XCTAssertEqual(field("ratio", in: debugValue), expectedRatio,
                       "\(caseName): requested canvas ratio was not applied")
        guard let encoded = field("px", in: debugValue) else {
            XCTFail("\(caseName): missing px in \(debugValue)")
            return
        }
        let dimensions = encoded.split(separator: "x").compactMap { Int($0) }
        let url = URL(fileURLWithPath: matrixDirectory, isDirectory: true)
            .appendingPathComponent(name).appendingPathExtension("png")
        guard dimensions.count == 2, let image = UIImage(contentsOfFile: url.path), let cgImage = image.cgImage else {
            XCTFail("\(caseName): missing/invalid PNG at \(url.path); debug=\(debugValue)")
            return
        }
        XCTAssertEqual(cgImage.width, dimensions[0], "\(caseName): width at \(url.path)")
        XCTAssertEqual(cgImage.height, dimensions[1], "\(caseName): height at \(url.path)")
        // Literal ratio contract, independent of the app's pixel-size calculation.
        let aspects = ["square": 1.0, "landscape": 4.0 / 3.0, "portrait": 3.0 / 4.0,
                       "wide": 16.0 / 9.0, "tall": 9.0 / 16.0]
        guard let aspect = aspects[expectedRatio], cgImage.width > 0, cgImage.height > 0 else {
            XCTFail("\(caseName): unknown ratio or empty PNG")
            return
        }
        if aspect >= 1 {
            XCTAssertEqual(Double(cgImage.height), Double(cgImage.width) / aspect, accuracy: 0.5,
                           "\(caseName): exported PNG must have the requested ratio")
        } else {
            XCTAssertEqual(Double(cgImage.width), Double(cgImage.height) * aspect, accuracy: 0.5,
                           "\(caseName): exported PNG must have the requested ratio")
        }
        if let expectedLongEdge {
            XCTAssertEqual(max(cgImage.width, cgImage.height), expectedLongEdge,
                           "\(caseName): long edge at \(url.path)")
        }
    }

    private func field(_ name: String, in value: String) -> String? {
        value.split(separator: ";").first { $0.hasPrefix("\(name)=") }
            .map { String($0.dropFirst(name.count + 1)) }
    }

    private func waitUntilEnabled(_ element: XCUIElement, timeout: TimeInterval) {
        let ready = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in element.exists && element.isEnabled }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [ready], timeout: timeout), .completed)
    }

    private func openComposer(in app: XCUIApplication) {
        let share = element("statisticsShareButton", in: app)
        XCTAssertTrue(share.waitForExistence(timeout: 120), app.debugDescription)
        // A cold statistics load under a busy host can take minutes.
        waitUntilEnabled(share, timeout: 600)
        share.tap()
        XCTAssertTrue(element("shareComposer", in: app).waitForExistence(timeout: 8))
    }

    private func attach(app: XCUIApplication, debugValue: String, name: String) {
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = name
        screenshot.lifetime = .keepAlways
        add(screenshot)
        let debug = XCTAttachment(string: debugValue)
        debug.name = "\(name)-debug"
        debug.lifetime = .keepAlways
        add(debug)
    }

    private func element(_ identifier: String, in app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: identifier).firstMatch
    }
}
