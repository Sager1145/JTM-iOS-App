import RailPresentation
import Testing

struct WorkspaceLayoutPolicyTests {
    struct ModeCase: Sendable {
        var width: Double
        var height: Double
        var isAccessibilitySize: Bool
        var expected: WorkspaceLayoutMode
    }

    @Test(
        "Composition follows content-fit breakpoints",
        arguments: [
            ModeCase(
                width: 390, height: 844, isAccessibilitySize: false,
                expected: .compactOverlay),
            ModeCase(
                width: 660, height: 844, isAccessibilitySize: false,
                expected: .compactOverlay),
            ModeCase(
                width: 661, height: 844, isAccessibilitySize: false,
                expected: .sideBySide),
            ModeCase(
                width: 1_179, height: 800, isAccessibilitySize: false,
                expected: .sideBySide),
            ModeCase(
                width: 1_180, height: 559, isAccessibilitySize: false,
                expected: .sideBySide),
            ModeCase(
                width: 1_180, height: 560, isAccessibilitySize: false,
                expected: .threeColumn),
        ])
    func composition(_ testCase: ModeCase) {
        let policy = WorkspaceLayoutPolicy(
            width: testCase.width,
            height: testCase.height,
            isAccessibilitySize: testCase.isAccessibilitySize)

        #expect(policy.mode == testCase.expected)
    }

    @Test(
        "Accessibility sizes reserve more width before adding navigation",
        arguments: [
            ModeCase(
                width: 1_180, height: 800, isAccessibilitySize: true,
                expected: .sideBySide),
            ModeCase(
                width: 1_259, height: 800, isAccessibilitySize: true,
                expected: .sideBySide),
            ModeCase(
                width: 1_260, height: 800, isAccessibilitySize: true,
                expected: .threeColumn),
        ])
    func accessibilityThreshold(_ testCase: ModeCase) {
        let policy = WorkspaceLayoutPolicy(
            width: testCase.width,
            height: testCase.height,
            isAccessibilitySize: testCase.isAccessibilitySize)

        #expect(policy.mode == testCase.expected)
    }

    @Test(
        "Reading column follows orientation and useful-width limits",
        arguments: [
            (width: 661.0, height: 900.0, expected: 360.0),
            (width: 700.0, height: 390.0, expected: 300.0),
            (width: 1_000.0, height: 700.0, expected: 340.0),
            (width: 1_500.0, height: 900.0, expected: 440.0),
        ])
    func sidePanelWidth(testCase: (width: Double, height: Double, expected: Double)) {
        let policy = WorkspaceLayoutPolicy(
            width: testCase.width,
            height: testCase.height,
            isAccessibilitySize: false)

        #expect(policy.sidePanelWidth == testCase.expected)
    }
}
