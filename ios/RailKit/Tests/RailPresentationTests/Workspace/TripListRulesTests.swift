import Foundation
import RailCore
import Testing

@testable import RailPresentation

struct TripListRulesTests {

    /// `2026-09-07T10:00:00+09:00` — 10:00 in Tokyo, 09:00 in Taipei.
    private static let tokyoMorning = Date(timeIntervalSince1970: 1_788_742_800)

    private func minutes(_ count: Double) -> Date {
        Self.tokyoMorning.addingTimeInterval(count * 60)
    }

    private func train(
        date: String? = "2026-09-07",
        region: String = "jp",
        departure: String? = "11:00",
        arrival: String? = "12:00",
        list: TripListMembership? = nil
    ) -> Train {
        var train = Train(
            id: "t", date: date, number: "1", origin: "A", destination: "B",
            stops: [
                Stop(name: "A", departure: departure, rideSegment: true),
                Stop(name: "B", arrival: arrival, rideSegment: true),
            ],
            region: region)
        train.listMembership = list
        return train
    }

    // MARK: - filing a new trip

    @Test("a trip whose departure is still ahead is filed as upcoming")
    func futureDepartureIsUpcoming() {
        #expect(TripListRules.initialMembership(
            for: train(), clock: .japan, now: Self.tokyoMorning) == .upcoming)
    }

    @Test("a trip that already departed today is filed as past")
    func pastDepartureIsPast() {
        #expect(TripListRules.initialMembership(
            for: train(departure: "09:59", arrival: "12:00"),
            clock: .japan, now: Self.tokyoMorning) == .past)
    }

    @Test("the trip's region clock decides, not UTC or the device")
    func regionClockDecides() {
        // 09:30 departs before 10:00 in Tokyo, but after 09:00 in Taipei.
        let trip = train(region: "tw", departure: "09:30", arrival: "10:30")
        #expect(TripListRules.initialMembership(
            for: trip, clock: .japan, now: Self.tokyoMorning) == .past)
        #expect(TripListRules.initialMembership(
            for: trip, clock: .taiwan, now: Self.tokyoMorning) == .upcoming)
    }

    @Test("without a departure the first arrival, then the end of the day, is the start")
    func missingTimesFallBack() {
        let arrivalOnly = train(departure: nil, arrival: "09:00")
        #expect(TripListRules.initialMembership(
            for: arrivalOnly, clock: .japan, now: Self.tokyoMorning) == .past)
        let untimed = train(departure: nil, arrival: nil)
        #expect(TripListRules.initialMembership(
            for: untimed, clock: .japan, now: Self.tokyoMorning) == .upcoming)
        #expect(TripListRules.initialMembership(
            for: train(date: "2026-09-06", departure: nil, arrival: nil),
            clock: .japan, now: Self.tokyoMorning) == .past)
    }

    @Test("an undated trip is filed as past")
    func undatedIsPast() {
        #expect(TripListRules.initialMembership(
            for: train(date: nil), clock: .japan, now: Self.tokyoMorning) == .past)
    }

    @Test("a departure past 24:00 belongs to the next day")
    func crossDayDeparture() {
        // Dated the 6th, departing 25:30 — 01:30 on the 7th, already gone.
        let gone = train(date: "2026-09-06", departure: "25:30", arrival: "27:00")
        #expect(TripListRules.initialMembership(
            for: gone, clock: .japan, now: Self.tokyoMorning) == .past)
        // Dated the 6th, departing 34:00 — 10:00 on the 7th... plus one minute.
        let ahead = train(date: "2026-09-06", departure: "34:01", arrival: "35:00")
        #expect(TripListRules.initialMembership(
            for: ahead, clock: .japan, now: Self.tokyoMorning) == .upcoming)
        #expect(TripListRules.initialMembership(
            for: train(date: "2026-09-06", departure: "10:01+1", arrival: nil),
            clock: .japan, now: Self.tokyoMorning) == .upcoming)
    }

    // MARK: - list membership

    @Test("a stored membership wins over the date")
    func storedMembershipWins() {
        #expect(TripListRules.isUpcoming(
            train(date: "2026-01-01", list: .upcoming), today: "2026-09-07"))
        #expect(!TripListRules.isUpcoming(
            train(date: "2027-01-01", list: .past), today: "2026-09-07"))
        #expect(TripListRules.isUpcoming(train(date: nil, list: .upcoming), today: nil))
    }

    @Test("a legacy record keeps the date rule")
    func legacyDateRule() {
        #expect(TripListRules.isUpcoming(train(date: "2026-09-07"), today: "2026-09-07"))
        #expect(!TripListRules.isUpcoming(train(date: "2026-09-06"), today: "2026-09-07"))
        #expect(!TripListRules.isUpcoming(train(date: nil), today: "2026-09-07"))
        #expect(!TripListRules.isUpcoming(train(date: "2026-09-07"), today: nil))
    }

    // MARK: - overdue

    @Test("an upcoming trip is overdue once its arrival has passed")
    func overdueAfterArrival() {
        let trip = train(list: .upcoming)
        #expect(!TripListRules.isOverdue(trip, clock: .japan, now: minutes(119)))
        #expect(TripListRules.isOverdue(trip, clock: .japan, now: minutes(120)))
    }

    @Test("a past trip is never overdue")
    func pastNeverOverdue() {
        #expect(!TripListRules.isOverdue(
            train(date: "2026-09-01", list: .past), clock: .japan, now: Self.tokyoMorning))
    }

    @Test("a stored-upcoming trip from an earlier day is overdue")
    func earlierDayOverdue() {
        #expect(TripListRules.isOverdue(
            train(date: "2026-09-01", list: .upcoming), clock: .japan, now: Self.tokyoMorning))
    }

    @Test("a legacy trip from today is overdue after its time, until the date rule drops it")
    func legacyTodayOverdue() {
        let trip = train(departure: "08:00", arrival: "09:00")
        #expect(TripListRules.isOverdue(trip, clock: .japan, now: Self.tokyoMorning))
        #expect(!TripListRules.isOverdue(
            train(date: "2026-09-06", departure: "08:00", arrival: "09:00"),
            clock: .japan, now: Self.tokyoMorning))
    }

    @Test("an end past 24:00 keeps an overnight trip from being overdue too soon")
    func overnightEnd() {
        // Dated the 6th, 23:00 → 34:30 (10:30 on the 7th).
        let overnight = train(
            date: "2026-09-06", departure: "23:00", arrival: "34:30", list: .upcoming)
        #expect(!TripListRules.isOverdue(overnight, clock: .japan, now: Self.tokyoMorning))
        #expect(TripListRules.isOverdue(overnight, clock: .japan, now: minutes(30)))
    }

    @Test("an end written earlier than the start without +1 is read as the next day")
    func wrappedEnd() {
        let wrapped = train(
            date: "2026-09-06", departure: "23:40", arrival: "00:20", list: .upcoming)
        let end = TripListRules.end(of: wrapped, clock: .japan)
        let start = TripListRules.start(of: wrapped, clock: .japan)
        #expect(end != nil && start != nil)
        if let end, let start { #expect(end.timeIntervalSince(start) == 40 * 60) }
    }

    @Test("the list start and end come from the boarding and alighting stops")
    func midTrainBoarding() {
        var mid = train(list: .upcoming)
        mid.stops = (0..<5).map { index in
            var stop = Stop(name: "S\(index)")
            stop.departure = String(format: "%02d:00", 8 + index)
            stop.arrival = String(format: "%02d:00", 8 + index)
            stop.rideSegment = (1...3).contains(index)
            return stop
        }
        mid.stops[1].stopType = "origin"
        mid.stops[3].stopType = "destination"
        let start = TripListRules.start(of: mid, clock: .japan)!
        let end = TripListRules.end(of: mid, clock: .japan)!
        #expect(end.timeIntervalSince(start) == 2 * 3600)
        mid.stops[1].actualDeparture = "09:30"
        let actualStart = TripListRules.start(of: mid, clock: .japan)!
        #expect(start.timeIntervalSince(actualStart) == -30 * 60)
        // An import with no types starts at its first ridden stop.
        for index in mid.stops.indices { mid.stops[index].stopType = ""; mid.stops[index].actualDeparture = nil
            mid.stops[index].rideSegment = index >= 2 }
        let imported = TripListRules.start(of: mid, clock: .japan)!
        #expect(imported.timeIntervalSince(start) == 3600)
    }

    @Test("without times the end of the date is the end")
    func untimedEnd() {
        let untimed = train(departure: nil, arrival: nil, list: .upcoming)
        #expect(!TripListRules.isOverdue(untimed, clock: .japan, now: Self.tokyoMorning))
        // Midnight in Tokyo is 14 hours after 10:00.
        #expect(TripListRules.isOverdue(untimed, clock: .japan, now: minutes(14 * 60)))
        #expect(!TripListRules.isOverdue(
            train(date: nil, list: .upcoming), clock: .japan, now: Self.tokyoMorning))
    }

    // MARK: - an untouched placeholder time is a date only

    private func byDate(_ train: Train) -> Train {
        var train = train
        train.listByDate = true
        return train
    }

    @Test("a date-only trip later today is upcoming although its placeholder clock has passed")
    func dateOnlyTodayIsUpcoming() {
        let placeholder = byDate(train(departure: "09:00", arrival: "09:00"))
        #expect(TripListRules.initialMembership(
            for: placeholder, clock: .japan, now: Self.tokyoMorning) == .upcoming)
        #expect(TripListRules.initialMembership(
            date: "2026-09-07", startClock: nil, clock: .japan, now: Self.tokyoMorning) == .upcoming)
    }

    @Test("a date-only trip on an earlier date is past although its placeholder clock is late")
    func dateOnlyYesterdayIsPast() {
        let placeholder = byDate(train(date: "2026-09-06", departure: "23:00", arrival: "23:00"))
        #expect(TripListRules.initialMembership(
            for: placeholder, clock: .japan, now: Self.tokyoMorning) == .past)
        #expect(TripListRules.initialMembership(
            date: "2026-09-06", startClock: nil, clock: .japan, now: Self.tokyoMorning) == .past)
    }

    @Test("a time that was set keeps the exact-time rule")
    func setTimeUsesExactRule() {
        #expect(TripListRules.initialMembership(
            date: "2026-09-07", startClock: "09:59", clock: .japan, now: Self.tokyoMorning) == .past)
        #expect(TripListRules.initialMembership(
            date: "2026-09-07", startClock: "10:01", clock: .japan, now: Self.tokyoMorning) == .upcoming)
        #expect(TripListRules.initialMembership(
            date: nil, startClock: "10:01", clock: .japan, now: Self.tokyoMorning) == .past)
    }

    @Test("a date-only upcoming trip is overdue only after its date ends")
    func dateOnlyOverdueAtEndOfDate() {
        let placeholder = byDate(train(departure: "09:00", arrival: "09:00", list: .upcoming))
        #expect(!TripListRules.isOverdue(placeholder, clock: .japan, now: Self.tokyoMorning))
        #expect(!TripListRules.isOverdue(placeholder, clock: .japan, now: minutes(14 * 60 - 1)))
        #expect(TripListRules.isOverdue(placeholder, clock: .japan, now: minutes(14 * 60)))
        // The same clocks, set by the reader, are overdue already.
        #expect(TripListRules.isOverdue(
            train(departure: "09:00", arrival: "09:00", list: .upcoming),
            clock: .japan, now: Self.tokyoMorning))
    }

    // MARK: - observed times

    @Test("an actual departure outranks the scheduled one when filing")
    func actualDepartureDecidesFiling() {
        // Scheduled 11:00 is still ahead at 10:00, but the reader recorded leaving at 09:55.
        var late = train()
        late.stops[0].actualDeparture = "9:55"
        #expect(TripListRules.initialMembership(for: late, clock: .japan, now: Self.tokyoMorning) == .past)
    }

    @Test("an actual arrival decides when an upcoming trip is overdue")
    func actualArrivalDecidesOverdue() {
        var delayed = train(departure: "9:00", arrival: "9:30", list: .upcoming)
        #expect(TripListRules.isOverdue(delayed, clock: .japan, now: Self.tokyoMorning))
        delayed.stops[1].actualArrival = "10:30"
        #expect(!TripListRules.isOverdue(delayed, clock: .japan, now: Self.tokyoMorning))
    }

    @Test("observed clocks count on a trip filed by its date alone")
    func actualTimesCountOnADateOnlyTrip() {
        var dated = train(departure: "0:00", arrival: "0:00")
        dated.listByDate = true
        #expect(TripListRules.initialMembership(for: dated, clock: .japan, now: Self.tokyoMorning) == .upcoming)
        dated.stops[0].actualDeparture = "9:00"
        #expect(TripListRules.initialMembership(for: dated, clock: .japan, now: Self.tokyoMorning) == .past)
    }

    @Test("a late actual departure with a scheduled arrival does not wrap to the next day")
    func lateActualDepartureKeepsTheEndOnTheSameDay() {
        var late = train(departure: "10:00", arrival: "10:10", list: .upcoming)
        late.stops[0].actualDeparture = "10:15"
        #expect(TripListRules.end(of: late, clock: .japan) == minutes(15))
        #expect(!TripListRules.isOverdue(late, clock: .japan, now: minutes(14)))
        #expect(TripListRules.isOverdue(late, clock: .japan, now: minutes(20)))
        #expect(TripListRules.isOverdue(late, clock: .japan, now: minutes(30)))
    }

    @Test("a mixed-kind end keeps the midnight wrap of its own kind")
    func mixedKindEndWrapsPastMidnight() {
        let day = RegionClock.japan.startOfDay("2026-09-06")!
        var lateStart = train(date: "2026-09-06", departure: "23:40", arrival: "00:20", list: .upcoming)
        lateStart.stops[0].actualDeparture = "23:45"
        #expect(TripListRules.end(of: lateStart, clock: .japan) == day.addingTimeInterval((24 * 60 + 20) * 60))

        var lateArrival = train(date: "2026-09-06", departure: "23:40", arrival: "00:20", list: .upcoming)
        lateArrival.stops[1].actualArrival = "0:25"
        #expect(TripListRules.end(of: lateArrival, clock: .japan) == day.addingTimeInterval((24 * 60 + 25) * 60))

        var sameDay = train(date: "2026-09-06", departure: "10:00", arrival: "10:10", list: .upcoming)
        sameDay.stops[0].actualDeparture = "10:15"
        #expect(TripListRules.end(of: sameDay, clock: .japan) == day.addingTimeInterval(615 * 60))
    }

    @Test("a middle stop's actual departure is ignored for the list start")
    func middleActualIgnored() {
        var trip = Train(
            id: "m", date: "2026-09-06", number: "1", origin: "A", destination: "C",
            stops: [
                Stop(name: "A", departure: "10:00", stopType: "origin", rideSegment: true),
                Stop(name: "B", departure: "10:30", actualDeparture: "10:45", rideSegment: true),
                Stop(name: "C", arrival: "11:00", stopType: "destination", rideSegment: true),
            ])
        trip.listMembership = .upcoming
        let day = RegionClock.japan.startOfDay("2026-09-06")!
        #expect(TripListRules.start(of: trip, clock: .japan) == day.addingTimeInterval(600 * 60))
        trip.stops[0].actualDeparture = "10:05"
        #expect(TripListRules.start(of: trip, clock: .japan) == day.addingTimeInterval(605 * 60))
    }

    @Test("a middle stop's actual arrival is ignored for the list end")
    func middleActualArrivalIgnored() {
        let trip = Train(
            id: "e", date: "2026-09-06", number: "1", origin: "A", destination: "C",
            stops: [
                Stop(name: "A", departure: "10:00", stopType: "origin", rideSegment: true),
                Stop(name: "B", arrival: "10:30", actualArrival: "10:40", rideSegment: true),
                Stop(name: "C", arrival: "11:00", stopType: "destination", rideSegment: true),
            ])
        let day = RegionClock.japan.startOfDay("2026-09-06")!
        #expect(TripListRules.end(of: trip, clock: .japan) == day.addingTimeInterval(660 * 60))
    }
}
