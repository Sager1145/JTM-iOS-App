import RailPresentation
import Testing

struct WorkspaceLayoutPolicyTests {
    struct ModeCase: Sendable {
        var width: Double
        var height: Double
        var expected: WorkspaceLayoutMode
    }

    @Test(
        "Composition follows content-fit breakpoints",
        arguments: [
            ModeCase(
                width: 390, height: 844,
                expected: .compactOverlay),
            ModeCase(
                width: 691, height: 844,
                expected: .compactOverlay),
            ModeCase(
                width: 692, height: 844,
                expected: .sideBySide),
            ModeCase(
                width: 1_179, height: 800,
                expected: .sideBySide),
            ModeCase(
                width: 1_180, height: 559,
                expected: .sideBySide),
            ModeCase(
                width: 1_180, height: 560,
                expected: .sideBySide),
        ])
    func composition(_ testCase: ModeCase) {
        let policy = WorkspaceLayoutPolicy(
            width: testCase.width,
            height: testCase.height)

        #expect(policy.mode == testCase.expected)
    }

    @Test(
        "Reading column follows orientation and useful-width limits",
        arguments: [
            (width: 692.0, height: 900.0, expected: 300.0),
            (width: 720.0, height: 900.0, expected: 328.0),
            (width: 768.0, height: 1_024.0, expected: 360.0),
            (width: 700.0, height: 390.0, expected: 300.0),
            (width: 1_000.0, height: 700.0, expected: 340.0),
            (width: 1_500.0, height: 900.0, expected: 440.0),
        ])
    func sidePanelWidth(testCase: (width: Double, height: Double, expected: Double)) {
        let policy = WorkspaceLayoutPolicy(
            width: testCase.width,
            height: testCase.height)

        #expect(policy.sidePanelWidth == testCase.expected)
    }

    @Test("Dock leaves a usable map at every supported window width")
    func mapClearance() {
        for width in stride(from: 692.0, through: 1_600.0, by: 1) {
            for height in [390.0, 900.0, 1_200.0] {
                let policy = WorkspaceLayoutPolicy(width: width, height: height)
                #expect(policy.sidePanelWidth >= 300)
                #expect(policy.sidePanelWidth <= 440)
                #expect(width - policy.sidePanelWidth - WorkspaceLayoutPolicy.dockInset * 2 >= 360)
            }
        }
    }
}
