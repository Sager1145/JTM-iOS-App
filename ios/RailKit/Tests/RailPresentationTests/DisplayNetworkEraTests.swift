import RailCore
import RailPresentation
import Testing

struct DisplayNetworkEraTests {
    private let today = "2026-09-24"
    private let relocation = "2020-03-14"

    private func closedInPlace() -> DisplayTemporalDecoration {
        DisplayTemporalDecoration(validTo: "2020-01-01", kind: .current)
    }

    private func notYetOpen() -> DisplayTemporalDecoration {
        DisplayTemporalDecoration(
            historyId: "jp.demo.new-west", validFrom: "2027-01-01", kind: .relocatedNew)
    }

    private func relocatedOld() -> DisplayTemporalDecoration {
        DisplayTemporalDecoration(
            historyId: "jp.demo.old-west", validTo: relocation, kind: .relocatedOld)
    }

    private func relocatedNew() -> DisplayTemporalDecoration {
        DisplayTemporalDecoration(
            historyId: "jp.demo.new-west", validFrom: relocation, kind: .relocatedNew)
    }

    private func historical() -> DisplayTemporalDecoration {
        DisplayTemporalDecoration(
            historyId: "jp.demo.historical", validTo: "2010-01-01", kind: .historical)
    }

    @Test("Undecorated geometry is shown in every era")
    func undecoratedAlwaysShown() {
        let eras: [DisplayNetworkEra] = [.current, .rideDate, .historicalOverlay]
        for era in eras {
            #expect(era.shows(nil, today: today, rideDate: nil))
            #expect(era.shows(DisplayTemporalDecoration(), today: today, rideDate: "1990-01-01"))
            #expect(era.shows(nil, today: today, rideDate: "1990-01-01", isStation: true))
        }
    }

    @Test("Current hides a closed valid_to part and a not-yet-open valid_from part")
    func currentHidesClosedAndUnopened() {
        #expect(!DisplayNetworkEra.current.shows(closedInPlace(), today: today, rideDate: nil))
        #expect(!DisplayNetworkEra.current.shows(notYetOpen(), today: today, rideDate: nil))
        #expect(DisplayNetworkEra.current.shows(relocatedNew(), today: today, rideDate: nil))
        #expect(!DisplayNetworkEra.current.shows(relocatedOld(), today: today, rideDate: nil))
        #expect(!DisplayNetworkEra.current.shows(historical(), today: today, rideDate: nil))
    }

    @Test("A nil ride date uses the Current predicate")
    func nilRideDateMatchesCurrent() {
        let samples: [DisplayTemporalDecoration?] = [
            nil, DisplayTemporalDecoration(), closedInPlace(), notYetOpen(),
            relocatedOld(), relocatedNew(), historical(),
        ]
        for sample in samples {
            #expect(
                DisplayNetworkEra.rideDate.shows(sample, today: today, rideDate: nil)
                    == DisplayNetworkEra.current.shows(sample, today: today, rideDate: nil))
        }
        #expect(!DisplayNetworkEra.rideDate.shows(
            closedInPlace(), today: today, rideDate: Dates.undated))
    }

    @Test("A ride date before a relocation shows the old alignment only")
    func rideDateBeforeRelocation() {
        let before = "2019-06-01"
        #expect(DisplayNetworkEra.rideDate.shows(relocatedOld(), today: today, rideDate: before))
        #expect(!DisplayNetworkEra.rideDate.shows(relocatedNew(), today: today, rideDate: before))
        #expect(DisplayNetworkEra.rideDate.shows(
            relocatedNew(), today: today, rideDate: relocation))
        #expect(!DisplayNetworkEra.rideDate.shows(
            relocatedOld(), today: today, rideDate: relocation))
    }

    @Test("Overlay keeps current geometry and adds historical")
    func overlayShowsHistoricalOnCurrent() {
        #expect(DisplayNetworkEra.historicalOverlay.shows(
            relocatedNew(), today: today, rideDate: nil))
        #expect(DisplayNetworkEra.historicalOverlay.shows(
            DisplayTemporalDecoration(), today: today, rideDate: nil))
        #expect(DisplayNetworkEra.historicalOverlay.shows(
            historical(), today: today, rideDate: nil))
        #expect(DisplayNetworkEra.historicalOverlay.shows(
            relocatedOld(), today: today, rideDate: nil))
        #expect(!DisplayNetworkEra.historicalOverlay.shows(
            closedInPlace(), today: today, rideDate: nil))
        #expect(DisplayNetworkEra.historicalOverlay.shows(
            closedInPlace(), today: today, rideDate: nil, isStation: true))
        #expect(DisplayNetworkEra.historicalOverlay.shows(
            DisplayTemporalDecoration(historyId: "jp.demo.mashike", kind: .historical, isOverlayStation: true),
            today: today, rideDate: nil, isStation: true))
    }

    @Test("Cross-day dash is a different style value than historical")
    func historicalMarkIsNotCrossDayDash() {
        #expect(DisplayNetworkDash.crossDay != DisplayNetworkDash.history)
        #expect(DisplayNetworkEra.strokeStyle(for: .historical) == .historical)
        #expect(DisplayNetworkEra.strokeStyle(for: .relocatedOld) == .historical)
        #expect(DisplayNetworkEra.strokeStyle(for: .relocatedNew) == .solid)
        #expect(DisplayNetworkEra.strokeStyle(for: .current) == .solid)
        #expect(DisplayNetworkStrokeStyle.historical != .crossDayDash)
        #expect(DisplayNetworkStrokeStyle.crossDayDash != DisplayNetworkEra.strokeStyle(for: .historical))
    }
}
