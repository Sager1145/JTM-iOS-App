import Foundation
import Testing

@testable import RailPresentation

/// Which day it is where the train is.
///
/// The cases worth writing down are the ones a hand-run cannot reach: a device
/// far enough west that its day and the ride's are different days, and the
/// ninety minutes each evening in which UTC+8 and UTC+9 disagree with each
/// other. Both were wrong before ``RegionClock`` existed, and neither is
/// visible to anyone testing the app in the region it is about.
struct RegionClockTests {

    /// `2026-08-27T15:30:00Z`. Chosen because the three answers differ:
    /// 23:30 on the 27th in Taipei, 00:30 on the 28th in Tokyo, and 08:30 on
    /// the 27th in Los Angeles.
    private static let evening = Date(timeIntervalSince1970: 1_787_844_600)

    private func instant(_ iso: String) -> Date {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        guard let date = formatter.date(from: iso) else {
            Issue.record("unparsable instant \(iso)")
            return Date(timeIntervalSince1970: 0)
        }
        return date
    }

    /// Runs `body` with the process's default zone forced somewhere else.
    ///
    /// Only the defaults can be moved from a test, and nothing in
    /// `RegionClock` reads them — which is the assertion, not an inconvenience
    /// being worked around.
    private func underDeviceZone(_ name: String, _ body: () -> Void) {
        guard let zone = TimeZone(identifier: name) else {
            Issue.record("no time zone \(name)")
            return
        }
        let previous = NSTimeZone.default
        NSTimeZone.default = zone
        defer { NSTimeZone.default = previous }
        body()
    }

    // MARK: - the table

    @Test("the five regions name the five zones")
    func theFive() {
        #expect(RegionClock.japan.timeZone.identifier == "Asia/Tokyo")
        #expect(RegionClock.taiwan.timeZone.identifier == "Asia/Taipei")
        #expect(RegionClock.hongKong.timeZone.identifier == "Asia/Hong_Kong")
        #expect(RegionClock.macao.timeZone.identifier == "Asia/Macau")
        #expect(RegionClock.korea.timeZone.identifier == "Asia/Seoul")
        #expect(RegionClock.all.count == 5)
    }

    /// The offsets, read out of the database rather than off the constants, so
    /// that this fails if a device's zone data ever disagrees with what the
    /// fallback claims — which is the only way the parachute could be wrong.
    @Test("the offsets are the ones these regions have kept")
    func offsets() {
        let now = Self.evening
        for clock in RegionClock.all {
            #expect(
                clock.timeZone.secondsFromGMT(for: now) == clock.fixedOffsetSeconds,
                "\(clock.regionCode) offset")
        }
        #expect(RegionClock.japan.utcOffsetText(at: now) == "UTC+9")
        #expect(RegionClock.korea.utcOffsetText(at: now) == "UTC+9")
        #expect(RegionClock.taiwan.utcOffsetText(at: now) == "UTC+8")
        #expect(RegionClock.hongKong.utcOffsetText(at: now) == "UTC+8")
        #expect(RegionClock.macao.utcOffsetText(at: now) == "UTC+8")
    }

    /// None of the five observes summer time, so no journey's day can be
    /// ambiguous and no printed stop time can land in a skipped hour. Asserted
    /// rather than assumed: this is the test that notices the year one of them
    /// adopts it.
    @Test("none of the five is on summer time")
    func noDaylightSaving() {
        for clock in RegionClock.all {
            #expect(
                clock.timeZone.nextDaylightSavingTimeTransition(after: Self.evening) == nil,
                "\(clock.regionCode) has a DST transition ahead")
        }
    }

    @Test("a region code names its clock, and anything else is Japan")
    func lookup() {
        #expect(RegionClock.forRegionCode("tw") == .taiwan)
        #expect(RegionClock.forRegionCode("HK") == .hongKong)
        #expect(RegionClock.forRegionCode("mo") == .macao)
        #expect(RegionClock.forRegionCode("kr") == .korea)
        #expect(RegionClock.forRegionCode("jp") == .japan)
        // The same fallback `Region.resolved` and `createBlankTrain` make: a
        // ride drawn against Japan's package is dated on Japan's clock.
        #expect(RegionClock.forRegionCode(nil) == .japan)
        #expect(RegionClock.forRegionCode("") == .japan)
        #expect(RegionClock.forRegionCode("cn") == .japan)
    }

    // MARK: - an instant, and the day it falls on

    /// 23:30 in Taipei is already the next day in Tokyo, and the day before in
    /// Los Angeles. Three regions, three answers, one instant.
    @Test("the day is the region's, not the device's")
    func theDayIsTheRegions() {
        for zone in ["UTC", "Asia/Tokyo", "America/Los_Angeles", "Pacific/Auckland"] {
            underDeviceZone(zone) {
                #expect(RegionClock.japan.civilDate(at: Self.evening) == "2026-08-28")
                #expect(RegionClock.korea.civilDate(at: Self.evening) == "2026-08-28")
                #expect(RegionClock.taiwan.civilDate(at: Self.evening) == "2026-08-27")
                #expect(RegionClock.hongKong.civilDate(at: Self.evening) == "2026-08-27")
                #expect(RegionClock.macao.civilDate(at: Self.evening) == "2026-08-27")
            }
        }
    }

    /// A device set to a non-Gregorian calendar still writes `2026-08-28`:
    /// jsonspec's `date` is not a localized string.
    @Test("the calendar is Gregorian whatever the device's is")
    func gregorian() {
        #expect(RegionClock.japan.calendar.identifier == .gregorian)
        #expect(RegionClock.japan.components(at: Self.evening).year == 2026)
    }

    @Test("a date and the first instant of it agree")
    func startOfDayRoundTrips() {
        for clock in RegionClock.all {
            for date in ["2026-01-01", "2026-08-27", "2026-12-31", "2028-02-29"] {
                guard let start = clock.startOfDay(date) else {
                    Issue.record("no start of \(date) in \(clock.regionCode)")
                    continue
                }
                #expect(clock.civilDate(at: start) == date, "\(date) in \(clock.regionCode)")
            }
        }
    }

    /// `undated` and `__all__` are buckets, not days.
    @Test("what is not a date has no first instant")
    func startOfDayRejectsNonDates() {
        for value in ["undated", "__all__", "", "2026-8-27", "tomorrow"] {
            #expect(RegionClock.japan.startOfDay(value) == nil, "\(value)")
        }
        #expect(RegionClock.japan.startOfDay(nil) == nil)
    }

    // MARK: - the questions the app asks

    /// The regression this file exists for. At 16:30 in London a Tokyo journey
    /// dated the 27th is over — Japan reached the 28th ninety minutes ago —
    /// and the app used to keep it in 「これから」 for another seven hours.
    @Test("a journey stops being upcoming when its own day ends")
    func upcomingFollowsTheRide() {
        underDeviceZone("Europe/London") {
            let japan = RegionClock.japan
            #expect(japan.isUpcoming("2026-08-27", at: Self.evening) == false)
            #expect(japan.hasPassed("2026-08-27", at: Self.evening))
            #expect(japan.isUpcoming("2026-08-28", at: Self.evening))

            // The same instant, a Taiwanese ride: Taipei is still on the 27th,
            // so the ride is still ahead. One store, two answers.
            let taiwan = RegionClock.taiwan
            #expect(taiwan.isUpcoming("2026-08-27", at: Self.evening))
            #expect(taiwan.hasPassed("2026-08-27", at: Self.evening) == false)
        }
    }

    /// Both answer `true` for today, and that is deliberate: a day is the
    /// finest grain a record's `date` has.
    @Test("today is both upcoming and already happened")
    func todayIsBoth() {
        let clock = RegionClock.japan
        let today = clock.today(at: Self.evening)
        #expect(clock.isUpcoming(today, at: Self.evening))
        #expect(clock.isTodayOrEarlier(today, at: Self.evening))
        #expect(clock.hasPassed(today, at: Self.evening) == false)
    }

    /// An undated record has no position on a calendar, so it is neither ahead
    /// nor behind. Not a negation of one another.
    @Test("an undated record is neither upcoming nor past")
    func undatedIsNeither() {
        let clock = RegionClock.japan
        for value in ["undated", "__all__", ""] {
            #expect(clock.isUpcoming(value, at: Self.evening) == false, "\(value)")
            #expect(clock.hasPassed(value, at: Self.evening) == false, "\(value)")
            #expect(clock.isTodayOrEarlier(value, at: Self.evening) == false, "\(value)")
        }
    }

    /// A day, not an instant: a journey stays upcoming for the whole of its own
    /// day rather than retiring at 00:01.
    @Test("a journey is upcoming all day, not until midnight")
    func upcomingLastsTheDay() {
        let clock = RegionClock.japan
        // 23:59 on the 27th in Tokyo.
        let lateInTokyo = instant("2026-08-27T14:59:00Z")
        #expect(clock.civilDate(at: lateInTokyo) == "2026-08-27")
        #expect(clock.isUpcoming("2026-08-27", at: lateInTokyo))
    }

    // MARK: - the seam cross-zone support will use

    /// One clock per journey today. These three members are the whole of what
    /// changes when that stops being true, and they are asserted so that the
    /// change cannot land half-done.
    @Test("every stop of a journey is on one clock")
    func journeyIsSingleZone() {
        let journey = JourneyClock(regionCode: "tw")
        #expect(journey.home == .taiwan)
        #expect(journey.crossesTimeZones == false)
        // Including indices no stop exists at: there is no index at which a
        // single-zone journey could answer differently.
        for index in [-1, 0, 1, 7, 9_999] {
            #expect(journey.clock(atStopIndex: index) == .taiwan, "stop \(index)")
        }
        #expect(journey.offsetMinutes(fromStopIndex: 0, toStopIndex: 9) == 0)
    }

    @Test("a journey answers the day questions on its own clock")
    func journeyForwards() {
        let japan = JourneyClock(regionCode: "jp")
        let taiwan = JourneyClock(regionCode: "tw")
        #expect(japan.today(at: Self.evening) == "2026-08-28")
        #expect(taiwan.today(at: Self.evening) == "2026-08-27")
        #expect(japan.isUpcoming("2026-08-27", at: Self.evening) == false)
        #expect(taiwan.isUpcoming("2026-08-27", at: Self.evening))
        #expect(japan.hasPassed("2026-08-27", at: Self.evening))
        #expect(taiwan.isTodayOrEarlier("2026-08-27", at: Self.evening))
    }

    /// A journey whose record names no region is Japanese, exactly as it is
    /// drawn and measured.
    @Test("a journey with no region is on Japan's clock")
    func journeyFallsBackToJapan() {
        #expect(JourneyClock(regionCode: nil).home == .japan)
        #expect(JourneyClock(regionCode: "").home == .japan)
    }

    // MARK: - what the interface prints

    @Test("each clock carries a key and an English fallback")
    func names() {
        for clock in RegionClock.all {
            #expect(clock.name.key == clock.nameKey)
            #expect(clock.name.fallback == clock.fallbackName)
            #expect(clock.nameKey.hasPrefix("ios.clock.zone"))
            // A trailing region code would be read as a country VARIANT by
            // `countryText` and answered by the wrong region's selection.
            for region in RegionClock.all {
                #expect(clock.nameKey.hasSuffix(".\(region.regionCode)") == false)
            }
        }
    }
}
