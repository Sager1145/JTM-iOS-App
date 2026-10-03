import RailPresentation
import RailCore
import Testing

struct StationLabelVisibilityTests {
    @Test func sparseServicesOfferAllCallsButLocalTrainsPrioritizeHubs() {
        #expect(StationLabelVisibility.preservesSelectedCalls(trainType: "快速", country: "jp", callCount: 12))
        #expect(!StationLabelVisibility.preservesSelectedCalls(trainType: "快速", country: "jp", callCount: 13))
        #expect(!StationLabelVisibility.preservesSelectedCalls(trainType: "普通", country: "jp", callCount: 8))
        #expect(!StationLabelVisibility.preservesSelectedCalls(trainType: "Local", country: "ca", callCount: 8))
        #expect(StationLabelVisibility.preservesSelectedCalls(trainType: "特急", country: "jp", callCount: 20))
        #expect(!StationLabelVisibility.preservesSelectedCalls(trainType: "特急", country: "jp", callCount: 21))
    }

    @Test func denseSelectedCallsKeepImportantHubsAtOverview() {
        let hub = StationLabelVisibility.selectedRideMinimumMapLibreZoom(
            role: "stop", preservesCalls: false, densityMinimum: 10.5,
            lineCount: 4, isNetworkTerminal: false)
        let ordinary = StationLabelVisibility.selectedRideMinimumMapLibreZoom(
            role: "stop", preservesCalls: false, densityMinimum: 10.5,
            lineCount: 1, isNetworkTerminal: false)
        #expect(hub == 0)
        #expect(ordinary == 10.5)
        #expect(RideMarkerVisibility.isVisible(
            role: "stop", isSelected: true, mapLibreZoom: 3,
            minimumMapLibreZoom: 10.5, selectedCallMinimum: hub))
        #expect(!RideMarkerVisibility.isVisible(
            role: "stop", isSelected: true, mapLibreZoom: 3,
            minimumMapLibreZoom: 10.5, selectedCallMinimum: ordinary))
        #expect(RideMarkerVisibility.isVisible(
            role: "stop", isSelected: true, mapLibreZoom: 10.5,
            minimumMapLibreZoom: 10.5, selectedCallMinimum: ordinary))
    }

    @Test func sparseCallsAndBoundariesRemainVisibleButPassThroughsWait() {
        #expect(StationLabelVisibility.selectedRideMinimumMapLibreZoom(
            role: "stop", preservesCalls: true, densityMinimum: 10.5,
            lineCount: 1, isNetworkTerminal: false) == nil)
        for role in ["terminal", "xday"] {
            #expect(StationLabelVisibility.selectedRideMinimumMapLibreZoom(
                role: role, preservesCalls: false, densityMinimum: 13,
                lineCount: 0, isNetworkTerminal: false) == nil)
        }
        #expect(StationLabelVisibility.selectedRideMinimumMapLibreZoom(
            role: "pass", preservesCalls: true, densityMinimum: 13,
            lineCount: 8, isNetworkTerminal: false) == 13)
    }

    @Test func unknownStationsKeepDensityTimingAndTerminiGainPriority() {
        #expect(StationLabelVisibility.selectedRideMinimumMapLibreZoom(
            role: "stop", preservesCalls: false, densityMinimum: 11,
            lineCount: 0, isNetworkTerminal: false) == 11)
        #expect(StationLabelVisibility.selectedRideMinimumMapLibreZoom(
            role: "stop", preservesCalls: false, densityMinimum: 11,
            lineCount: 1, isNetworkTerminal: true) == 10)
        #expect(StationLabelVisibility.selectedRideMinimumMapLibreZoom(
            role: "stop", preservesCalls: false, densityMinimum: 11,
            lineCount: 2, isNetworkTerminal: false) == 9)
    }

    @Test func actualCallsOutrankEvenBusyPassThroughStations() {
        #expect(StationLabelVisibility.rideLabelPriority(role: "stop", lineCount: 1, isNetworkTerminal: false)
            > StationLabelVisibility.rideLabelPriority(role: "pass", lineCount: 50, isNetworkTerminal: false))
        #expect(StationLabelVisibility.rideLabelPriority(role: "stop", lineCount: 4, isNetworkTerminal: false)
            > StationLabelVisibility.rideLabelPriority(role: "stop", lineCount: 1, isNetworkTerminal: false))
        #expect(StationLabelVisibility.rideLabelPriority(role: "terminal", lineCount: 0, isNetworkTerminal: false)
            > StationLabelVisibility.rideLabelPriority(role: "stop", lineCount: 50, isNetworkTerminal: true))
    }

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
