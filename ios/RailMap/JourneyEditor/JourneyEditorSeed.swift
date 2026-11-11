import Foundation
import RailCore

/// What the editor's header fields showed when the draft opened.
///
/// A saved journey keeps every value the reader leaves alone: a field is
/// written back only when it differs from its seed. A new trip writes them all.
///
/// Every `Date` here is a real instant read on the trip region's calendar
/// (`RegionClock.calendar`), never the device's.
struct EditorSeed: Equatable {
    var trainType: String
    var number: String
    var company: String
    var departure: Date
    var arrival: Date
    /// The saved journey carried this clock. A placeholder clock is never written back.
    var departureKnown: Bool
    var arrivalKnown: Bool
    /// The saved boarding departure / final arrival text, exactly as stored.
    /// Set only when it parsed.
    var departureText: String?
    var arrivalText: String?

    init(train: Train, isNew: Bool, clock: RegionClock, now: Date = Date()) {
        let type = train.trainType ?? ""
        if isNew {
            trainType = JourneyDraftWork.serviceTypeIDs.contains(type) ? type : "local"
            number = ""
            company = ""
            // The editor's clocks are the trip region's wall clock, so the
            // placeholder is "now" itself: the pickers show that instant in the
            // region's zone. The device's own day can be a day behind it (New
            // York evening is the next morning in Tokyo), and a date-only trip
            // filed on that day would land in History.
            departure = now
            arrival = now
            departureKnown = false
            arrivalKnown = false
            return
        }
        trainType = type
        number = train.number
        company = train.company ?? ""
        let day = Dates.normalizeDateString(train.date)
        let start = day.flatMap { clock.instant(serviceDate: $0, clock: "00:00") }
        // Minute precision: the editor's pickers and delta maths ignore seconds.
        func minute(_ d: Date?) -> Date? {
            d.map { clock.calendar.dateInterval(of: .minute, for: $0)?.start ?? $0 }
        }
        let leaving = minute(day.flatMap { day in
            train.stops.first?.departure.flatMap { clock.instant(serviceDate: day, clock: $0) }
        })
        let arriving = minute(day.flatMap { day in
            train.stops.last?.arrival.flatMap { clock.instant(serviceDate: day, clock: $0) }
        })
        departure = leaving ?? start ?? now
        arrival = max(arriving ?? departure, departure)
        departureKnown = leaving != nil
        arrivalKnown = arriving != nil
        departureText = leaving != nil ? train.stops.first?.departure : nil
        arrivalText = arriving != nil ? train.stops.last?.arrival : nil
    }
}
