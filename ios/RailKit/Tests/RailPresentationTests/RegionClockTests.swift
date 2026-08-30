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

    /// The five whose region IS their clock, and which of the seven those
    /// are. The United States and Canada are in ``RegionClock/all`` too, and
    /// they are not in this list on purpose: what they name is a DEFAULT for a
    /// record with no station this build can place, not the zone their
    /// journeys are read on. See ``fiveSingleZoneRegions``.
    private static let fiveSingleZoneRegions: [RegionClock] = [
        .japan, .taiwan, .hongKong, .macao, .korea,
    ]

    @Test("each region names its zone")
    func theTable() {
        #expect(RegionClock.japan.timeZone.identifier == "Asia/Tokyo")
        #expect(RegionClock.taiwan.timeZone.identifier == "Asia/Taipei")
        #expect(RegionClock.hongKong.timeZone.identifier == "Asia/Hong_Kong")
        #expect(RegionClock.macao.timeZone.identifier == "Asia/Macau")
        #expect(RegionClock.korea.timeZone.identifier == "Asia/Seoul")
        #expect(RegionClock.unitedStates.timeZone.identifier == "America/New_York")
        #expect(RegionClock.canada.timeZone.identifier == "America/Toronto")
        #expect(RegionClock.all.count == 7)
        // Every region the catalog knows has a clock, and no two share a code.
        #expect(Set(RegionClock.all.map(\.regionCode)).count == RegionClock.all.count)
    }

    /// The offsets, read out of the database rather than off the constants, so
    /// that this fails if a device's zone data ever disagrees with what the
    /// fallback claims — which is the only way the parachute could be wrong.
    @Test("the offsets are the ones these regions have kept")
    func offsets() {
        let now = Self.evening
        for clock in Self.fiveSingleZoneRegions {
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

    /// None of the five Asian regions observes summer time, so no journey
    /// inside one of them can have an ambiguous day and no printed stop time
    /// can land in a skipped hour. Asserted rather than assumed: this is the
    /// test that notices the year one of them adopts it.
    ///
    /// The United States and Canada are excluded, and it is worth writing down
    /// why rather than leaving it to the list: they DO observe summer time,
    /// which is exactly why their clock is per station and read on the
    /// journey's own date. The assertion for them is the opposite one, and it
    /// is in ``offsetDependsOnTheDate``.
    @Test("none of the five Asian regions is on summer time")
    func noDaylightSaving() {
        for clock in Self.fiveSingleZoneRegions {
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
        #expect(RegionClock.forRegionCode("us") == .unitedStates)
        #expect(RegionClock.forRegionCode("CA") == .canada)
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

    // MARK: - a journey that stays on one clock

    /// Every journey in the five Asian packages, and most in the two North
    /// American ones. It must keep costing nothing: a single-zone journey that
    /// started answering through a per-stop table would pay for a lookup at
    /// every stop to be told what its region already said.
    @Test("every stop of a journey is on one clock")
    func journeyIsSingleZone() {
        let journey = JourneyClock(regionCode: "tw")
        #expect(journey.home == .taiwan)
        #expect(journey.crossesTimeZones == false)
        #expect(journey.stops.isEmpty)
        // Including indices no stop exists at: there is no index at which a
        // single-zone journey could answer differently.
        for index in [-1, 0, 1, 7, 9_999] {
            #expect(journey.clock(atStopIndex: index) == .taiwan, "stop \(index)")
        }
        #expect(journey.offsetMinutes(
            fromStopIndex: 0, toStopIndex: 9, on: "2026-08-27") == 0)
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

    // MARK: - a journey that changes clock

    /// Chicago to Seattle, which is what the *Empire Builder* does. Its two
    /// zones are two hours apart all year — both observe summer time — so this
    /// is the case where the correction is a constant and the arithmetic can
    /// be checked without the daylight-saving question getting in the way.
    @Test("a journey across two zones reports both, and the offset between")
    func crossesTwoZones() {
        let chicago = RegionClock.forZone("America/Chicago", regionCode: "us")
        let seattle = RegionClock.forZone("America/Los_Angeles", regionCode: "us")
        let journey = JourneyClock(
            stops: [chicago, chicago, seattle, seattle], fallback: .unitedStates)
        #expect(journey.crossesTimeZones)
        #expect(journey.home == chicago)
        #expect(journey.clock(atStopIndex: 0) == chicago)
        #expect(journey.clock(atStopIndex: 3) == seattle)
        // Off the end answers the journey's own clock rather than trapping.
        #expect(journey.clock(atStopIndex: 99) == chicago)
        // Westbound: the arrival is printed on a clock two hours behind, so
        // two hours must be SUBTRACTED from the departure to compare them.
        #expect(journey.offsetMinutes(
            fromStopIndex: 0, toStopIndex: 3, on: "2026-08-27") == -120)
        #expect(journey.offsetMinutes(
            fromStopIndex: 3, toStopIndex: 0, on: "2026-08-27") == 120)
        #expect(journey.offsetMinutes(
            fromStopIndex: 0, toStopIndex: 1, on: "2026-08-27") == 0)
    }

    /// A journey whose stops are all on one clock is a single-clock journey
    /// however the caller happened to build it. Otherwise every North American
    /// ride would report `crossesTimeZones`, and the note under its stop list
    /// would name the same zone twice.
    @Test("a table with one zone in it collapses")
    func tableOfOneZoneCollapses() {
        let boston = RegionClock.forZone("America/New_York", regionCode: "us")
        let journey = JourneyClock(
            stops: [boston, boston, boston], fallback: .unitedStates)
        #expect(journey.crossesTimeZones == false)
        #expect(journey.stops.isEmpty)
        #expect(journey.home == boston)
    }

    /// Two identifiers, one clock — and this is not hypothetical, it is what
    /// the shipped North American packages carry.
    ///
    /// `stations-us.json` files Rouses Point, New York under
    /// `America/New_York` and `stations-ca.json` files Rouses Point, Québec —
    /// the other side of the same border crossing, one section along the
    /// *Adirondack* — under `America/Toronto`, because that is what each
    /// railway publishes about its own stations. Both are Eastern time, all
    /// year, to the second.
    ///
    /// Collapsing on the zone IDENTIFIER made both shipped cross-border
    /// samples report `crossesTimeZones`, and the note under their stop lists
    /// then read "this journey crosses time zones (departs Eastern Time,
    /// arrives Eastern Time)" — the sentence
    /// ``tableOfOneZoneCollapses`` exists to prevent.
    @Test("two names for one clock are one clock")
    func sameOffsetDifferentIdentifier() {
        let newYork = RegionClock.forZone("America/New_York", regionCode: "us")
        let toronto = RegionClock.forZone("America/Toronto", regionCode: "ca")
        let journey = JourneyClock(
            stops: [newYork, toronto], fallback: .unitedStates, on: "2026-08-19")
        #expect(journey.crossesTimeZones == false)
        #expect(journey.stops.isEmpty)
        #expect(journey.home == newYork)
        #expect(journey.offsetMinutes(
            fromStopIndex: 0, toStopIndex: 1, on: "2026-08-27") == 0)
        // In January too — they keep the same rules as well as the same
        // offset, which is the difference between this and Phoenix/Denver.
        #expect(JourneyClock(
            stops: [newYork, toronto], fallback: .unitedStates, on: "2026-01-15")
            .crossesTimeZones == false)
        // And with no date at all, which is what an undated record gets.
        #expect(JourneyClock(stops: [newYork, toronto], fallback: .unitedStates)
            .crossesTimeZones == false)
    }

    /// The *Adirondack*, as its stops actually reach the clock table: sixteen
    /// American stations on `America/New_York`, then Rouses Point, St-Lambert
    /// and Montréal Central on `America/Toronto`. One clock from end to end,
    /// and the note under the list says so.
    @Test("a border crossing on one clock reports one clock")
    func adirondackDoesNotCrossZones() {
        let newYork = RegionClock.forZone("America/New_York", regionCode: "us")
        let toronto = RegionClock.forZone("America/Toronto", regionCode: "ca")
        let adirondack = JourneyClock(
            stops: Array(repeating: newYork, count: 16) + Array(repeating: toronto, count: 3),
            fallback: .unitedStates,
            on: "2026-08-19")
        #expect(adirondack.crossesTimeZones == false)
        #expect(adirondack.clock(atStopIndex: 18).name.fallback == "Eastern Time")
        // The ported ride length is returned untouched, because there is no
        // clock change to correct for.
        #expect(adirondack.rideMinutes(660, stopCount: 19, on: "2026-08-19") == 660)
    }

    /// Same offset, different name, and they stay two clocks.
    ///
    /// Phoenix keeps Mountain STANDARD time all year and Denver does not, so
    /// in January they read alike and in July they do not. Collapsing them in
    /// January would print one journey's times under a zone name that is
    /// wrong for half its stops — which is why the reading a stop is on is
    /// only half the test, and what it is CALLED is the other half.
    @Test("one offset under two names is still two clocks")
    func sameOffsetDifferentName() {
        let phoenix = RegionClock.forZone("America/Phoenix", regionCode: "us")
        let denver = RegionClock.forZone("America/Denver", regionCode: "us")
        let january = JourneyClock(
            stops: [phoenix, denver], fallback: .unitedStates, on: "2026-01-15")
        #expect(january.crossesTimeZones)
        #expect(january.offsetMinutes(
            fromStopIndex: 0, toStopIndex: 1, on: "2026-01-15") == 0)
        let july = JourneyClock(
            stops: [phoenix, denver], fallback: .unitedStates, on: "2026-07-04")
        #expect(july.crossesTimeZones)
    }

    /// Two zones the app has no name for are told apart by their identifiers,
    /// because that is the only thing left to tell them apart by — an unnamed
    /// zone carries its own identifier as its name.
    @Test("two unnamed zones an hour apart stay two clocks")
    func unnamedZonesStaySeparate() {
        let paris = RegionClock.forZone("Europe/Paris", regionCode: "us")
        let london = RegionClock.forZone("Europe/London", regionCode: "us")
        let journey = JourneyClock(stops: [paris, london], fallback: .unitedStates)
        #expect(journey.crossesTimeZones)
        #expect(journey.offsetMinutes(
            fromStopIndex: 0, toStopIndex: 1, on: "2026-08-27") == -60)
    }

    /// Arizona keeps standard time all year and Colorado does not, so the
    /// difference between Phoenix and Denver is an hour in July and nothing in
    /// January. This is why the offset takes the journey's own date.
    @Test("the offset is asked on the journey's own day")
    func offsetDependsOnTheDate() {
        let phoenix = RegionClock.forZone("America/Phoenix", regionCode: "us")
        let denver = RegionClock.forZone("America/Denver", regionCode: "us")
        let journey = JourneyClock(stops: [phoenix, denver], fallback: .unitedStates)
        #expect(journey.offsetMinutes(
            fromStopIndex: 0, toStopIndex: 1, on: "2026-07-04") == 60)
        #expect(journey.offsetMinutes(
            fromStopIndex: 0, toStopIndex: 1, on: "2026-01-15") == 0)
    }

    /// The correction `Statistics.trainRideMinutes` cannot make for itself.
    @Test("a westbound ride is longer than its printed times say")
    func rideMinutesCorrected() {
        let chicago = RegionClock.forZone("America/Chicago", regionCode: "us")
        let seattle = RegionClock.forZone("America/Los_Angeles", regionCode: "us")
        let westbound = JourneyClock(
            stops: [chicago, seattle], fallback: .unitedStates)
        let eastbound = JourneyClock(
            stops: [seattle, chicago], fallback: .unitedStates)
        // 46 hours of printed difference is 48 hours of travelling.
        #expect(westbound.rideMinutes(2_760, stopCount: 2, on: "2026-08-27") == 2_880)
        // …and the other way round it is 44.
        #expect(eastbound.rideMinutes(2_760, stopCount: 2, on: "2026-08-27") == 2_640)
        // A journey on one clock is returned untouched, and an unanswerable
        // one stays unanswerable.
        #expect(JourneyClock(regionCode: "jp")
            .rideMinutes(120, stopCount: 8, on: "2026-08-27") == 120)
        #expect(westbound.rideMinutes(nil, stopCount: 2, on: "2026-08-27") == nil)
    }

    /// A zone the app has no name for still produces a working clock rather
    /// than being silently read on the wrong one.
    @Test("an unnamed zone is described by its own identifier")
    func unknownZoneStillWorks() {
        let sydney = RegionClock.forZone("Australia/Sydney", regionCode: "us")
        #expect(sydney.timeZone.identifier == "Australia/Sydney")
        #expect(sydney.name.fallback == "Australia/Sydney")
        // Nonsense falls back to the region's own clock, not to Sydney.
        #expect(RegionClock.forZone("Mars/Olympus", regionCode: "us") == .unitedStates)
        #expect(RegionClock.forZone(nil, regionCode: "ca") == .canada)
        #expect(RegionClock.forZone("", regionCode: "ca") == .canada)
    }

    /// The two North American defaults exist, are Eastern, and are the answer
    /// a record with no station this build can place gets.
    @Test("the North American regions name a default clock")
    func northAmericanDefaults() {
        #expect(RegionClock.forRegionCode("us") == .unitedStates)
        #expect(RegionClock.forRegionCode("ca") == .canada)
        #expect(RegionClock.unitedStates.timeZone.identifier == "America/New_York")
        #expect(RegionClock.canada.timeZone.identifier == "America/Toronto")
        // Summer time is the database's business, and it is doing it.
        let july = instant("2026-07-04T12:00:00Z")
        let january = instant("2026-01-15T12:00:00Z")
        #expect(RegionClock.unitedStates.utcOffsetText(at: july) == "UTC-4")
        #expect(RegionClock.unitedStates.utcOffsetText(at: january) == "UTC-5")
    }
}
