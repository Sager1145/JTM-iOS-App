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

    @Test("Suspension uses one in-place bank with dated overlay styling")
    func suspensionBoundaryControlsPartsStationsAndStyle() {
        let suspended = DisplayTemporalDecoration(
            historyId: "isumi.opening", validFrom: "2008-08-09", validTo: "2024-10-05",
            suspensionPeriodID: "isumi.suspension")
        for station in [false, true] {
            #expect(DisplayNetworkEra.current.shows(
                suspended, today: "2024-10-04", rideDate: nil, isStation: station))
            #expect(!DisplayNetworkEra.current.shows(
                suspended, today: "2024-10-05", rideDate: nil, isStation: station))
            #expect(DisplayNetworkEra.rideDate.shows(
                suspended, today: "2026-10-26", rideDate: "2024-10-04", isStation: station))
            #expect(!DisplayNetworkEra.rideDate.shows(
                suspended, today: "2026-10-26", rideDate: "2024-10-05", isStation: station))
            #expect(!DisplayNetworkEra.rideDate.shows(
                suspended, today: "2026-10-26", rideDate: "2008-08-08", isStation: station))
            #expect(DisplayNetworkEra.rideDate.shows(
                suspended, today: "2026-10-26", rideDate: "2008-08-09", isStation: station))
            #expect(DisplayNetworkEra.historicalOverlay.shows(
                suspended, today: "2024-10-05", rideDate: nil, isStation: station))
            #expect(!DisplayNetworkEra.historicalOverlay.shows(
                suspended, today: "2008-08-08", rideDate: nil, isStation: station))
        }
        #expect(DisplayNetworkEra.historicalOverlay.strokeStyle(
            for: suspended, today: "2024-10-04", rideDate: nil) == .solid)
        #expect(DisplayNetworkEra.historicalOverlay.strokeStyle(
            for: suspended, today: "2024-10-05", rideDate: nil) == .historical)
        #expect(DisplayNetworkEra.rideDate.strokeStyle(
            for: suspended, today: "2026-10-26", rideDate: "2024-10-04") == .solid)
        #expect(suspended.historyId == "isumi.opening")
    }

    @Test("A suspension identity is decorated even without an opening history id")
    func suspensionIdentityIsNotUndecorated() {
        #expect(!DisplayTemporalDecoration(suspensionPeriodID: "isumi.suspension").isUndecorated)
    }


    @Test("Temporal frames retain unchanged line builds while input epochs reject stale work")
    func temporalContextSeparatesFrameIdentityFromInputGeneration() {
        let base = DisplayNetworkTemporalContext(
            era: .current, rideDate: nil,
            todayByRegion: ["jp": "2024-10-04", "hk": "2024-10-04"], generation: 7)
        let reordered = DisplayNetworkTemporalContext(
            era: .current, rideDate: nil,
            todayByRegion: ["hk": "2024-10-04", "jp": "2024-10-04"], generation: 7)
        #expect(base.cacheKey == reordered.cacheKey)
        let newInputEpoch = DisplayNetworkTemporalContext(
            era: .current, rideDate: nil, todayByRegion: base.todayByRegion, generation: 8)
        // Unrelated residency changes retain the same temporal frame; captured
        // worker identity still differs so an old completion cannot publish.
        #expect(base.cacheKey == newInputEpoch.cacheKey)
        #expect(base != newInputEpoch)
        for changed in [
            DisplayNetworkTemporalContext(era: .current, rideDate: nil,
                todayByRegion: ["jp": "2024-10-05", "hk": "2024-10-04"], generation: 7),
            DisplayNetworkTemporalContext(era: .current, rideDate: nil,
                todayByRegion: ["jp": "2024-10-04", "hk": "2024-10-05"], generation: 7),
            DisplayNetworkTemporalContext(era: .historicalOverlay, rideDate: nil,
                todayByRegion: base.todayByRegion, generation: 7),
            DisplayNetworkTemporalContext(era: .rideDate, rideDate: "2024-10-04",
                todayByRegion: base.todayByRegion, generation: 7),
        ] {
            #expect(base.cacheKey != changed.cacheKey)
        }
        let nextRideDay = DisplayNetworkTemporalContext(
            era: .rideDate, rideDate: "2024-10-05", todayByRegion: base.todayByRegion, generation: 7)
        let previousRideDay = DisplayNetworkTemporalContext(
            era: .rideDate, rideDate: "2024-10-04", todayByRegion: base.todayByRegion, generation: 7)
        #expect(previousRideDay.cacheKey != nextRideDay.cacheKey)
    }

    @Test("One immutable snapshot supplies both the frame key and its visibility day")
    func temporalContextRetainsCapturedDayAcrossCallerRefresh() {
        var regionalDays = ["jp": "2024-10-04"]
        let captured = DisplayNetworkTemporalContext(
            era: .current, rideDate: nil, todayByRegion: regionalDays, generation: 1)
        regionalDays["jp"] = "2024-10-05"
        let refreshed = DisplayNetworkTemporalContext(
            era: .current, rideDate: nil, todayByRegion: regionalDays, generation: 1)
        let suspended = DisplayTemporalDecoration(
            validTo: "2024-10-05", suspensionPeriodID: "isumi.suspension")
        #expect(captured.cacheKey != refreshed.cacheKey)
        #expect(captured.era.shows(suspended,
            today: captured.todayByRegion["jp"] ?? "", rideDate: captured.rideDate))
        #expect(!refreshed.era.shows(suspended,
            today: refreshed.todayByRegion["jp"] ?? "", rideDate: refreshed.rideDate))
    }

}
