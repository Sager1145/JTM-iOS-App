import Foundation
import RailCore
import Testing

@testable import RailPresentation

/// What the passport is allowed to count.
///
/// The rule this file exists for is a negative one: **no date appears in it.**
/// A journey enters the statistics because the record says it was ridden, and
/// for no other reason — so the tests below never construct a clock, and the
/// one that names dates proves they make no difference.
struct RideLedgerTests {

    private func stop(_ name: String, ridden: Bool, type: String = "passenger_stop") -> Stop {
        Stop(name: name, arrival: "10:00", departure: "10:01", stopType: type, rideSegment: ridden)
    }

    private func train(_ stops: [Stop], date: String? = "2026-08-01") -> Train {
        Train(
            id: "t1", date: date, number: "1", origin: stops.first?.name ?? "",
            destination: stops.last?.name ?? "", stops: stops)
    }

    // MARK: - reading the record

    /// What every store written by an older build says, and the reason no
    /// migration was needed: `ride_segment` has always been true throughout.
    @Test("a journey with every call ridden is counted")
    func allRidden() {
        let journey = train([
            stop("A", ridden: true), stop("B", ridden: true), stop("C", ridden: true),
        ])
        #expect(RideLedger.hasBeenRidden(journey))
        #expect(RideLedger.confirmation(of: journey) == .ridden)
        #expect(RideLedger.riddenSegmentCount(journey.stops) == 2)
    }

    @Test("a journey with no call ridden is not counted")
    func noneRidden() {
        let journey = train([
            stop("A", ridden: false), stop("B", ridden: false), stop("C", ridden: false),
        ])
        #expect(RideLedger.hasBeenRidden(journey) == false)
        #expect(RideLedger.confirmation(of: journey) == .notRidden)
        #expect(RideLedger.riddenSegmentCount(journey.stops) == 0)
    }

    /// Boarding halfway. The record is not a plan and not a whole journey, and
    /// it has to be counted for the part that happened.
    @Test("a partly ridden journey is counted, and says it is partial")
    func partlyRidden() {
        let journey = train([
            stop("A", ridden: false), stop("B", ridden: true), stop("C", ridden: true),
        ])
        #expect(RideLedger.hasBeenRidden(journey))
        #expect(RideLedger.confirmation(of: journey) == .partly)
        #expect(RideLedger.riddenSegmentCount(journey.stops) == 1)
    }

    /// Two ridden calls with an unridden one between them bound no ridden
    /// interval, so the journey carries no distance — and must not be counted
    /// as a journey either, or 旅程數 would name a record the total beside it
    /// does not include.
    @Test("ridden calls that bound no interval count as nothing")
    func scatteredFlagsCountNothing() {
        let journey = train([
            stop("A", ridden: true), stop("B", ridden: false), stop("C", ridden: true),
        ])
        #expect(RideLedger.riddenSegmentCount(journey.stops) == 0)
        #expect(RideLedger.hasBeenRidden(journey) == false)
        // Not `.partly`: nothing of it is being counted.
        #expect(RideLedger.confirmation(of: journey) == .notRidden)
    }

    /// A pass-through inherits the interval it lies in, which is the ported
    /// rule (`Statistics.effectiveStopRide`) and the reason the flag on a
    /// rolled-through station is not consulted on its own.
    @Test("a pass-through inherits the interval it lies in")
    func passThroughInherits() {
        let ridden = train([
            stop("A", ridden: true),
            stop("B", ridden: false, type: "pass_through"),
            stop("C", ridden: true),
        ])
        #expect(RideLedger.hasBeenRidden(ridden))

        let plan = train([
            stop("A", ridden: false),
            stop("B", ridden: true, type: "pass_through"),
            stop("C", ridden: false),
        ])
        #expect(RideLedger.hasBeenRidden(plan) == false)
    }

    @Test("a journey with fewer than two calls is counted as nothing")
    func tooFewStops() {
        #expect(RideLedger.riddenSegmentCount([]) == 0)
        #expect(RideLedger.riddenSegmentCount([stop("A", ridden: true)]) == 0)
    }

    // MARK: - the rule has no clock in it

    /// The regression this whole change is: the answer must not move with the
    /// date, in either direction. A journey dated far in the future and marked
    /// ridden is counted; one dated years ago and not confirmed is not.
    @Test("the date changes nothing")
    func dateIsIrrelevant() {
        let dates: [String?] = ["1999-01-01", "2026-08-28", "2099-12-31", "undated", nil, ""]
        for date in dates {
            let confirmed = train(
                [stop("A", ridden: true), stop("B", ridden: true)], date: date)
            let unconfirmed = train(
                [stop("A", ridden: false), stop("B", ridden: false)], date: date)
            #expect(RideLedger.hasBeenRidden(confirmed), "\(date ?? "nil")")
            #expect(RideLedger.hasBeenRidden(unconfirmed) == false, "\(date ?? "nil")")
        }
    }

    // MARK: - what the button commits

    @Test("confirming marks every call, including pass-throughs")
    func confirmMarksEverything() {
        let journey = train([
            stop("A", ridden: false),
            stop("B", ridden: false, type: "pass_through"),
            stop("C", ridden: false),
        ])
        let confirmed = RideLedger.setRidden(journey, true)
        #expect(confirmed.stops.filter(\.rideSegment).count == confirmed.stops.count)
        #expect(RideLedger.confirmation(of: confirmed) == .ridden)
        // And nothing else about the record moved.
        #expect(confirmed.id == journey.id)
        #expect(confirmed.date == journey.date)
        #expect(confirmed.stops.map(\.name) == journey.stops.map(\.name))
        #expect(confirmed.stops.map(\.stopType) == journey.stops.map(\.stopType))
    }

    @Test("un-confirming writes a plan")
    func unconfirmWritesAPlan() {
        let journey = train([stop("A", ridden: true), stop("B", ridden: true)])
        let plan = RideLedger.setRidden(journey, false)
        #expect(plan.stops.filter(\.rideSegment).isEmpty)
        #expect(RideLedger.hasBeenRidden(plan) == false)
    }

    /// Confirming a partly-ridden journey commits the whole of it. The reader
    /// pressing the button is saying they made the journey; keeping an
    /// interval switched off would answer a question they did not ask.
    @Test("confirming a partly ridden journey commits all of it")
    func confirmOverwritesPartial() {
        let journey = train([
            stop("A", ridden: false), stop("B", ridden: true), stop("C", ridden: true),
        ])
        #expect(RideLedger.confirmation(of: RideLedger.setRidden(journey, true)) == .ridden)
    }

    @Test("setting a state twice is the same as setting it once")
    func idempotent() {
        let journey = train([stop("A", ridden: false), stop("B", ridden: true)])
        for ridden in [true, false] {
            let once = RideLedger.setRidden(journey, ridden)
            #expect(RideLedger.setRidden(once, ridden).stops == once.stops)
        }
    }
}
