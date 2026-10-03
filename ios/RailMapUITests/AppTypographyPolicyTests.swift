import XCTest
import UIKit

@MainActor
final class AppTypographyPolicyTests: XCTestCase {
    override func setUp() {
        super.setUp()
        continueAfterFailure = false
    }

    func testSystemTextSizeStaysWithinPermanentAppBounds() {
        assertBounds(launchCategory: nil)
    }

    func testAX5LaunchOverrideStillUsesXLarge() {
        assertBounds(launchCategory: .accessibilityExtraExtraExtraLarge, expectedSize: "xLarge")
    }

    func testOrdinaryLargeTextRemainsLarge() {
        assertBounds(launchCategory: .large, expectedSize: "large")
    }

    private func assertBounds(launchCategory: UIContentSizeCategory?, expectedSize: String? = nil) {
        let app = XCUIApplication()
        app.launchEnvironment["RAILMAP_UI_TEST_STORAGE_ID"] = UUID().uuidString
        app.launchEnvironment["RAILMAP_UI_TEST_TYPOGRAPHY"] = "1"
        app.launchArguments = ["-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        if let launchCategory {
            app.launchArguments += ["-UIPreferredContentSizeCategoryName", launchCategory.rawValue]
        }
        app.launch()
        let probe = app.staticTexts["appTypographySize"]
        XCTAssertTrue(probe.waitForExistence(timeout: 15))
        let values = Dictionary((probe.value as? String ?? "").split(separator: ";").compactMap { field in
            let parts = field.split(separator: ":", maxSplits: 1)
            return parts.count == 2 ? (String(parts[0]), String(parts[1])) : nil
        }, uniquingKeysWith: { _, last in last })
        XCTAssertTrue(["xSmall", "small", "medium", "large", "xLarge"].contains(values["size"] ?? ""),
                      "Every app surface must keep the permanent xSmall...xLarge limit: \(values).")
        if let expectedSize { XCTAssertEqual(values["size"], expectedSize) }
        let row = Double(values["subtitleRow"] ?? "") ?? .infinity
        let maximum = UIFont.preferredFont(forTextStyle: .footnote,
            compatibleWith: UITraitCollection(preferredContentSizeCategory: .extraLarge)).lineHeight
        XCTAssertLessThanOrEqual(row, Double(maximum) + 0.001,
                                 "UIKit header measurements must obey the same text-size ceiling.")
        let receipt = XCTAttachment(string: String(describing: values))
        receipt.name = "app-typography-observed-bounds"
        receipt.lifetime = .keepAlways
        add(receipt)
    }
}
