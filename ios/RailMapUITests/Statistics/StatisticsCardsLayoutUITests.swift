import RailPresentation
import XCTest

/// The Stats tab shows the full cards inline; no text may be clipped at any
/// supported language or text size.
@MainActor
final class StatisticsCardsLayoutUITests: XCTestCase {
    private static let defaultSize = "UICTContentSizeCategoryL"
    private static let cappedSize = "UICTContentSizeCategoryXL"

    func testStatsCards_en_default() { run("en", "en_US", "default", Self.defaultSize) }
    func testStatsCards_en_xLarge() { run("en", "en_US", "xLarge", Self.cappedSize) }
    func testStatsCards_ja_default() { run("ja", "ja_JP", "default", Self.defaultSize) }
    func testStatsCards_ja_xLarge() { run("ja", "ja_JP", "xLarge", Self.cappedSize) }
    func testStatsCards_zhHant_default() { run("zh-Hant", "zh_TW", "default", Self.defaultSize) }
    func testStatsCards_zhHant_xLarge() { run("zh-Hant", "zh_TW", "xLarge", Self.cappedSize) }
    func testStatsCards_zhHans_default() { run("zh-Hans", "zh_CN", "default", Self.defaultSize) }
    func testStatsCards_zhHans_xLarge() { run("zh-Hans", "zh_CN", "xLarge", Self.cappedSize) }

    private func run(_ language: String, _ locale: String, _ sizeName: String, _ sizeCategory: String) {
        let app = XCUIApplication()
        app.uiTestLaunch[.storageId] = UUID().uuidString
        app.launchArguments = [
            "-AppleLanguages", "(\(language))",
            "-AppleLocale", locale,
            "-interface-language", language,
            "-UIPreferredContentSizeCategoryName", sizeCategory,
        ]
        app.uiTestLaunch[.tab] = "stats"
        app.uiTestLaunch[.stage] = "expanded"
        app.uiTestLaunch[.sample] = "new-year-grand-loop"
        app.uiTestLaunch[.statsRegion] = "jp"
        UITestLaunchSupport.launch(app)

        XCTAssertTrue(element("statisticsYearBar", in: app).waitForExistence(timeout: 120))
        let rhythm = element("statisticsRhythmColumn-1", in: app)
        var rhythmFound = false
        var previous: Data?

        for step in 0..<25 {
            let shot = app.screenshot()
            let attachment = XCTAttachment(screenshot: shot)
            attachment.name = "Stats-\(language)-\(sizeName)-\(step)"
            attachment.lifetime = .keepAlways
            add(attachment)

            assertNoCutoff(in: app, label: "\(language)/\(sizeName)/\(step)")
            if rhythm.exists { rhythmFound = true }

            let data = shot.pngRepresentation
            if let previous, previous == data { break }
            previous = data
            app.swipeUp()
        }
        XCTAssertTrue(rhythmFound, "Inline rhythm card missing (\(language)/\(sizeName))")
    }

    private func assertNoCutoff(in app: XCUIApplication, label: String) {
        let window = app.windows.firstMatch.frame
        let texts = app.staticTexts.allElementsBoundByIndex
        for text in texts where text.exists {
            let frame = text.frame
            guard frame.intersects(window), !frame.isEmpty else { continue }
            XCTAssertGreaterThan(frame.width, 0, "Zero-width text '\(text.label)' [\(label)]")
            XCTAssertGreaterThan(frame.height, 0, "Zero-height text '\(text.label)' [\(label)]")
            XCTAssertGreaterThanOrEqual(frame.minX, window.minX - 1,
                                        "Text clipped left '\(text.label)' [\(label)]")
            XCTAssertLessThanOrEqual(frame.maxX, window.maxX + 1,
                                     "Text clipped right '\(text.label)' [\(label)]")
        }
    }

    private func element(_ identifier: String, in app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: identifier).firstMatch
    }
}
