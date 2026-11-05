import Foundation
import Testing

@testable import RailCore

/// One ride-duration rule for the dashboard and the passport (audit A1).
///
/// A record whose end is still before its start after the single overnight wrap
/// (`23:50+1` -> `00:20`) is a data error. It used to add a negative number to
/// the dashboard total while the passport filtered it out.
struct RideDurationTests {

    private static func train(
        _ id: String, from: String, to: String, date: String = "2026-08-27"
    ) -> Train {
        Train(
            id: id, date: date, number: id, origin: "A", destination: "B",
            stops: [
                Stop(name: "A", departure: from, stopType: "origin", rideSegment: true),
                Stop(name: "B", arrival: to, stopType: "destination", rideSegment: true),
            ])
    }

    @Test("a span still negative after one overnight wrap is not a duration")
    func negativeSpanIsNil() {
        #expect(Statistics.trainRideMinutes(Self.train("N", from: "23:50+1", to: "00:20")) == nil)
        #expect(Statistics.trainRideMinutes(Self.train("N2", from: "24:30", to: "00:10")) == nil)
    }

    @Test("the dashboard total equals the passport total for a data-error record")
    func sumSkipsNegativeSpan() {
        let n = Self.train("N", from: "23:50+1", to: "00:20")
        let p = Self.train("P", from: "10:00", to: "11:00")
        #expect(Statistics.sumRideMinutes([n, p]) == 60)
    }

    @Test("the dashboard sum follows the passport rule on a mixed set")
    func sumMatchesPassportRule() {
        let trains = [
            Self.train("A", from: "10:00", to: "11:30"),
            Self.train("Z", from: "12:00", to: "12:00"),
            Self.train("N", from: "23:50+1", to: "00:20"),
            Self.train("O", from: "23:50", to: "00:20"),
            Self.train("U", from: "", to: ""),
        ]
        let passport = trains.compactMap { Statistics.trainRideMinutes($0) }
            .filter { $0 > 0 }
            .reduce(0, +)
        #expect(Statistics.sumRideMinutes(trains) == passport)
        #expect(passport == 120)
    }

    @Test("an ordinary overnight ride still wraps once")
    func overnightWrapStillWorks() {
        #expect(Statistics.trainRideMinutes(Self.train("O", from: "23:50", to: "00:20")) == 30)
    }

    @Test("a cross-zone ride is corrected by the offset between its boundary stops")
    func crossZoneCorrection() {
        let date = "2026-08-27"
        let train = Train(
            id: "X", date: date, number: "X", origin: "A", destination: "B",
            stops: [
                Stop(name: "A", departure: "10:00", stopType: "origin", rideSegment: true),
                Stop(name: "B", arrival: "11:00", stopType: "destination", rideSegment: true),
            ])
        let clock = JourneyClock(stops: [.japan, .taiwan], fallback: .japan, on: date)
        #expect(clock.crossesTimeZones)
        #expect(Statistics.trainRideMinutes(train, clock: clock) == 120)
    }

    @Test("the correction uses the first and last ridden stops, not stop 0 and the end")
    func riddenSubrangeCorrection() {
        let date = "2026-08-27"
        let train = Train(
            id: "R", date: date, number: "R", origin: "A", destination: "C",
            stops: [
                Stop(name: "A", departure: "09:00", stopType: "origin", rideSegment: false),
                Stop(name: "B", departure: "10:00", rideSegment: true),
                Stop(name: "C", arrival: "11:00", stopType: "destination", rideSegment: true),
            ])
        let clock = JourneyClock(
            stops: [.taiwan, .japan, .japan], fallback: .japan, on: date)
        #expect(clock.crossesTimeZones)
        #expect(Statistics.trainRideMinutes(train, clock: clock) == 60)
    }

    @Test("a single-clock journey answers exactly the one-argument form")
    func homeOnlyClockIsIdentity() {
        let trains = [
            Self.train("A", from: "10:00", to: "11:30"),
            Self.train("O", from: "23:50", to: "00:20"),
            Self.train("N", from: "23:50+1", to: "00:20"),
            Self.train("U", from: "", to: ""),
        ]
        let clock = JourneyClock(home: .japan)
        for train in trains {
            let plain = Statistics.trainRideMinutes(train)
            let zoned = Statistics.trainRideMinutes(train, clock: clock)
            #expect(plain?.bitPattern == zoned?.bitPattern)
        }
    }
}
