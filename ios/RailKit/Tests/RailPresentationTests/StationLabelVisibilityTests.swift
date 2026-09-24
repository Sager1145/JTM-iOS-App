import RailPresentation
import Testing

struct StationLabelVisibilityTests {
    @Test func farViewPreservesHubsBeforeOrdinaryStations() {
        let zoom = 3.0
        #expect(StationLabelVisibility.minimumMapLibreZoom(lineCount: 4, isTerminal: false) <= zoom)
        #expect(StationLabelVisibility.minimumMapLibreZoom(lineCount: 2, isTerminal: false) > zoom)
        #expect(StationLabelVisibility.minimumMapLibreZoom(lineCount: 1, isTerminal: false) == 12)
    }

    @Test func interchangeOutranksSingleLineTerminus() {
        #expect(StationLabelVisibility.minimumMapLibreZoom(lineCount: 2, isTerminal: false)
            < StationLabelVisibility.minimumMapLibreZoom(lineCount: 1, isTerminal: true))
        #expect(StationLabelVisibility.minimumMapLibreZoom(lineCount: 4, isTerminal: true) == 0)
    }
}
