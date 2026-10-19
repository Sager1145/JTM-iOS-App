import RailPresentation
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
        app.uiTestLaunch[.storageId] = UUID().uuidString
        app.uiTestLaunch[.typography] = "1"
        app.launchArguments = ["-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        if let launchCategory {
            app.launchArguments += ["-UIPreferredContentSizeCategoryName", launchCategory.rawValue]
        }
        UITestLaunchSupport.launch(app)
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
        let draftFont = Double(values["draftFont"] ?? "") ?? .infinity
        let draftMaximum = UIFont.preferredFont(forTextStyle: .caption1,
            compatibleWith: UITraitCollection(preferredContentSizeCategory: .extraLarge)).pointSize
        XCTAssertLessThanOrEqual(draftFont, Double(draftMaximum) + 0.001,
                                 "Draft map pins must use the same UIKit font ceiling.")
        XCTAssertGreaterThan(Double(values["draftHeight"] ?? "") ?? 0, 0,
                             "The observed font must come from a configured, measured draft pin.")
        let receipt = XCTAttachment(string: String(describing: values))
        receipt.name = "app-typography-observed-bounds"
        receipt.lifetime = .keepAlways
        add(receipt)
    }
}
