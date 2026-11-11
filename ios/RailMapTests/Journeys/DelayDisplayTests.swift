import RailCore
import Testing
@testable import RailMap

/// The delay display: actual time shown, scheduled struck beside it, signed
/// marker, all computed on clock strings (no device clock).
@MainActor
struct DelayDisplayTests {
    /// English, pinned for the test and put back after: the language is a
    /// persisted preference of the host app.
    private func english(_ body: (AppLocalization) -> Void) {
        let l = AppLocalization()
        let saved = l.language
        l.language = .en
        defer { l.language = saved }
        body(l)
    }

    private func display(_ scheduled: String?, _ actual: String?) -> StopTimingStatus.TimeDisplay? {
        StopTimingStatus.timeDisplay(scheduled: scheduled, actual: actual)
    }

    @Test func late() {
        english { l in
            let d = display("10:30", "10:35")
            #expect(d == .init(shown: "10:35", scheduled: "10:30", offsetMinutes: 5))
            #expect(StopTimingStatus.markerText(d!, localization: l) == "+5 min")
            #expect(d!.isLate)
        }
    }

    @Test func early() {
        english { l in
            let d = display("12:55", "12:52")
            #expect(d == .init(shown: "12:52", scheduled: "12:55", offsetMinutes: -3))
            #expect(StopTimingStatus.markerText(d!, localization: l) == "\u{2212}3 min")
            #expect(d!.isEarly)
        }
    }

    @Test func onTimeHasNoStruckClock() {
        english { l in
            let d = display("10:30", "10:30")
            #expect(d == .init(shown: "10:30", scheduled: nil, offsetMinutes: 0))
            #expect(StopTimingStatus.markerText(d!, localization: l) == "On time")
        }
    }

    @Test func actualOnlyHasNoMarker() {
        english { l in
            let d = display(nil, "10:35")
            #expect(d == .init(shown: "10:35"))
            #expect(StopTimingStatus.markerText(d!, localization: l) == nil)
            #expect(display("", "10:35") == .init(shown: "10:35"))
        }
    }

    @Test func scheduledOnlyAndDateOnly() {
        #expect(display("10:30", nil) == .init(shown: "10:30"))
        #expect(display("10:30", "") == .init(shown: "10:30"))
        #expect(display(nil, nil) == nil)
        #expect(display("", "") == nil)
    }

    @Test func overnightUsesServiceMinutes() {
        let d = display("23:55", "24:05")
        #expect(d?.offsetMinutes == 10)
        #expect(d?.shown == "24:05")
    }

    @Test func unparseableScheduleKeepsActualWithoutMarker() {
        #expect(display("soon", "10:35") == .init(shown: "10:35"))
    }

    @Test func spokenStrings() {
        english { l in
            let late = display("10:30", "10:35")!
            #expect(StopTimingStatus.spoken(role: "Departure", late, localization: l)
                == "Departure 10:35, scheduled 10:30, 5 min late")
            let onTime = display("10:30", "10:30")!
            #expect(StopTimingStatus.spoken(role: "Departure", onTime, localization: l)
                == "Departure 10:30, On time")
            let only = display(nil, "10:35")!
            #expect(StopTimingStatus.spoken(role: "Arrival", only, localization: l) == "Arrival 10:35")
            #expect(StopTimingStatus.spoken(role: nil, late, localization: l)
                == "10:35, scheduled 10:30, 5 min late")
        }
    }

    @Test func tripSidesUseEffectiveTimes() {
        var first = Stop(name: "A", stopType: "origin", rideSegment: true)
        first.departure = "10:30"
        first.actualDeparture = "10:35"
        var last = Stop(name: "B", stopType: "destination", rideSegment: true)
        last.arrival = "12:55"
        last.actualArrival = "12:58"
        let stops = [first, last]
        #expect(RideCardTimeText.departureDisplay(stops)?.offsetMinutes == 5)
        #expect(RideCardTimeText.arrivalDisplay(stops)?.offsetMinutes == 3)
        #expect(RideCardTimeText.departure(stops) == "10:35")
        #expect(RideCardTimeText.arrival(stops) == "12:58")
        #expect(RideCardTimeText.effective(scheduled: "10:30", actual: "10:35") == "10:35")
        #expect(RideCardTimeText.effective(scheduled: "10:30", actual: "") == "10:30")
        #expect(RideCardTimeText.effective(scheduled: nil, actual: nil) == nil)
    }

    @Test func statisticsCacheDigestSeesActualTimes() {
        var first = Stop(name: "A", stopType: "origin", rideSegment: true)
        first.departure = "10:30"
        var last = Stop(name: "B", stopType: "destination", rideSegment: true)
        last.arrival = "12:55"
        var train = Train(id: "t", date: "2026-01-01", number: "T", origin: "A", destination: "B", stops: [first, last])
        let base = MileageStatisticsStore.entryDigest(train: train, ride: nil)
        #expect(MileageStatisticsStore.entryDigest(train: train, ride: nil) == base)
        train.stops[0].actualDeparture = "10:35"
        let withDeparture = MileageStatisticsStore.entryDigest(train: train, ride: nil)
        #expect(withDeparture != base)
        train.stops[1].actualArrival = "12:58"
        #expect(MileageStatisticsStore.entryDigest(train: train, ride: nil) != withDeparture)
    }

    @Test func offsetWrapsAcrossMidnight() {
        #expect(display("23:58", "00:03")?.offsetMinutes == 5)
        #expect(display("00:03", "23:58")?.offsetMinutes == -5)
        #expect(display("10:30", "10:35")?.offsetMinutes == 5)
    }
}
