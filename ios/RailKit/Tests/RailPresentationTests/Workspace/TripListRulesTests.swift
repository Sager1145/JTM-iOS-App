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

    @Test("without times the end of the date is the end")
    func untimedEnd() {
        let untimed = train(departure: nil, arrival: nil, list: .upcoming)
        #expect(!TripListRules.isOverdue(untimed, clock: .japan, now: Self.tokyoMorning))
        // Midnight in Tokyo is 14 hours after 10:00.
        #expect(TripListRules.isOverdue(untimed, clock: .japan, now: minutes(14 * 60)))
        #expect(!TripListRules.isOverdue(
            train(date: nil, list: .upcoming), clock: .japan, now: Self.tokyoMorning))
    }
}
